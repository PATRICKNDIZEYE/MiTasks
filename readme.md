# miTasks

A floating desktop task widget for macOS. Click the bubble, capture the task,
tick it done. Electron + vanilla JS, no framework, no bundler.

## Running it

```sh
npm install
npm start          # compiles the native helper, then launches Electron
```

`npm start` unsets `ELECTRON_RUN_AS_NODE` first. Terminals hosted inside
Electron (VS Code and friends) leak that variable, and it silently turns
`electron .` into a plain Node run where `require('electron')` returns a path
string instead of the API.

Dev and the installed app share one data directory
(`~/Library/Application Support/miTasks`), and the single-instance lock lives
there too — so **quit `/Applications/miTasks.app` before `npm start`**, or the
dev copy will hand off to the installed one and exit.

## Building and installing

```sh
npm run pack         # → release/miTasks-darwin-arm64/miTasks.app
npm run install-app  # pack, quit any running copy, replace /Applications
```

`build/pack.js` assembles the bundle from `node_modules/electron/dist` rather
than using `@electron/packager`, which re-downloads and unzips a 99 MB archive
on every run — pathologically slow on this machine. It handles the three things
that are easy to get wrong:

- ships the Swift EventKit helper in `Contents/Resources`
- writes the Calendar usage strings into `Info.plist`; without them macOS
  never even offers the permission prompt
- recomputes `ElectronAsarIntegrity` from the asar *header* hash

It deliberately does **not** run `codesign --deep`. Sealing the bundle's
resources on an ad-hoc signature with no Team ID stops it launching through
LaunchServices, even though `codesign --verify` passes.

## Calendar

`native/mitasks-cal.swift` is a small EventKit bridge — one JSON payload per
invocation, exit code 2 meaning "not authorised yet".

```sh
./native/bin/mitasks-cal auth
./native/bin/mitasks-cal events --from 2026-09-07T00:00:00Z --to 2026-09-08T00:00:00Z
```

It reads whatever accounts Calendar.app already has, so nothing needs signing in
to twice. Grant access once from **Advanced › Calendar › Connect**.

There is no Developer ID on this machine, so the app is ad-hoc signed and its
code hash changes on every rebuild — macOS will re-ask for Calendar access after
each `npm run install-app`. If that gets tiresome, move the helper out to a
LaunchAgent so the grant lives with the helper instead of the app.

## Phone

The widget runs a small HTTP server on `:43917` that serves `mobile/index.html`
as an iPhone PWA, plus a JSON API and an SSE stream. Links are in
**Advanced › iPhone**.

## Layout

| File | Role |
| --- | --- |
| `main.js` | window, tray, reminders, IPC |
| `preload.js` | `window.api` bridge |
| `renderer/` | the whole desktop UI |
| `server.js` | phone sync server |
| `calendar.js` | cached, polled wrapper around the EventKit helper |
| `lockin.js` | `caffeinate` session |
| `native/` | Swift EventKit bridge |
| `build/` | packaging and install scripts |
