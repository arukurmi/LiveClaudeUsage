# Reset time on the bar

**Date:** 2026-07-11
**Status:** Implemented

## Goal

Show when the 5-hour usage window resets, directly on the bar, so a glance tells
you both how much you've used and when it comes back.

## Design

- **Which time:** the wall-clock reset time from the API's `five_hour.resets_at`
  field, formatted in the local timezone as `h:mma` (e.g. `4:30PM`).
- **Placement:** rotated 90° so it reads bottom-to-top, anchored just above the
  bottom edge of the bar, centered across the bar's width.
- **Legibility in every colour:** white semibold text with a dark shadow halo —
  readable on all threshold colours (green/yellow/orange/red) and on the gray
  track when the fill is shorter than the text.
- **Config:** `showResetTime` boolean in `~/.config/claudebar/config.json`,
  default `true`.
- **States:** fresh and stale usage both show the time (a stale reset time is
  still correct). Error state hides it. Stale reset times restored from
  `UserDefaults` are only shown if still in the future.

## Components

- `ClaudeBarCore/UsageFetcher.swift` — `ResetTimeFormatter` (pure, testable;
  takes an injectable `TimeZone`).
- `ClaudeBarCore/BarConfig.swift` — `showResetTime` flag with partial-load and
  default handling.
- `claudebar/BarView.swift` — `DisplayState.usage`/`.stale` carry `resetsAt`;
  a rotated `CATextLayer` renders the time.
- `claudebar/UsagePoller.swift` — passes `resetsAt` through and persists it
  next to the last good percent for restart survival.
- `--demo` and `--fixed` modes fake a reset time 2.5h out for visual testing.

## Testing

- Unit: `ResetTimeFormatter` output (UTC-fixed), `showResetTime` config parsing.
- Visual: `--fixed 42` screenshot plus live run against the real API.
