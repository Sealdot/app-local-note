# Contributing

See [Development and verification](docs/development.md) for build commands,
the release-state snapshot, and engineering documents. For README or media
changes, follow [the provenance and QA notes](docs/readme-media.md); never use
generated design references as product screenshots.

1. Create a branch from `main`.
2. Keep the application dependency-free unless a dependency has a measured
   memory, launch-time, and binary-size benefit.
3. Add or update tests for behavior changes.
4. Run `./scripts/verify.sh` and `./scripts/performance-smoke.sh` before opening
   a pull request.
5. Never add real Notion credentials or work content to fixtures.
