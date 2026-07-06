# Audio Asset Policy

This repository is designed to work with local audio assets, but it should not include copyrighted source tracks or generated clips.

## Local Directories

Put source files here:

```text
Samples/hajimi-local/raw/
```

Generated clips are written here:

```text
Samples/hajimi-local/clips/
```

Both directories are ignored by git except for `.gitkeep`.

## Segment Plan

The repository does include:

```text
Samples/hajimi-local/segment-plan.json
```

This file records the intended source filenames, cut points, durations, fades, and output paths. It is safe to version because it does not include audio data.

If someone clones the project, they need to provide local WAV files with matching names or edit the segment plan to match their own assets.
