# Contributing

Thanks for improving Keyboard Hajimi Groove.

## Local Setup

Requirements:

- macOS 14+
- Swift 6+
- `ffmpeg`

Run:

```sh
swift test
make validate-hajimi
```

## Audio Assets

Do not commit copyrighted or large audio files.

Local assets belong in:

- `Samples/hajimi-local/raw`
- `Samples/hajimi-local/clips`

These directories are ignored by git except for `.gitkeep` placeholders.

## Segment Editing

Edit:

`Samples/hajimi-local/segment-plan.json`

Then run:

```sh
make recut-hajimi-one ID=drop-copy
```

or:

```sh
make recut-hajimi
```

Use the local web editor for faster iteration:

```sh
make segment-ui
```

## Segmentation Principles

Prefer musical phrase boundaries over uniform durations. Each source track should have its own cut based on motif, hook, transition, cadence, and low-energy boundaries.
