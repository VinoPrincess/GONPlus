# Changelog

## 1.0.2 — 2026-10-14

- **Fixed Lovesick's last two minutes** ("SHE ALWAYS KNOWS"): Roku ran back and forth and ignored you.
  Every "love power" ping sent her to where you *were*; she looked around the empty spot, wandered off,
  and 4 seconds later got a new spot — and she could only hug while chasing. Now in the final phase she
  chases you all the time, seen or not; earlier, when a ping brings her close to you, she switches to the chase too.
- Lovesick: "love power" comes more often — every 40–55 s at the start, every 15–20 s before the final (was 70–100 and 25–35).
- **Menu animations** (Settings → Animations, on by default). Game style: pages slide up and down inside the frame
  (deeper screens go up, BACK goes down), the window fades in and out. Terminal: the panel slides off the left edge
  and comes back with the new page. Any key or click during a slide finishes it at once.
- **New interface style: Terminal** (Settings → Interface). The choice window becomes a full-height side panel
  like a computer in the complex: the game's monospace font, square corners, a blue line, `> ROW` selection.
  The game-style window stays the default.
- **Bars: a third look, Terminal** (Settings → Bars: corner / center / terminal) — thin square bars at the bottom left
  with HP / ST labels and percentages. Switching the interface to Terminal switches the bars too.
- **Settings → Graphics / FPS** — for PCs where the game drops frames (reported on AMD cards):
  render scale, overall quality, faster shadows (no Unreal 5 virtual shadows), cheaper reflections,
  volumetric fog, anti-aliasing, light effects, FPS limit, quick presets (game / balanced / max FPS)
  and an FPS counter (average and the lowest value of the last 5 seconds).
  Everything is engine console variables: "game" leaves the game's own value, nothing in game files changes.
  The mod keeps the chosen values when the game overwrites them, and writes a graphics report to `UE4SS.log`.
- Stability: the mod no longer keeps references to Rokus or hiding spots between ticks — it stores their
  addresses and looks the live object up again (Lovesick, Nightmare, Pure Stealth extras, Twins, Meltdown, lab).
- Code: the darkness module has its own scope (headroom under Lua's 200-locals limit).
- Developer tests on UE4SS mocks: `dev/tests` (see `dev/README.md`).

## 1.0.1 — 2026-10-13

- **Fixed a crash in Pure Stealth with several Rokus** (reported by the first tester: 4 Rokus, a few steps after the elevator).
  The mod now talks to a Roku's AI only when her controller really exists and controls her,
  and leaves every newly appeared Roku alone for 3 seconds while the game finishes setting her up.
- README: use the experimental UE4SS build — the old stable v3.0.1 is too old for Unreal 5.7.

## 1.0 — 2026-10-13

First public release.

- **Modes:** Normal, Pure Stealth (1–4 Rokus), Nightmare, Lovesick (4–12 min).
- **Mutators:** Reactor (Failure / Critical failure / Meltdown), Slippery Hands, SUTEGOMA, Twins, No Food, Zoomies, Razor Claws, Random, Chaos.
- **Records** for every mode + mutator combination; speedrun panel with splits.
- **Interface** in the game's style: choice window with mouse, wheel and keyboard, BACK button, scrollbar;
  GON+ health and stamina bars (center or corner); colored messages per mode and mutator;
  victory and defeat screens for every mode.
- **Real darkness** in Nightmare and during reactor blackouts (lamps, sky light, color grading, vignette).
- Mutator timers follow game time (stop while paused).
- Quiet log: only loading and errors unless the developer lab is enabled.
- Stability: cached references to game objects are dropped on every new run (fixes a rare crash after a level restart).
