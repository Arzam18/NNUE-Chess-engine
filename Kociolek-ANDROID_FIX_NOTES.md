# Kociolek 2.3 — Android ARM64 self-contained NNUE build

## What this revision changes

The previous Android artifact shipped `quantised-v14.bin` beside the executable. That was not a self-contained engine and could fail when DroidFish launched the executable from a different directory. This revision embeds the original network bytes into a read-only ELF section at link time.

- `src/nnue_embed.S` uses assembler `.incbin` to include the repository's original `quantised-v14.bin` bytes in the executable.
- `src/uci.cpp` loads the embedded network before any external-file fallback.
- `NNUE::loadNetworkFromMemory()` validates and loads the embedded bytes using the exact tensor layout already defined in `src/config.h`.
- The existing 1,607,744-byte distributed file is accepted as 1,607,696 bytes of tensor payload plus 48 trailing alignment bytes. The tail is not interpreted as weights.
- The final ZIP contains the executable and build information only; it intentionally contains no `.bin` companion network.
- The policy networks continue to use the project's existing generated embedded headers.

## Search startup

`uci` still reports the engine identity normally. Startup must additionally print:

`info string Loading embedded NNUE quantised-v14.bin (1607744 bytes)...`

`info string NNUE loaded: embedded quantised-v14.bin file_bytes=1607744 payload_bytes=1607696 padding_bytes=48 hidden=1024 buckets=8`

`info string NNUE ready; search enabled`

If these messages are absent, the Android binary is not the embedded build or the build failed to include the expected network. A valid `go depth 8` should produce search `info` lines followed by a legal `bestmove`.

## Build requirements

The repository must contain the original, unmodified files:

- `quantised-v14.bin`
- `Policy-big.bin`
- `quantised-64.bin`

The workflow validates the NNUE file size and embeds its bytes. It does not download, rewrite, truncate, or alter the network. The artifact is self-contained with respect to the NNUE and policy networks.

## Android target

- AArch64 / Android API 24
- ARMv8-A NEON (`-march=armv8-a+simd`)
- No Dotprod claim
- One search thread, preserving the original setting

## Validation limits

The source changes and packaging scripts require a real GitHub Actions run with the repository's real network files, followed by a Galaxy A16 DroidFish UCI test. Do not treat a host build with synthetic weights as evidence of chess strength. Confirm startup messages, `isready` / `readyok`, `position startpos`, `go depth 8`, search info, and a legal `bestmove` before strength testing.
