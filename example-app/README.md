# Example App for `@capgo/capacitor-downloader`

This Vite project links directly to the local plugin source so you can exercise the native APIs while developing.

## Actions in this playground

- **Start download** – Starts a background download (native platforms).
- **Check status** – Queries progress for an existing download id.
- **Pause download** – Pauses a running download (Android).
- **Resume download** – Resumes a paused download (Android).
- **Stop download** – Stops a download task.
- **Get file info** – Reads metadata for a downloaded file.

## Getting started

```bash
npm install
npm start
```

Add native shells with `npx cap add ios` or `npx cap add android` from this folder to try behaviour on device or simulator.
