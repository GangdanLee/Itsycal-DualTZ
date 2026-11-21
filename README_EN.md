# Itsycal DualTZ — Beijing-First Dual-Timezone Menu Bar Calendar for US-Region macOS & Cross-Border Teams

简体中文 ([README](./README.md)) | **English** · [Download Latest DMG](https://github.com/GangdanLee/Itsycal-DualTZ/releases/latest/download/Itsycal-DualTZ-v2.2.0-macOS-arm64.dmg) · [Releases](https://github.com/GangdanLee/Itsycal-DualTZ/releases) · [Issues](https://github.com/GangdanLee/Itsycal-DualTZ/issues)

[![macOS](https://img.shields.io/badge/macOS-27%2B%20Apple%20Silicon-007AFF?logo=apple&logoColor=white)](https://github.com/GangdanLee/Itsycal-DualTZ/releases)
[![Release](https://img.shields.io/github/v/release/GangdanLee/Itsycal-DualTZ?color=34C759&label=Release)](https://github.com/GangdanLee/Itsycal-DualTZ/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE.txt)

**Keep your Mac locked to US Region / US Pacific time for Claude Desktop, Claude Code, and US developer tools — while running your calendar, daily planning, and cross-border e-commerce schedule in Beijing Time (CST).**

> **What's New in v2.2.0**: Zero-dependency Multi-Account AI Quota Pool (`AIQuotaStore` / `AIQuotaEngine`) supporting **Dual/Multi Claude Code** (auto-discovers `Claude Code-credentials*` Keychain items & `CLAUDE_CONFIG_DIR` isolation), **Antigravity (Gemini)** via local `127.0.0.1` RPC with persistent offline cache, **ChatGPT Codex**, and **Cursor** via read-only `SQLite3` on `state.vscdb`. Built with strict safety guardrails: 300s focus throttling, 429 backoff, silent `kSecUseAuthenticationUIFail` Keychain queries, zero browser cookie access, never mutates external tokens, and never persists secrets.
>
> **v2.1.0 & v2.0.0 Foundation**: Pure-offline Subscription Billing Ledger (`SubscriptionStore`), arrowless floating `NSGlassEffectView` Liquid Glass popover, customizable Primary City & 2-column DST-aware World Clock Bento cards, preserved ISO week numbers, and a native 6-Tab System Settings window.

Forked and deeply customized from [`sfsam/Itsycal` v0.29.0](https://github.com/sfsam/Itsycal) under the MIT License.

---

## Direct Download

| Artifact | File | Notes | Download |
| :--- | :--- | :--- | :--- |
| **DMG Installer (Recommended)** | `Itsycal-DualTZ-v2.2.0-macOS-arm64.dmg` | Apple Silicon (`arm64`), includes `/Applications` drag target & first-launch guide | [Download DMG](https://github.com/GangdanLee/Itsycal-DualTZ/releases/latest/download/Itsycal-DualTZ-v2.2.0-macOS-arm64.dmg) |
| **ZIP Archive** | `Itsycal-DualTZ-v2.2.0-macOS-arm64.zip` | Unzip and move `Itsycal DualTZ.app` to `/Applications` | [Download ZIP](https://github.com/GangdanLee/Itsycal-DualTZ/releases/latest/download/Itsycal-DualTZ-v2.2.0-macOS-arm64.zip) |
| **Checksums** | `SHA256SUMS.txt` | SHA-256 verification | [View SHA256SUMS](https://github.com/GangdanLee/Itsycal-DualTZ/releases/latest/download/SHA256SUMS.txt) |

---

## Why Itsycal DualTZ?

- **Built for US-region macOS setups (Claude / AI power users)**: Keep macOS system timezone on `America/Los_Angeles` without losing track of today's date and schedule in Beijing (`Asia/Shanghai`).
- **Beijing-First Everywhere**:
  - Top **Beijing Time Hero Header** + live **Local / US Pacific** comparison (+ NY & UTC optional).
  - Menu bar icon date and custom template placeholders (`{BJ:...}`, `{NY:...}`, `{UTC:...}`, `{diff}`, `{bj_dn}`).
  - Calendar grid with **dual-today visual states** (Beijing Today vs. US Today), with **Today** button anchoring to Beijing Today.
  - **New Event defaults to Beijing Time** with unambiguous 24-hour pickers (`yyyy-MM-dd`) and an **amber `🌙` late-night warning** whenever converted US time lands in `00:00–06:59`.
  - **All-Day Event Isolation**: Calendar all-day events stay strictly on their single Gregorian calendar day instead of bleeding across two Beijing days.
- **Cross-Border E-Commerce Ready (Amazon / TikTok Shop / Temu / DTC)**:
  - Bundled **China statutory holidays & makeup workdays** (`Off` / `Wk` badges, 2025–2027 offline JSON + online/manual JSON sync).
  - **Chinese Lunar dates & 24 Solar Terms**.
  - **US Federal Holidays** (`US` badge) + **Black Friday / Cyber Monday** + toggleable **retail marketing nodes** (`02-14`, Mother's/Father's Day, `618`, `Halloween`, `11.11`, Christmas Eve).
  - **7-day US DST transition banner** for automatic `15h` / `16h` awareness.
- **Cross-TZ Meeting Workflow**:
  - Expandable **96-slot Beijing Meeting Time Scrubber** highlighting golden overlap hours.
  - One-click **Copy Dual-TZ Invite** in Agenda context menu.
  - Video call link detection for **Feishu / Lark / Tencent Meeting (WeMeet) / Zoom / Teams / Google Meet** + **15-min pre-meeting countdown** suffix in menu bar.
- **Live Bilingual UI Switch**: Hot-switch between **简体中文**, **English**, and **Follow System** in Settings without restarting.
- **Coexists with Upstream Itsycal**: Uses bundle ID `com.morgan.ItsycalDualTZ` and separate preferences while safely migrating basic appearance defaults on first run.

---

## Installation & First Launch

1. Download **`Itsycal-DualTZ-v2.2.0-macOS-arm64.dmg`** and drag **`Itsycal DualTZ.app`** into **`Applications`**.
2. Because the build uses local ad-hoc signing without paid Apple notarization, if macOS Gatekeeper blocks the first launch, run once in Terminal:

```bash
xattr -cr "/Applications/Itsycal DualTZ.app"
```

> **Requirements**: macOS 27.0+ (Apple Silicon `arm64`). Build from source via `cp Local.xcconfig.example Local.xcconfig && xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Release build`.

---

## Credits & License

- Built upon [`sfsam/Itsycal`](https://github.com/sfsam/Itsycal) (`v0.29.0`) by Sanjay Madan.
- AI quota probe protocol design inspired by [`steipete/CodexBar`](https://github.com/steipete/CodexBar) (MIT License).
- Released under the [MIT License](./LICENSE.txt).
