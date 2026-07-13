# Mid-fill reset time + hover-to-hide collapse

**Date:** 2026-07-13
**Status:** Implemented

## Changes

1. **Reset time rides the fill.** Instead of sitting at the bottom, the rotated
   time label is centered at half the fill height, so a 20% bar shows it in the
   middle of that 20%, and it climbs as usage grows. Clamped so near-empty and
   near-full bars keep it fully on screen.

2. **Hover-to-hide.** The overlay stays click-through except while the pointer
   is over its frame (checked by a 0.15s poll of `NSEvent.mouseLocation` — no
   Accessibility permission needed, unlike global event monitors or synthetic
   events). Hovering reveals a dark **–** chip at the foot of the bar; clicking
   it collapses the whole window into a 16pt dot 8pt above the bottom corner of
   the same edge, tinted with the current threshold colour. Clicking the dot
   restores the bar. State persists in `UserDefaults` (`barCollapsed`).

## Testing

- Unit suite unchanged (33 assertions, all view logic is visual).
- Visual: screenshots of 20%/80% fixed bars (time position), `--hover` debug
  flag (chip), `barCollapsed` preset (dot), and the live bar after reinstall.
- Click-to-toggle needs a human hand: synthetic CGEvent clicks are dropped
  without Accessibility permission, so that path was verified by code review
  plus manual testing.
