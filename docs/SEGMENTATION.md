# Segmentation Guide

The project treats shortcut sounds as short musical phrases, not arbitrary fixed-length clips.

## Good Cuts

A good segment has:

- a clear entry point
- a complete motif or phrase
- a natural ending or low-energy boundary
- a short fade only when needed to smooth the phrase tail

## Bad Cuts

Avoid:

- cutting all tracks to the same duration
- ending in the middle of a vocal syllable
- ending during an unresolved melodic line
- using fade-out to hide a bad cut

## Workflow

1. Start the editor:

```sh
make segment-ui
```

2. Pick a segment.
3. Preview the source interval.
4. Adjust `start`, `duration`, `fadeIn`, `fadeOut`, and `volume`.
5. Save and recut.
6. Trigger the shortcut in the app.

## Rule of Thumb

Shortcut feedback can be longer than UI bleeps. For this project, 3-13 seconds can be reasonable when the phrase deserves it.
