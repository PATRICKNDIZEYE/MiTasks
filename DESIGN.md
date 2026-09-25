# miTasks design system

miTasks is built from Crew's own parts so the two feel like siblings. This
applies to all three front-ends: the Mac widget (`renderer/`), the phone PWA
(`mobile/`) and the native iOS app (`ios/`). The Mac widget is the reference
implementation. When in doubt, match it.

## Principles

- **Always dark, like Crew.** Graphite surfaces. No light theme and no warm
  gradients or glow.
- **Structure, not just colour.** Screens are laid out like a Crew mission:
  - a top bar with the mark
  - a header with a title, a meta line and a pill switch
  - the composer
  - underline tabs with counts
  - sidebar-style sections of rows
- **Colour means something.**
  - Amber: needs you today (due today, medium, live meeting, the "Needs you" count).
  - Red: overdue, high priority, destructive.
  - Green: running, done, free time.
  - Blue: links and focus rings.
  - A label's own colour is only ever a dot.
  - Everything else is ink, muted or faint.
- **Actions are chips.** Row and toolbar actions are Crew's filled grey chips
  (`chip-bg`). The rare primary action is ink.
- **Every value comes from a scale.** Don't invent in-between sizes.
- **Keep the personality.** The pet bubble, the confetti and label colours
  stay. Label colours are user data synced to the phone, so they must never be
  remapped.

## Tokens (Crew dark)

| Token | Value | Token | Value |
| --- | --- | --- | --- |
| `bg` | `#111110` | `primary` / `primary-ink` | `#edece9` / `#111110` |
| `surface` | `#161615` | `hover` | `rgba(255,255,255,.055)` |
| `surface-2` | `#1c1c1a` | `select` | `rgba(255,255,255,.1)` |
| `surface-3` | `#252523` | `chip-bg` / hover | `#3b3b3c` / `#474748` |
| `ink` | `#edece9` | `status-running` | `#72c293` |
| `ink-2` | `#c7c5c0` | `brand-dot` | `#f2a93b` |
| `muted` | `#8f8d88` | `amber` / `amber-bg` | `#e4a53a` / `#2e2414` |
| `faint` | `#64625e` | `red` / `red-bg` | `#ec6a5a` / `#32191a` |
| `line` | `#262624` | `green` / `green-bg` | `#52c48f` / `#13271e` |
| `line-strong` | `#363532` | `blue` / `blue-bg` | `#79a3ff` / `#18223a` |

**Type.** IBM Plex Sans 400/500/600 and IBM Plex Mono for times, countdowns
and tags. The web front-ends load it from `/fonts/` (the files are in
`renderer/fonts`); iOS uses the system font. The size scale is 11 · 12 · 13 ·
14 · 16 · 20 · 28. Rows are 13px.

**Space.** 2 4 6 8 12 16 20 24 32 40 48 64.

**Radius.** 4 for tags, 6 for buttons, 8 for rows and cards, 12 for panels,
the composer and sheets. Pills are fully round.

## Parts

- **Top bar.** 44px high, with Crew's ring-and-dot mark and the name at
  14/600, and quiet icon buttons on the right. A hairline sits underneath.
- **Header.** "Today" at 20/600 (28 on the phone). The meta line is 13 muted:
  the date · **n** of m done · free time in green.
- **Pill switch.** Crew's Auto-approve: an outlined pill with a small switch.
  When on, the outline and text use `status-running` and a Mono countdown
  shows. Lock-in uses it.
- **Composer.** A bordered box with 12 radius holding the input. The bar under
  the input has the label scope as a quiet dropdown with a dot, then the mic,
  then a grey "↑ Add" chip.
- **Tabs.** 13/500 muted. The active tab is ink with a 2px ink underline. The
  count sits next to the name at 11 faint.
- **Section head.** Title at 13/600 `ink-2`, then the count at 13/600 (amber
  for Needs you, green for In focus), then a 12 muted hint on the right.
- **Needs-you row.** A checkbox with the label colour as a status dot on its
  corner, a 13/600 title, and a 12 status line coloured by meaning. A grey
  "Focus" chip sits on the right.
- **Active row (In focus).** A `select` background, a bold title, a Mono
  "focus" tag outlined in `status-running`, a Mono time, and a "Stop" chip.
- **Line row (Up next).** Grouped under label heads (dot, name, count). A
  small checkbox, the 13 title, and a 12 muted word on the right.
- **Done.** A folded "› Done n" that expands in place.
- **Metric card.** 11 muted label on top with a 20/600 number underneath, on
  `surface-2` with a `line` border.
- **Segmented control.** A `surface-3` track; the selected segment is
  `chip-bg`.
- **Switch.** Track `line-strong`, `status-running` when on.
