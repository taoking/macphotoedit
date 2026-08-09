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
must be reviewed. It downloads the official `XcodeGen` 2.46.0 release archive,
verifies SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`,
then places that binary on `PATH`; it does not float with Homebrew's latest
formula. `actions/checkout` is pinned to commit
`11bd71901bbe5b1630ceea73d27597364c9af683` (v4.2.2).

## What runs

For pushes to `main`, pull requests targeting `main`, and manual dispatches,
the workflow:

1. checks out the repository with read-only contents permission;
2. selects Xcode 26.6 and verifies the pinned XcodeGen 2.46.0 archive;
3. generates `MacPhotoStudio.xcodeproj`, fails if the committed
   `project.pbxproj` drifts, and runs the complete unsigned macOS unit-test
   suite; and
4. regenerates the project, repeats the drift check, and performs an unsigned
   Debug build.

Documentation-only and `plan.md` pushes do not schedule another macOS job.
The workflow uses no secrets, uploads no user media, and does not create or
retain test photos, RAW files, videos, databases, caches or DerivedData.

The GitHub-hosted job validates the software gate only. It does not replace the
real-media, physical-storage, display and permission checks recorded in
`docs/manual-validation.md`.

## Branch protection status

The GitHub Actions regression check exists, but it is not currently a required
pre-merge check. On 2026-08-09, the authenticated repository inspection for
`taoking/macphotoedit` reported `main` as unprotected and returned no applicable
repository rulesets. This is recorded as an observed personal-repository
configuration, not as a CI pass condition; enabling protection remains optional.
