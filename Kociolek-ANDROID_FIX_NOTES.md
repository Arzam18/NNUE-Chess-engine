# Kociolek 2.3 — Android ARM64 NEON fix notes

## NNUE-size mismatch correction

The first Android validation expected the tensor payload size exactly:

`2 * (768 * 1024 + 1024 + 2 * 1024 * 8 + 8) = 1,607,696 bytes`

The distributed `quantised-v14.bin` reported by the user is `1,607,744` bytes. This is not a different tensor layout: `1,607,696` rounded up to a 64-byte file boundary is exactly `1,607,744`, leaving 48 trailing bytes. The original upstream loader reads the NNUE arrays sequentially and does not consume or interpret those trailing bytes.

The corrected loader, standalone build script, and GitHub Actions workflow now accept either:

- the raw NNUE tensor payload: `1,607,696` bytes; or
- the 64-byte-aligned file: `1,607,744` bytes.

The loader reads only the first `1,607,696` bytes into the declared tensors. It does not append the final 48 bytes to the weights, truncate or rewrite the user's network, or alter the original file. Any other size is rejected.

## Original runtime fault being addressed

The uploaded source's original `NNUE::loadNetwork()` returned `void`. On a failed open or incomplete read, `uci_loop()` could nevertheless report `NNUE loaded` and let search run using zero-filled or partially loaded evaluation arrays. The configured evaluation filename was also relative to the process working directory, which can differ from the executable's folder on Android.

That failure mode is consistent with repetitive first-legal pawn moves such as `1.a3 a6 2.a4 a5`, because an all-zero evaluation can leave root moves tied. It is a plausible diagnosis, not proof that the user's previous installation had a missing network. The real network must be checked in the UCI startup log.

## Changes included

1. `NNUE::loadNetwork()` returns success/failure, validates either supported file size, reads the tensor payload into a temporary heap buffer, and commits only after a complete read.
2. Android/Linux startup tries the configured network path from the process working directory, then tries the same filename beside `/proc/self/exe`.
3. Startup reports NNUE readiness only after a successful load.
4. `go`, `eval`, and `bench` refuse to operate without a valid NNUE. A failed `EvalFile` replacement does not overwrite a previously loaded network.
5. The standalone build script and GitHub Actions workflow use the same raw-or-64-byte-aligned size rule.
6. The build artifact contains the executable and original `quantised-v14.bin` side by side, and records the network SHA-256. The network is not modified by the workflow.

## Android NEON target

- ABI: AArch64 / `arm64-v8a`
- Android API: 24
- SIMD: baseline ARMv8-A NEON (`-march=armv8-a+simd`)
- No Dotprod claim is made.
- Search, evaluation formula, policy model, move ordering, thread count, and network bytes are not intentionally changed by this size correction.

## On-device verification

After extracting `Kociolek-2.3-Android-ARM64.zip`, keep these files together:

- `Kociolek-2.3-android-arm64`
- `quantised-v14.bin`

Run `uci`, `isready`, `eval`, then `position startpos` and `go depth 8`.

For the user's 1,607,744-byte file, startup should include a line similar to:

`info string NNUE loaded: /.../quantised-v14.bin file_bytes=1607744 payload_bytes=1607696 padding_bytes=48 hidden=1024 buckets=8`

and then:

`info string NNUE ready; search enabled`

The engine should not report a normal `bestmove` if NNUE loading failed. As an alternate path, use:

`setoption name EvalFile value /full/path/to/quantised-v14.bin`

## Validation status

The source fix and package checks are prepared, but the actual network binary was not included in the uploaded source ZIP and no Android NDK build or Galaxy A16 runtime/strength test has been performed in this environment. A synthetic zero-filled 1,607,744-byte file passed a host UCI test: the executable found it beside itself when launched from another working directory and reported the correct 48-byte tail. This validates size handling and path resolution only; it is not a chess network and cannot validate playing strength. Do not mark Kociolek successful until the Actions artifact loads the user's real file and its device UCI evaluation and opening play are checked.
