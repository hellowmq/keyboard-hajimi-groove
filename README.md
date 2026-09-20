# Keyboard Hajimi Groove

[简体中文](README.zh-CN.md) | English

Keyboard Hajimi Groove is a macOS status bar app that turns common work shortcuts into local Hajimi-style musical “loot drop” feedback.

> Source release: the repository does not include audio tracks, a signed app bundle, or automatic updates. A fresh clone can build the app and verify shortcut handling, but audible feedback requires audio files you have the right to use.

It is intentionally shortcut-first:

- `Command+C`, `Command+V`, `Command+Z`, `Command+S`, `Command+F`, and similar workflow shortcuts can trigger short musical phrases.
- `F1-F12` can trigger function-key feedback.
- Ordinary typing does not trigger audio.
- Audio is loaded from local files, so you can use your own materials without bundling them into the app.

## Requirements

- macOS 14+
- Swift 6.3+
- Python 3 for the local segment tools
- `ffmpeg` for cutting local audio segments

## Quick Start

```sh
git clone https://github.com/hellowmq/keyboard-hajimi-groove.git
cd keyboard-hajimi-groove
make doctor
swift run keyboard-hajimi-groove
```

The app loads `Themes/shortcut-local-drops.json` by default and places a `哈` item in the macOS status bar.

On first launch, macOS may require Accessibility or Input Monitoring permission for the terminal app that starts the process.

If no audio files are present yet, the app will still launch but shortcuts will print missing-sample warnings instead of playing audio.

## Permission & privacy

The app uses a listen-only macOS event tap to observe global key-down and modifier events, then matches only configured shortcuts for playback and local aggregate analysis. It does not block or rewrite input. Grant Accessibility or Input Monitoring only on a Mac you control; quit the app and revoke the permission when you no longer need it.

The segment editor binds to `127.0.0.1` by default. Keep it local rather than exposing it to a public network. See [SECURITY.md](SECURITY.md) for private reporting guidance.

## Local Audio Assets

Source tracks are expected at:

```text
Samples/hajimi-local/raw/
```

Generated clips are written to:

```text
Samples/hajimi-local/clips/
```

These folders are git-ignored because they usually contain local or copyrighted audio. See `docs/ASSETS.md`.

## Segment Editing

The cut plan lives in:

```text
Samples/hajimi-local/segment-plan.json
```

Start the local web editor:

```sh
make segment-ui
```

Then open:

```text
http://127.0.0.1:8765
```

The editor lets you preview source intervals, adjust `start`, `duration`, `fadeIn`, `fadeOut`, and `volume`, then save and recut.

The status bar menu also has:

- `重新载入当前主题`
- `打开切片编辑器`
- `打印按键分析`
- `重置按键分析`

Command-line workflow:

```sh
make list-hajimi-segments
make recut-hajimi-one ID=drop-copy
make recut-hajimi
make validate-code
make validate-assets
make validate-hajimi
```

## Segmentation Philosophy

Do not cut every track to the same duration. Each segment should follow the source track’s phrase, hook, transition, cadence, or low-energy boundary.

See `docs/SEGMENTATION.md`.

## Development

```sh
swift test
make validate-code
```

Use `make validate-hajimi` only when local raw/clipped audio assets exist.

## License

Code is released under the [MIT License](LICENSE). Audio assets are not included and remain subject to their own rights.
