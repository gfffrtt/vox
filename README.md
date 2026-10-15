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

Because the app is ad-hoc signed, macOS may forget the Accessibility grant after a rebuild.
If the shortcut stops working, remove Vox from System Settings → Privacy & Security → Accessibility and add it again.

## Settings (menu bar mic icon → Settings…)

- **API key**: stored in the macOS Keychain.
- **Model**: defaults to `gemini-3.8-flash`. Type any model ID, or press ↻ to load the models your key can use and pick one.
- **System prompt**: context about you and how the text should come out (e.g. "I'm a software engineer; keep technical terms exact").
- **Translation**: translates the transcript into a target language.
- **Behavior**: hold-to-talk or press to start/stop, and paste automatically or copy only.

The transcript is always left on the clipboard. You can copy it again with "Copy Last Transcript" in the menu.
