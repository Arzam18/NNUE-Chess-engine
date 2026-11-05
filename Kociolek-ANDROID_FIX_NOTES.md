# Kociolek Android ARM64 — build-script permission fix

## Cause
GitHub Actions failed with exit code 126 because the workflow invoked `./build-android-arm64.sh` directly while the file did not have its executable bit set in the checkout/archive.

## Fix
The workflow now has a dedicated `chmod +x ./build-android-arm64.sh` step and invokes the script with `bash ./build-android-arm64.sh`. Calling Bash explicitly is the important part: it does not depend on executable mode bits being preserved by ZIP extraction or Git metadata.

The NNUE embedding implementation, network file, Makefile, and engine source are otherwise unchanged from the preceding Compile-Flag-Fix package. This change addresses only the workflow's exit-126 permission failure. It does not establish that the new binary passes the NNUE load and UCI search test; that still needs to be verified from the next Actions run and Termux test.
