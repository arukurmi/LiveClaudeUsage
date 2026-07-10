# ClaudeBar — Live Claude Usage Edge Bar (Design Spec)

**Date:** 2026-07-10
**Status:** Approved for implementation
**Repo:** https://github.com/arukurmi/LiveClaudeUsage

## Problem

Checking Claude plan usage requires opening claude.ai → profile → usage (or running
`/usage` inside Claude Code). The user wants ambient, always-visible awareness of how
close they are to the 5-hour session limit, without any interaction.

## Solution

A tiny native macOS agent (Swift + AppKit, no Dock icon, no menu bar item) that draws a
thin (~6px) vertical bar hugging one screen edge (right by default, configurable). The
bar:

- fills bottom-up in proportion to `five_hour.utilization` (0–100%)
- shifts color green → yellow → orange → red as usage grows
- shows a small emoji riding the fill line: 😊 (<50%) → 😐 (<75%) → 😬 (<90%) → 🚨 (≥90%)
- is click-through (`ignoresMouseEvents`) and always-on-top (`.statusBar` window level),
  visible on all Spaces — it floats over everything but never blocks the mouse
- animates fill changes smoothly (CoreAnimation)

## Data source

Every 2 minutes (configurable), the agent:

1. Reads the Claude Code OAuth token from the macOS Keychain
   (generic password, service `Claude Code-credentials`, JSON field
   `claudeAiOauth.accessToken`) — the same credential the `claude` CLI uses.
2. Calls `GET https://api.anthropic.com/api/oauth/usage` with headers
   `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
3. Decodes `five_hour.utilization` (percent, Double) and `five_hour.resets_at`
   (ISO-8601 timestamp).

Verified working on this account on 2026-07-10 (returned 29% session / 14% weekly).
This is an undocumented endpoint used by community tools; if it ever changes, only
`UsageFetcher` needs updating.

**Error state:** on network failure, non-200, decode failure, or expired token, the bar
turns gray with a ⚠️ emoji. Stale data is never displayed as current.

## Architecture

One Swift Package (`swift build`, works with Command Line Tools alone — no Xcode), three
units with clear boundaries:

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `UsageFetcher` | Keychain read → HTTP call → JSON decode → `UsageSnapshot { percent, resetsAt }` or typed error | Security.framework, URLSession |
| `BarConfig` | Load/validate `~/.config/claudebar/config.json`; sensible defaults when absent | Foundation |
| `OverlayWindow` + `BarView` | Borderless transparent NSWindow on the configured edge; renders track, fill, emoji; animates changes | AppKit, BarConfig |
| `main` / `AppDelegate` | Wires the above: poll timer → fetch → update view | all of the above |

Each unit is understandable and testable without reading the others' internals.

## Configuration (`~/.config/claudebar/config.json`)

```json
{
  "side": "right",            // "left" | "right"
  "widthPx": 6,
  "pollIntervalSeconds": 120,
  "showEmoji": true,
  "thresholds": [
    { "upTo": 50,  "color": "#34C759", "emoji": "😊" },
    { "upTo": 75,  "color": "#FFCC00", "emoji": "😐" },
    { "upTo": 90,  "color": "#FF9500", "emoji": "😬" },
    { "upTo": 100, "color": "#FF3B30", "emoji": "🚨" }
  ]
}
```

Missing file or missing keys → defaults above. Invalid values → fall back to defaults
(never crash the overlay over a config typo).

## Install / run

- `make build` — release-build the binary
- `make install` — copy binary to `~/.local/bin/claudebar`, write and load a launchd
  agent (`~/Library/LaunchAgents/com.arukurmi.claudebar.plist`) so it starts at login
  and restarts on crash
- `make uninstall` — unload agent, remove binary and plist
- `claudebar --demo` — animate 0→100% locally for visual verification without real usage
- `claudebar --once` — fetch and print usage to stdout, then exit (debugging aid)

## Testing

- Unit tests (XCTest, `swift test`): usage JSON decoding (real captured payload),
  threshold → color/emoji mapping including boundary values (50, 75, 90, 100),
  config parsing (missing file, partial file, invalid values).
- Visual verification via `--demo` mode.
- Keychain/network are injected as protocols so `UsageFetcher` is testable without
  either.

## Phases (each ends in a working, committed state)

1. Repo scaffold: Swift package, .gitignore, README skeleton, this spec
2. `UsageFetcher` + `--once` CLI printing live percent (with tests)
3. `BarConfig` loader (with tests)
4. Bare overlay window: click-through colored strip on the configured edge
5. Fill rendering: proportional fill + threshold colors (with mapping tests)
6. Emoji layer riding the fill line
7. Polling loop: timer → fetch → animated update
8. Error/stale state rendering (gray + ⚠️)
9. `--demo` mode
10. launchd install/uninstall + Makefile
11. Colorful full README (badges, screenshots/GIF, install & config docs), polish

Each phase = at least one meaningful commit pushed to github.com/arukurmi/LiveClaudeUsage.

## Out of scope (YAGNI)

- Weekly-limit bar, multi-monitor support, menu bar mode, notifications, Windows/Linux —
  can be added later; the config format leaves room.
