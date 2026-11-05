# Kociolek 2.3 — Embedded NNUE loader compile-flag fix

## Diagnosis from the Galaxy A16 Termux log

The engine printed neither `Loading embedded NNUE quantised-v14.bin` nor `NNUE loaded: embedded quantised-v14.bin`. It instead attempted `quantised-v14.bin` as a working-directory file and then an executable-directory file. This proves that the C++ embedded-NNUE startup branch guarded by `KOCIOLEK_EMBED_NNUE` was not active in the tested executable. The policy networks were embedded independently, which explains why their startup messages appeared.

The earlier build script put `-DKOCIOLEK_EMBED_NNUE=1` in the exported `CXXFLAGS`. The corrected build passes this as an explicit `CPPFLAGS` make argument and updates the Makefile recipe to include `$(CPPFLAGS)`. It also deletes the exact Android target before rebuilding, so an old target cannot be reused.

## Files changed

- `Makefile`: adds `CPPFLAGS` to the actual C++ compile command.
- `build-android-arm64.sh`: explicitly passes `-DKOCIOLEK_EMBED_NNUE=1`, removes stale output, checks for the embedded-loader message in the executable, and validates the embedded symbol size against the original network file.
- `.github/workflows/android.yml`: runs the corrected build and verifies the embedded-loader compile flag is recorded in build metadata.

No NNUE weights, search logic, evaluator math, policy model, thread count, or playing-strength behavior are changed. `src/nnue_embed.S` still embeds the repository's original `quantised-v14.bin` bytes unchanged. The external network is not packaged beside the final executable.

## Expected Termux startup

A correct new binary must print a line similar to:

`info string Loading embedded NNUE quantised-v14.bin (1607744 bytes)...`

followed by:

`info string NNUE loaded: embedded quantised-v14.bin file_bytes=1607744 payload_bytes=1607696 padding_bytes=48 hidden=1024 buckets=8`

and:

`info string NNUE ready; search enabled`

Then `go depth 8` must produce search `info` lines and a legal `bestmove`. Do not consider the engine fixed until this is confirmed on the phone.

## Build target

Android API 24, AArch64, ARMv8-A NEON (`-march=armv8-a+simd`), one search thread. This is not a Dotprod build.
