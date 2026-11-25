# Maestro flows (capacitor-downloader)

Native Android checks for OkHttp batches. Build and install the example app first (`example-app/`), then run flows from the repo root.

## Prerequisites

- [Maestro CLI](https://maestro.mobile.dev/) installed
- Example app synced and installed on a device or emulator: `cd example-app && bun install && bun run build && bunx cap sync android`

## Flows

| Flow | Purpose |
| --- | --- |
| `android/okhttp-batch-success.yaml` | OkHttp batch `download()` resolves with `RUNNING` |
| `android/mixed-engine-batch-fail.yaml` | Mixed-engine batch rejects with the plugin error message |

## Run

```bash
./scripts/maestro/run-android-flows.sh
```

Or run a single flow:

```bash
maestro test .maestro/android/okhttp-batch-success.yaml
```

Each flow taps dedicated buttons in the example app (`maestro-okhttp-batch`, `maestro-mixed-batch-fail`) so the harness does not preset the plugin outcome.