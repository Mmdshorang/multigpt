# MultiCodex UI Redesign — Design Document

**Date:** April 2026
**Status:** Approved for implementation (Dashboard style)
**Mockup:** `docs/multicodex-redesign-mockups.html` (open in browser)

## Context

MultiCodex is a native macOS SwiftUI menu bar app for managing multiple coding agent accounts. The existing UI is functional but suffers from:
- Hard to scan quickly — information hierarchy is flat
- Too cramped/dense — insufficient whitespace between sections
- Too plain/boring — lacks visual interest and personality

Three design directions were evaluated and documented below. **The Dashboard style was selected for implementation.**

---

## Style 1: Native macOS Pro

**Aesthetic:** Refined system-native macOS look, like System Settings or Finder.

**Key characteristics:**
- Light background with vibrancy materials (`rgba(246,246,246,0.92)` + `backdrop-filter: blur`)
- System fonts (-apple-system, SF Pro Text)
- Grouped card panels with 0.5px hairline borders
- Segmented controls for strategy selection
- Native macOS blue accent (#007AFF)
- System traffic-light status colors (green/orange/red)
- Rounded rect buttons matching macOS HIG (6px radius, 11px text)
- Sidebar with `underPageBackgroundColor` background

**SwiftUI mapping:**
- `SettingsPanelCard` → `GroupBox` with `.formStyle(.grouped)`
- `ActionPillButton` → native `Button` with `.buttonStyle(.bordered)` / `.borderedProminent`
- Sidebar → `NavigationSplitView` with `.navigationSplitViewStyle(.balanced)`
- Segmented controls → `Picker` with `.pickerStyle(.segmented)`
- Status pills → custom `Label` with tinted background

**Pros:** Feels at home on macOS, minimal custom code, familiar to users
**Cons:** Conservative, can look generic

---

## Style 2: Dashboard / Data-First (SELECTED FOR IMPLEMENTATION)

**Aesthetic:** Dark observability dashboard with rich data visualization — like iStat Menus meets a monitoring tool.

**Key characteristics:**
- Dark background (#0C0E14) with subtle transparency layers
- Space Grotesk font for a technical, modern feel
- Bento grid layout for the popover — asymmetric card arrangement
- **Progress rings** (SVG circular indicators) for 5h and weekly usage
- **Sparkline bars** showing usage trend over time
- Glowing status dots with box-shadow halos
- Indigo accent (#6366F1) for primary actions and selections
- Inline micro-bars in account rows for at-a-glance comparison
- Uppercase tracking labels (9px, letter-spacing 1.5px) for section headers
- Border-right indicator on active sidebar items

### Popover Structure

```
┌─────────────────────────────────────┐
│ Header: Title + Timestamp + Refresh │
├──────────┬──────────────────────────┤
│ 5h Ring  │ Weekly Ring              │
│ + Spark  │ + Sub label              │
├──────────┴──────────────────────────┤
│ Current Account (wide card)         │
├─────────────────────────────────────┤
│ All Accounts                        │
│  ● account-1    ▓▓▓▓░░  42%       │
│  ● account-2    ▓▓▓▓▓▓  78%       │
│  ● account-3    ░░░░░░   0%        │
├─────────────────────────────────────┤
│ [+ New Account]          [Settings] │
└─────────────────────────────────────┘
```

### Settings Structure

```
┌──────────┬──────────────────────────────┐
│ Sidebar  │ Detail                       │
│          │                              │
│ Dashboard│ ┌──────┐ ┌──────┐ ┌──────┐  │
│ Accounts │ │Card 1│ │Card 2│ │Card 3│  │
│ Runtime  │ └──────┘ └──────┘ └──────┘  │
│ Display  │                              │
│ Trouble  │ Section: Switching Strategy  │
│          │   Row: Strategy  [Manual]    │
│          │   Row: Notifs    [Enabled]   │
│          │                              │
│          │ Section: Runtime             │
│          │   Row: Path  [/usr/...]      │
└──────────┴──────────────────────────────┘
```

### Color Palette

| Token             | Value                          | Usage                        |
|--------------------|-------------------------------|------------------------------|
| `bg`              | `#0C0E14`                     | Popover & window background  |
| `card-bg`         | `rgba(255,255,255,0.03)`      | Bento card fills             |
| `card-border`     | `rgba(255,255,255,0.06)`      | Card borders                 |
| `text-primary`    | `#FFFFFF`                     | Headings, account names      |
| `text-secondary`  | `rgba(255,255,255,0.35)`      | Metadata, descriptions       |
| `text-tertiary`   | `rgba(255,255,255,0.3)`       | Section labels (uppercase)   |
| `accent`          | `#6366F1` (indigo)            | Selection, primary actions   |
| `accent-bg`       | `rgba(99,102,241,0.08-0.15)`  | Selected row fill            |
| `status-green`    | `#34D399`                     | Connected                    |
| `status-orange`   | `#FB923C`                     | Needs login                  |
| `status-red`      | `#EF4444`                     | Error / critical usage       |
| `ring-5h`         | `#6366F1`                     | 5h progress ring stroke      |
| `ring-weekly`     | `#34D399`                     | Weekly progress ring stroke   |
| `spark-default`   | `rgba(99,102,241,0.4)`        | Sparkline bars               |
| `spark-high`      | `rgba(251,146,60,0.5)`        | Bars > 60%                   |
| `spark-critical`  | `rgba(239,68,68,0.5)`         | Bars > 80%                   |

### Typography

| Element            | Font           | Size | Weight | Tracking   |
|--------------------|---------------|------|--------|------------|
| Section label      | Space Grotesk | 9px  | 600    | +1.5px     |
| Card heading       | Space Grotesk | 13px | 600    | default    |
| Detail title       | Space Grotesk | 18px | 700    | default    |
| Account name       | Space Grotesk | 12px | 600    | default    |
| Metadata           | Space Grotesk | 10px | 400    | default    |
| Ring label         | Space Grotesk | 10px | 600    | default    |
| Button             | Space Grotesk | 11px | 400    | default    |

### Spacing & Sizing

| Token         | Value | Usage                                |
|---------------|-------|--------------------------------------|
| Container pad | 16px  | Popover outer padding                |
| Card padding  | 12px  | Bento card inner padding             |
| Card radius   | 10px  | Card corner radius                   |
| Card gap      | 8px   | Between bento cards                  |
| Row gap       | 4px   | Between account rows                 |
| Row padding   | 8 10px| Account row vertical/horizontal pad  |
| Ring size     | 48px  | SVG progress ring diameter           |
| Dot size      | 8px   | Status dot diameter                  |
| Spark height  | 24px  | Sparkline container height           |

### SwiftUI Components to Build

1. **`DashboardProgressRing`** — `View` using `Shape` subclass with `trim(from:to:)` and `rotationEffect`
2. **`DashboardSparkline`** — `View` rendering an array of `RoundedRectangle` bars in an `HStack`
3. **`DashboardBentoGrid`** — Layout container using `Grid` (macOS 14+) or custom `Layout`
4. **`DashboardStatCard`** — Reusable card with uppercase label + value
5. **`DashboardFormRow`** — `HStack` with label + control, dark-themed
6. **`DashboardAccountRow`** — Row with status dot, name, metadata, inline progress bar
7. **`DashboardSectionHeader`** — Uppercase tracked label (9px, 600 weight)

---

## Style 3: Compact Terminal-Dev

**Aesthetic:** Developer terminal aesthetic — dark, monospace, dense information, minimal chrome.

**Key characteristics:**
- Pure dark (#111111) with near-black sections (#0D0D0D, #1A1A1A, #1E1E1E)
- IBM Plex Mono / Geist Mono font throughout
- Square borders (1px radius), flat fills
- Key-value pair layout (`key: value`) for data
- Flat color progress bars (6px height, 1px radius)
- Status dots as 5px squares (not circles — `border-radius: 1px`)
- `> ` prefix on sidebar items
- `// ` prefix on section headings
- `$ ` command prompt in header
- Tag badges for state (`NEEDS LOGIN` with border)
- No gradients, no shadows, no rounded corners
- Indigo (#6366F1) only for active indicators

**SwiftUI mapping:**
- Cards → plain `VStack` with 1px border `RoundedRectangle(cornerRadius: 1)`
- Text → `.font(.system(.body, design: .monospaced))`
- Buttons → `Button` with `.buttonStyle(.plain)` + border overlay
- Sidebar items → `Text("> \(section)")` with `.monospaced()`
- Status → colored `Circle()` or `RoundedRectangle` square
- Progress bars → `RoundedRectangle(cornerRadius: 1)` + overlay fill

**Pros:** Appeals to developer audience, maximizes info density, distinctive identity
**Cons:** May feel austere, less approachable for non-technical users

---

## Implementation Plan

The **Dashboard** style will be implemented. The implementation will touch:

1. `Features/Shared/AccountPresentation.swift` — New `DashboardAccountPresentation` with dark theme colors
2. `Features/MenuBar/AccountsMenuContentView.swift` — Bento grid layout with rings + sparklines
3. `Features/MenuBar/AccountsMenuContentView+Sections.swift` — New section builders
4. `Features/MenuBar/MenuAccountQuickRow.swift` — Redesigned row with inline micro-bar
5. `Features/Settings/SettingsContentView.swift` — Dark theme settings window
6. `Features/Settings/SettingsContentView+Dashboard.swift` — Dashboard page redesign
7. `Features/Settings/SettingsContentView+Design.swift` — New design tokens
8. `Features/Shared/SettingsPanelCard.swift` — Dark-themed card component
9. New files for `DashboardProgressRing`, `DashboardSparkline`, etc.
