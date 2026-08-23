# Performance baseline

Measured on the development Mac on 2026-08-13 using an ad-hoc signed release
build produced by `scripts/package-app.sh`.

| Check | Observed | Budget |
|---|---:|---:|
| Packaged app size | 1.9 MB | < 5 MB |
| Idle resident memory after launch | 29,856 KB | < 128 MB smoke ceiling |
| Idle RSS growth over eight samples / 24 seconds | 0 KB | < 16 MB |
| Idle CPU sample | 0.0% | approximately 0% |
| Load today with 3,650 unrelated history files | < 1 second | < 1 second |
| Markdown encode/decode for 2,000 rows | included in 0.53 second performance suite | < 2 seconds |

The smoke script also samples the idle process eight times over 24 seconds and
fails if RSS grows by more than 16 MB during that interval. The RSS ceiling is
deliberately much higher than the current sample so tests
remain stable across macOS versions. The architectural guardrails are more
important than a single reading:

- no embedded Chromium or WebKit view;
- no recurring polling timer;
- one selected day retained in the model;
- one network request at a time;
- current-day payloads only;
- no third-party runtime dependencies.

Run the local sample again with:

```sh
./scripts/performance-smoke.sh
```
