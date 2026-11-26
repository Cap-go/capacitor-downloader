# Maestro flows (capacitor-downloader)

Native checks for multi-file batch downloads. Build and install the example app first (`example-app/`), then run flows from the repo root.

## Prerequisites

- [Maestro CLI](https://maestro.mobile.dev/) installed
- Plugin build from the repo root: `bun install && bun run build` (the example app depends on the local `file:..` package)
- Example app synced and installed on a device or emulator:
  - Android: `cd example-app && bun install && bun run build && bunx cap sync android`
  - iOS: `cd example-app && bun install && bun run build && bunx cap sync ios`

## Flows

| Flow | Platform | Purpose |
| --- | --- | --- |
| `android/okhttp-batch-success.yaml` | Android | OkHttp batch completes (`downloadCompleted`, per-file DONE, sizes in output) |
| `android/mixed-engine-batch-fail.yaml` | Android | Mixed-engine batch rejects with the plugin error message |
| `ios/ios-batch-success.yaml` | iOS | Multi-file batch completes (`downloadCompleted`, per-file DONE, sizes in output) |
| `ios/ios-batch-reject-url-and-files.yaml` | iOS | Rejects `url`+`destination` together with `files` (`Provide either url and destination or files, not both`) |

## Run

Android:

```bash
./scripts/maestro/run-android-flows.sh
```

iOS (local Mac with simulator or device):

```bash
./scripts/maestro/run-ios-flows.sh
```

Or from the repo root:

```bash
bun run verify:maestro:android
bun run verify:maestro:ios
```

Single flow:

```bash
maestro test .maestro/android/okhttp-batch-success.yaml
maestro test .maestro/ios/ios-batch-success.yaml
```

Each flow taps dedicated buttons in the example app so the harness does not preset the plugin outcome before `download()`.