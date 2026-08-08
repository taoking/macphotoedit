# Continuous integration

The public repository has a lightweight macOS GitHub Actions regression gate
at `.github/workflows/macos-regression.yml`.

## Supported runner matrix

| Environment | macOS runner | Xcode | Notes |
| --- | --- | --- | --- |
| Local development | developer Mac | 26.6 or later | Run the commands in `README.md`. |
| GitHub Actions | `macos-26` | 26.6 at `/Applications/Xcode_26.6.app` | The workflow selects this path explicitly. |

The workflow fixes the operating-system runner label and Xcode application
path so an image change cannot silently test with an older toolchain. If the
image no longer provides that application, CI fails visibly and the matrix
must be reviewed. `XcodeGen` is installed with Homebrew because it is not part
of the standard runner image.

## What runs

For pushes to `main`, pull requests targeting `main`, and manual dispatches,
the workflow:

1. checks out the repository with read-only contents permission;
2. selects Xcode 26.6 and installs XcodeGen;
3. generates `MacPhotoStudio.xcodeproj` and runs the complete unsigned macOS
   unit-test suite; and
4. regenerates the project and performs an unsigned Debug build.

Documentation-only and `plan.md` pushes do not schedule another macOS job.
The workflow uses no secrets, uploads no user media, and does not create or
retain test photos, RAW files, videos, databases, caches or DerivedData.

The GitHub-hosted job validates the software gate only. It does not replace the
real-media, physical-storage, display and permission checks recorded in
`docs/manual-validation.md`.
