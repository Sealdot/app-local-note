# Development and verification

## Build and run

Run these commands from a clone of this repository on macOS. The declared
minimum is macOS 11 with Swift 5.4 Command Line Tools; a full Xcode installation
is not needed for the direct compiler scripts. No third-party runtime
dependencies are required.

```sh
git clone https://github.com/Sealdot/app-local-note.git
cd app-local-note
./scripts/package-app.sh
open build/LocalNote.app
```

`package-app.sh` calls `build.sh release`, compiles arm64 and x86_64 targets,
combines them with `lipo`, bundles resources, and ad-hoc signs the application.
Expected output is `Packaged build/LocalNote.app`. Opening it adds a checklist
icon to the menu bar; it does not create a Dock icon or main window.

For a host-architecture debug executable:

```sh
./scripts/build.sh
./build/bin/LocalNote
```

With full Xcode, the Swift Package can also be built with `swift build`. That
alternate route was not exercised during the README review.

## Check changes

```sh
./scripts/test.sh
./scripts/verify.sh
```

> Before running `performance-smoke.sh`, save your records and quit all Local
> Note instances. The script selects and terminates processes by name and may
> affect an instance you use for daily work.

```sh
./scripts/performance-smoke.sh
```

`test.sh` compiles and runs the core and application regressions. `verify.sh`
runs tests, packages the app, checks plist/signature/architectures/resources,
and scans for credential patterns. The performance smoke run is required for
contributions by [CONTRIBUTING.md](../CONTRIBUTING.md); historical measurements
in [performance.md](performance.md) are not current-version benchmarks or
cross-device guarantees.

## Release state checked on 2026-09-28

- GitHub default branch: `main`; homepage README: root `README.md`.
- Application-source baseline, remote `main`, and release tag `v0.2.0`:
  `e342c66a2465ccd5ef84e1223221fbda48fa8acc`. Documentation updates live on
  `codex/readme-docs`; this source baseline is not the README
  update commit.
- [v0.2.0](https://github.com/Sealdot/app-local-note/releases/tag/v0.2.0) is a
  published, non-prerelease GitHub release, dated 2026-09-26. It contains
  `LocalNote-macOS.zip` and `LocalNote-macOS.zip.sha256`.
- The downloaded ZIP checksum passed; its binary has both arm64 and x86_64
  slices, bundle version 0.2.0, and minimum system version 11.0. Its ad-hoc
  signature verified. No Developer ID/notarized distribution is offered.
- Local packaging and the existing test suite passed on Apple Silicon,
  macOS 14.2.1, Swift 5.4 Command Line Tools. Intel/macOS 11 launch checks and
  live Notion validation were not performed.

`archive-release.sh` produces a local ZIP/checksum after verification; it does
not upload a release. Do not treat packaging as authorization to publish.

## Find engineering context

- [Architecture](architecture.md): native lifecycle, storage, sync, and budgets.
- [Test plan](test-plan.md): regression cases and synchronization fixtures.
- [Calendar design](calendar-overview.md): summaries and activity levels.
- [Appearance acceptance](theme-appearance-p0.md) and [historical design QA](../design-qa.md).
- [Outline hierarchy QA](design-qa-outline-hierarchy.md).
- [Milestones / deferred scope](implementation-plan.md): historical progress,
  not a promise that deferred capabilities already exist.
- [Icon rationale](icon-design.md): brand asset provenance.
- [README media and QA](readme-media.md): demonstration source, reproduction,
  recording instructions, and verification limits.

Read [CONTRIBUTING.md](../CONTRIBUTING.md) before submitting a change and
[SECURITY.md](../SECURITY.md) before using credentials or work records.
