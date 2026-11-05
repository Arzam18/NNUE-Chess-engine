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

python3 - <<'PY'
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
PY

export CXX CC
export AR="$TOOLCHAIN/llvm-ar"
export RANLIB="$TOOLCHAIN/llvm-ranlib"
export STRIP="$TOOLCHAIN/llvm-strip"
export PYTHON=python3
export CXXFLAGS='-std=c++17 -O3 -DNDEBUG -pthread -march=armv8-a+simd -mtune=cortex-a53 -static-libstdc++ -DKOCIOLEK_EMBED_NNUE=1'

# Assemble the original NNUE file directly into a read-only ELF section.
# No generated text header, runtime file lookup, or companion .bin is needed.
"$CC" -c -x assembler-with-cpp src/nnue_embed.S -o nnue_embed.o

make clean || true
make clean-embed || true
make -j2 \
    TARGET=Kociolek-2.3-android-arm64 \
    EXTRA_OBJECTS=nnue_embed.o \
    EVALFILE=quantised-v14.bin \
    POLICYFILE=Policy-big.bin \
    POLICYFILE_SMALL=quantised-64.bin \
    KOCIOLEK_POLICY_HL=2048 \
    POLICY_SMALL_HL=64

[[ -s Kociolek-2.3-android-arm64 ]] || { echo "ERROR: engine output is missing" >&2; exit 1; }
mkdir -p dist
cp Kociolek-2.3-android-arm64 dist/
chmod +x dist/Kociolek-2.3-android-arm64
file dist/Kociolek-2.3-android-arm64 | tee dist/build-info.txt
"$TOOLCHAIN/llvm-readelf" -h dist/Kociolek-2.3-android-arm64 >> dist/build-info.txt
grep -q 'AArch64' dist/build-info.txt
printf 'Embedded NNUE: quantised-v14.bin (%s bytes)\n' "$(stat -c%s quantised-v14.bin)" >> dist/build-info.txt
sha256sum quantised-v14.bin >> dist/build-info.txt
"$TOOLCHAIN/llvm-nm" Kociolek-2.3-android-arm64 | grep -E 'g_kociolek_nnue_(start|end)' >> dist/build-info.txt

# The network is embedded in the executable: deliberately package no .bin files.
(cd dist && zip -9 -j Kociolek-2.3-Android-ARM64.zip \
    Kociolek-2.3-android-arm64 build-info.txt)
echo "Build complete: $ROOT/dist/Kociolek-2.3-Android-ARM64.zip"
