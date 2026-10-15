# Changelog

## Unreleased (1.1)

- **Modes and mutators reorganised.** A mode changes the rules as a whole; a mutator changes one thing.
  - **Reactor** is now a mode (Mode: Reactor, then pick the level: Failure / Critical failure / Meltdown).
    Records are kept — they're the same as before.
  - **SUTEGOMA** is now a mode too (records kept), with a new rule by VinoPrincess: **running makes the bleeding worse.**
    A *blood loss* meter fills as you burn stamina — use up the whole stamina bar in one go and it's full — and drains
    a bit slower than stamina comes back. The fuller it is, the faster you bleed (up to 4× at full, "HEMORRHAGE").
    You can still run — just not all the time.
    - *Medkits only buy time:* they heal half as much, but bandage the wound — no bleeding for 35 s ("BANDAGED").
    - *Her hits open the wound:* the blood loss meter jumps and a bandage is torn off.
    - *Hiding spots:* pressing the wound — bleeding almost stops, the meter drains faster.
    - *Weakness:* below 30% health the screen edges darken with your heartbeat; below 15% the camera drifts.
    - *She follows the blood:* the complex smells of other people's blood, so yours gets lost — Roku roams on her own,
      further away than usual, and now and then checks places you were a minute ago. But bleed out hard
      (HEMORRHAGE) or stay in one spot too long and the scent is fresh: she comes straight for you.
      If she sees you, she hunts as usual; lose her for 8 s and she goes back to roaming.
  - **Nightmare** is now the fourth difficulty of the plain game: Normal mode, no mutator, Difficulty: Nightmare
    (needs Hard unlocked in the game). Records kept.
  - **New mutators** — they work on their own and in Chaos: **Darkness** (lights out), **No HUD**, **No Hiding**,
    **One Hit**, **Heat** (stamina comes back twice as slowly). And **Blackouts** — every 35–60 s the screen flickers
    and goes completely black for a few seconds, like your eyes can't adjust (not in Chaos).
- **Run intros:** the mode / mutator name now comes with a short line under it that tells what you're in for
  ("+ BASHFUL +" — *Don't make her blush.*; "+ NIGHTMARE +" — *Lights out. One hit. Nowhere to hide. Good luck.*).
  Mode first, then the mutator. Chaos shows the line of every new mutator. Replaces the old start banners.
- **The game's own settings in the GON+ window** — no need to visit the game's main menu any more:
  - *Roku:* her outfit, right on the main screen. Changes on her at once and is saved for the game too
    (same as its Customize menu). Locked outfits are skipped.
  - *Difficulty* (Easy / Normal / Hard) for the plain game — Normal mode without a mutator. GON+ modes and mutators
    always play on Normal; if the game was set to something else, START restarts the level once and the run begins by itself.
    Records are kept apart for each difficulty.
  - *Settings → Mouse sensitivity* — the game's own, saved for the game too.
  - *Settings → Quick start* (off by default): launching the game skips its main menu and goes straight to the GON+ window.
    Only once per launch — if you quit to the main menu yourself, it stays there.
- **Quit game** at the bottom of the choice window: closes the game right away (click twice, so it can't happen by accident).
- **Settings → Game pop-ups** (on / off): hides the game's pop-up hints — "+RUN+" when she chases you,
  "+ NOTE ACQUIRED + PAUSE TO READ +" and item names when you pick something up. They clash with the modes.
  New hints are caught the moment they appear and are born invisible — no flicker.
- **New mode: Bashful.** Idea by VinoPrincess, in the spirit of SCP-096: Roku can't see you, but she feels your gaze.
  She doesn't walk — she flickers out and appears again near you: ahead, behind, around the corner.
  Two ways to lose: look at her too long (she's on screen and nothing hides her), or come too close
  (near you *and* in plain sight — a wall between you doesn't count). A pink meter at the top shows how
  embarrassed she is; it fills while you stare or stand close and slowly fades. She never attacks.
  She's invisible until you look right at her or come close (surprise behind the door), fidgets shyly when you
  look at her, and every 35–60 s "LOOK AT ME" pulls your camera towards her — turn away in time.
  While you look at her the mouse goes sluggish (the game's own sensitivity drops to 35%), so turning away takes effort.
  Not with Twins, Zoomies or Razor Claws.
- Zero Hour: its own victory screen ("JUST IN TIME") instead of the reactor's.
- **New mutator: Zero Hour.** One minute on the clock; every apple adds 20 seconds, but you can bank 2:30 at most —
  the clock is always nearly empty. Run, plan your vents, don't miss apples. Time out = defeat.
  The timer turns blue / pink / red at 40 / 20 / 10 seconds and shakes only in the last 10.
- **New interface style: Minimal** (Settings → Interface: game / terminal / minimal). No window: big text in the
  game's button font right over the darkened game, like the game's main menu; `+NEW+RUN+` headings, `— ROW`
  selection, the description on the right behind a thin line. Animation: the text drifts away and the new page fades in.
- **Bars: Lines** (Settings → Bars) — two thin lines at the bottom center; picked automatically with Minimal.
- **Clearer buttons:** rows you can change show `<` and `>` at their edges (in Terminal / Minimal both sit on the right).
  The edges change the value, the middle chooses; the arrow under the mouse lights up. No more guessing where to click.
- Fixed: switching the interface style while scrolled down could move the selection to another row.
- **Developer lab (F1): five new sections**, the old FunMenu moved in and new findings added.
  - *Player:* ghost flight, endless mask, heal, super speed, moon gravity, size, teleport where you look, save / return to a spot.
  - *Roku:* freeze, pull to me, AI asleep, camera through her eyes / behind her, big / tiny / hyper / invisible, orbit,
    any animation, fall over, turn to me, drunk, late-game speed, cowbell, a hit-reaction prop (research).
  - *Senses:* hearing radius and vision range (deaf … hears everything, near-sighted … eagle eyes), senses off,
    "forget me" (cancels the chase), "can't hurt you", karma (spotted = she trips), vision down / up.
  - *Items:* spawn any item, force push, clone fountain, delete what you look at / everything spawned, shake the Sum of Nothing.
  - *World:* slow motion, mega flashlight, everything off.
  - Everything works for all Rokus at once (Twins, Pure Stealth). Lab toys still mark the run: no record.

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
