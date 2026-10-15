# Vox

A macOS menu-bar push-to-talk dictation app. Hold **fn ⌘ E**, speak, release. The audio goes to Gemini, and the text is pasted into the app you're using.

## Build & run

```sh
./build.sh
open build/Vox.app
```

On first launch:
1. Grant **Accessibility** (needed for the global shortcut and for auto-paste).
2. Grant **Microphone**.
3. Paste your Gemini API key in Settings (get one at https://aistudio.google.com/apikey).

## Distributing

```sh
./make-dmg.sh   # → build/Vox-<version>.dmg
```

The DMG has the usual drag-to-Applications layout. The app is signed with the local self-signed identity,
not an Apple Developer ID, so on other Macs Gatekeeper blocks the first launch. Users can allow it in
**System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Vox.app`.

The app icon lives in `Resources/AppIcon.icns`; regenerate it with `swift scripts/make-icon.swift Resources/AppIcon.icns`.
The installer window background lives in `Resources/DMGBackground.tiff`; regenerate it with
`swift scripts/make-dmg-background.swift Resources/DMGBackground.tiff`.

`build.sh` signs the app with a self-signed "Vox Local Signing" identity (created on first build in
`~/Library/Keychains/vox-signing.keychain-db`), so the Accessibility grant survives rebuilds.

## Settings (menu bar mic icon → Settings…)

- **API key**: stored locally in the app's preferences (UserDefaults).
- **Model**: defaults to `gemini-3.8-flash`. Type any model ID, or press ↻ to load the models your key can use and pick one.
- **System prompt**: context about you and how the text should come out (e.g. "I'm a software engineer; keep technical terms exact").
- **Behavior**: hold-to-talk or press to start/stop, and paste automatically or copy only.

The transcript is always left on the clipboard. You can copy it again with "Copy Last Transcript" in the menu.
