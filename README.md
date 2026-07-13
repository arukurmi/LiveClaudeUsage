# 🎨 ClaudeBar — Live Claude Usage Edge Bar for macOS

![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/macOS-13+-000000?logo=apple)
![Deps](https://img.shields.io/badge/dependencies-0-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

A whisper-thin, always-on-top bar hugging your screen edge that shows how much of
your **Claude 5-hour session limit** you've used — live. Green and 😊 when you're
fresh, red and 🚨 when you're about to hit the wall. It's **click-through**: your
mouse never knows it's there — until you hover it. Hovering reveals a small **–**
chip; click it and the bar tucks itself into a tiny dot near the bottom corner
(perfect for full-screen video). Click the dot to bring the bar back. The reset
time of your 5-hour window rides the middle of the fill, rotated to fit.

## 😩 Why

Checking your Claude usage means: open claude.ai → profile → usage. Or run
`/usage` inside Claude Code. Every. Single. Time. ClaudeBar turns that into a
glance at your screen edge.

```
Screen right edge (~6px wide)

        │░░│  ← empty track (dim)
        │░░│
        │░░│
        😊 ← emoji rides the fill line
        │██│  ← filled = usage %
        │██│     green → red as it grows
        │██│
```

## 📸 See it

| Fresh 😊 | Getting there 😬 | Almost out 🚨 |
|:---:|:---:|:---:|
| <img src="docs/screenshots/bar-green.png" height="400"> | <img src="docs/screenshots/bar-orange.png" height="400"> | <img src="docs/screenshots/bar-red.png" height="400"> |

## 🚦 What the colors mean

| Usage | Bar color | Emoji |
|-------|-----------------------|-------|
| 0–50% | 🟢 Green `#34C759` | 😊 |
| 51–75% | 🟡 Yellow `#FFCC00` | 😐 |
| 76–90% | 🟠 Orange `#FF9500` | 😬 |
| 91–100% | 🔴 Red `#FF3B30` | 🚨 |
| fetch failed | ⬜ Gray | ⚠️ |

## 📦 Install

```bash
git clone git@github.com:arukurmi/LiveClaudeUsage.git
cd LiveClaudeUsage
make install
```

That's it — the bar appears immediately and starts automatically at every login.

> 🔑 **First run:** macOS may ask permission for `claudebar` to read the
> `Claude Code-credentials` Keychain item. Click **Always Allow**.

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).
You must be logged into [Claude Code](https://claude.com/claude-code) at least once.

## ⚙️ Configuration

Everything is configurable via `~/.config/claudebar/config.json` (see
[`examples/config.json`](examples/config.json)). Missing keys keep their
defaults; invalid values fall back safely.

```json
{
  "side": "left",
  "widthPx": 12,
  "pollIntervalSeconds": 120,
  "showEmoji": true,
  "showResetTime": true,
  "thresholds": [
    { "upTo": 50,  "color": "#34C759", "emoji": "😊" },
    { "upTo": 75,  "color": "#FFCC00", "emoji": "😐" },
    { "upTo": 90,  "color": "#FF9500", "emoji": "😬" },
    { "upTo": 100, "color": "#FF3B30", "emoji": "🚨" }
  ]
}
```

| Key | What it does | Default |
|-----|--------------|---------|
| `side` | `"left"` or `"right"` screen edge | `"left"` |
| `widthPx` | Bar thickness in points (1–40) | `12` |
| `pollIntervalSeconds` | How often to fetch usage (min 5) | `120` |
| `showEmoji` | Show the emoji riding the fill line | `true` |
| `showResetTime` | Show the window's reset time (local, e.g. `4:30PM`) rotated at the middle of the fill | `true` |
| `thresholds` | Your own colors 🎨 and emojis, any number of tiers | see above |

After editing the config, restart the bar:
`launchctl kickstart -k gui/$(id -u)/com.arukurmi.claudebar`

The bar always appears on the **built-in MacBook display**, even with external
monitors connected.

## 🔍 How it works

1. 🔐 Reads your Claude Code OAuth token from the macOS Keychain — the same
   credential the `claude` CLI already uses. Nothing new to log into.
2. 🌐 Every 2 minutes, calls Anthropic's OAuth usage endpoint
   (`api.anthropic.com/api/oauth/usage`) and takes `five_hour.utilization`.
   (Undocumented endpoint — the same data the `/usage` screen shows.)
3. 🖥️ Renders it as a CoreAnimation fill in a borderless, click-through
   `NSWindow` at status-bar level, visible on every Space.

Native Swift + AppKit. One ~200KB binary. Zero dependencies. Near-zero CPU.

## 🛠️ CLI flags

| Flag | What it does |
|------|--------------|
| `claudebar --once` | Print current usage to stdout and exit |
| `claudebar --demo` | Animate 0→100→0 forever (no network) — try `make demo` |

## 🧪 Development

```bash
make build     # release build
make test      # run the test suite (plain executable — CLT has no XCTest)
make demo      # watch the full color sweep
```

## 🗑️ Uninstall

```bash
make uninstall
```

## 📄 License

[MIT](LICENSE) © 2026 Aryansh Kurmi
