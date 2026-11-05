#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

NDK="${NDK_PATH:-${ANDROID_NDK_LATEST_HOME:-}}"
if [[ -z "$NDK" || ! -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++" ]]; then
    SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
    NDK_ROOT="$SDK_ROOT/ndk"
    [[ -d "$NDK_ROOT" ]] || { echo "ERROR: Android NDK not found. Set NDK_PATH." >&2; exit 1; }
    NDK="$(find "$NDK_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
fi

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
CXX="$TOOLCHAIN/aarch64-linux-android24-clang++"
CC="$TOOLCHAIN/aarch64-linux-android24-clang"
[[ -x "$CXX" && -x "$CC" ]] || { echo "ERROR: Android API 24 AArch64 compiler not found" >&2; exit 1; }

for f in quantised-v14.bin Policy-big.bin quantised-64.bin; do
    [[ -s "$f" ]] || { echo "ERROR: Missing required network: $f" >&2; exit 1; }
done

python3 - <<'PY2'
from pathlib import Path
import re
config = Path("src/config.h").read_text(encoding="utf-8")
def value(name):
    m = re.search(rf"constexpr\s+usize\s+{name}\s*=\s*(\d+)", config)
    if not m: raise SystemExit(f"Cannot read {name} from src/config.h")
    return int(m.group(1))
payload = 2 * (value("INPUT_SIZE") * value("HL_SIZE") + value("HL_SIZE") +
               2 * value("HL_SIZE") * value("OUTPUT_BUCKETS") + value("OUTPUT_BUCKETS"))
padded = (payload + 63) & ~63
actual = Path("quantised-v14.bin").stat().st_size
print(f"NNUE input: {actual} bytes; tensor payload: {payload}; padded file: {padded}")
if actual not in (payload, padded):
    raise SystemExit("quantised-v14.bin does not match the NNUE layout")
PY2

export CXX CC
export AR="$TOOLCHAIN/llvm-ar"
export RANLIB="$TOOLCHAIN/llvm-ranlib"
export STRIP="$TOOLCHAIN/llvm-strip"
export PYTHON=python3
export CXXFLAGS='-std=c++17 -O3 -DNDEBUG -pthread -march=armv8-a+simd -mtune=cortex-a53 -static-libstdc++'

# IMPORTANT: CPPFLAGS is passed explicitly to make and consumed by the Makefile
# compile recipe. This guarantees that the C++ UCI code activates the embedded
# NNUE loader; defining the symbol only in the assembler object is not enough.
EMBED_CPPFLAGS='-DKOCIOLEK_EMBED_NNUE=1'

# Remove the exact Android target as well as the temporary assembly object so
# make cannot silently reuse a stale executable from an earlier run.
make clean TARGET=Kociolek-2.3-android-arm64
make clean-embed
rm -f Kociolek-2.3-android-arm64 nnue_embed.o

"$CC" -c -x assembler-with-cpp src/nnue_embed.S -o nnue_embed.o

make -j2 \
    TARGET=Kociolek-2.3-android-arm64 \
    CPPFLAGS="$EMBED_CPPFLAGS" \
    EXTRA_OBJECTS=nnue_embed.o \
    EVALFILE=quantised-v14.bin \
    POLICYFILE=Policy-big.bin \
    POLICYFILE_SMALL=quantised-64.bin \
    KOCIOLEK_POLICY_HL=2048 \
    POLICY_SMALL_HL=64

BIN="Kociolek-2.3-android-arm64"
[[ -s "$BIN" ]] || { echo "ERROR: engine output is missing" >&2; exit 1; }

# Fail the build if the C++ binary did not compile the embedded-NNUE startup
# branch, even if the raw network bytes happened to be linked by the assembler.
if ! strings -a "$BIN" | grep -Fq 'Loading embedded NNUE quantised-v14.bin'; then
    echo "ERROR: embedded NNUE loader is NOT compiled into the executable" >&2
    exit 1
fi
if ! strings -a "$BIN" | grep -Fq 'NNUE ready; search enabled'; then
    echo "ERROR: NNUE-ready startup path is missing from executable" >&2
    exit 1
fi

# Confirm the assembly object's NNUE start symbol describes the exact original
# network file size. This also detects a missing/empty .incbin payload.
NETWORK_SIZE="$(stat -c%s quantised-v14.bin)"
SYMBOL_SIZE="$("$TOOLCHAIN/llvm-nm" -S --defined-only "$BIN" | python3 -c 'import sys; rows=[x.split() for x in sys.stdin if x.split() and x.split()[-1] == "g_kociolek_nnue_start"]; print(int(rows[0][1], 16) if rows else "")')"
if [[ -z "$SYMBOL_SIZE" || "$SYMBOL_SIZE" -ne "$NETWORK_SIZE" ]]; then
    echo "ERROR: embedded NNUE symbol size ($SYMBOL_SIZE) does not match network ($NETWORK_SIZE)" >&2
    "$TOOLCHAIN/llvm-nm" -S --defined-only "$BIN" | grep g_kociolek_nnue || true
    exit 1
fi

mkdir -p dist
cp "$BIN" "dist/$BIN"
chmod +x "dist/$BIN"
file "dist/$BIN" | tee dist/build-info.txt
"$TOOLCHAIN/llvm-readelf" -h "dist/$BIN" >> dist/build-info.txt
grep -q 'AArch64' dist/build-info.txt
printf 'Embedded NNUE: quantised-v14.bin (%s bytes)\n' "$NETWORK_SIZE" >> dist/build-info.txt
sha256sum quantised-v14.bin >> dist/build-info.txt
"$TOOLCHAIN/llvm-nm" -S --defined-only "$BIN" | grep -E 'g_kociolek_nnue_(start|end)' >> dist/build-info.txt
printf 'Embedded loader compile flag: %s\n' "$EMBED_CPPFLAGS" >> dist/build-info.txt

# The final artifact is intentionally self-contained: no external .bin files.
(cd dist && zip -9 -j -FS Kociolek-2.3-Android-ARM64.zip "$BIN" build-info.txt)
echo "Build complete: $ROOT/dist/Kociolek-2.3-Android-ARM64.zip"
