# Kociolek 2.3 — Android ARM64 NEON fix notes

## Observed fault

The Android executable was reported to play a highly repetitive sequence such as `1.a3 a6 2.a4 a5`. The source archive's NNUE loader had a critical failure mode:

- `NNUE::loadNetwork()` logged that the evaluation network could not be opened or was incomplete, but it returned `void`.
- `uci_loop()` printed `info string NNUE loaded` unconditionally after calling it.
- The UCI `go` command still entered search even when the NNUE arrays were zero-filled or only partly read.
- The default `EVALFILE` is a relative filename. Android engine hosts may launch the executable with a working directory different from the directory containing the executable and network file.

When the evaluation is all zero, candidate moves tie. Root search begins with the first generated legal move as its fallback, so a first-legal move can remain selected. This is consistent with the reported opening behavior. It is not proof that the user's installed copy had a missing model; the startup diagnostic below will confirm that on-device.

## Changes made

1. `NNUE::loadNetwork()` now returns success/failure, validates the exact network byte count before touching live weights, reads into a temporary heap buffer, and commits the data only after the complete read succeeds.
2. NNUE startup first tries the configured file in the process working directory, then tries the same file beside `/proc/self/exe` (Android/Linux). This handles launchers that use a different current working directory.
3. Startup prints `NNUE ready; search enabled` only after a successful load. It no longer reports a false success.
4. `go` refuses to search without a valid NNUE and emits an explicit UCI diagnostic plus `bestmove 0000`. `eval` and `bench` also refuse to produce misleading zero-network results.
5. A failed `setoption name EvalFile` keeps the last successfully loaded network intact. A successful load resets the accumulator for the current board.
6. The Android workflow validates the evaluation network's byte count against the dimensions in `src/config.h` and still packages the NNUE companion file beside the executable. The archive must be extracted with both files kept together.

## Expected NNUE layout

The model layout used by the supplied source is:

- `INPUT_SIZE = 768`
- `HL_SIZE = 1024`
- `OUTPUT_BUCKETS = 8`
- 16-bit weights/biases

Expected size:

`2 * (768 * 1024 + 1024 + 2 * 1024 * 8 + 8) = 1,607,696 bytes`

The two policy networks are separate. The Makefile embeds those policy files in generated headers, while the NNUE evaluation file remains a runtime companion.

## On-device verification

After extracting `Kociolek-2.3-Android-ARM64.zip`, keep these files in the same folder:

- `Kociolek-2.3-android-arm64`
- `quantised-v14.bin`

Run `uci`, `isready`, `eval`, then `position startpos` and `go depth 8`.

A correct startup should include a line similar to:

`info string NNUE loaded: /.../quantised-v14.bin bytes=1607696 hidden=1024 buckets=8`

followed by:

`info string NNUE ready; search enabled`

If neither candidate path works, the engine will say `NNUE unavailable` at startup and refuse `go`; it will not silently play using a zero network. As an alternate path, send the UCI option:

`setoption name EvalFile value /full/path/to/quantised-v14.bin`

## Scope and validation

No evaluation formula, network data, legal move generation, move ordering, search heuristic, time management, or NEON arithmetic was changed.

Validation performed in this environment:

- Modified `nnue.cpp` and `uci.cpp` compile as C++17 translation units.
- All supplied C++ translation units compile and link into a host test executable.
- With no NNUE file available, the host executable reports the missing network and refuses search instead of returning a normal-looking move.
- With a synthetic all-zero file of the exact expected length placed beside the executable, running from a different working directory successfully finds and loads the sibling file. This validates path resolution only; the synthetic file is not a chess network and was not used for strength testing.
- Android workflow YAML parses successfully.

Not verified here: the actual official NNUE binary was not included in the uploaded ZIP, no Android NDK was available in this environment, and no Galaxy A16 runtime or strength test has been performed. The user must run the updated GitHub Actions workflow and test with the real `quantised-v14.bin` before the engine is marked successful.
