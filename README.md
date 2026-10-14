# GON+

**Modes, mutators and records for [GON: God of Nothing](https://store.steampowered.com/search/?term=GON%20God%20of%20Nothing).**
A UE4SS Lua mod. No cheats — you only choose *how* you want to play.

A choice window opens at the start of every run: pick a mode, a mutator, and go.
Every combination keeps its own best run.

Also available on [Nexus Mods](https://www.nexusmods.com/gongodofnothing/mods/5).

---

## Install

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) for the game — **the experimental build** (`experimental-latest`, the `UE4SS_v3.x.x-...zip` file, not `zDEV`).
   The old stable **v3.0.1 is too old** for this game (Unreal 5.7) and can crash with mods.
2. Download `GONPlus-<version>.zip` from [Releases](../../releases) (or from [Nexus Mods](https://www.nexusmods.com/gongodofnothing/mods/5)) and unpack it into
   ```
   ...\GON God Of Nothing\Roku3\Binaries\Win64\ue4ss\Mods\
   ```
   so you get `Mods\GONPlus\Scripts\main.lua` and `Mods\GONPlus\enabled.txt`.
3. Start the game. The choice window appears when a run begins.

Updating: replace the `Scripts` folder, keep `settings.txt` and `records.txt` (your settings and records).

## Controls

| | |
|---|---|
| Mouse | hover to select, click to choose, click the sides of a button to change its value |
| Mouse wheel / scrollbar | scroll long lists |
| Arrows + Enter | the same with the keyboard |
| Right click / Backspace / **BACK** | go back |

## Modes

| Mode | |
|---|---|
| **Normal** | The game as it is: collect the apples and get out. |
| **Pure Stealth** | Roku doesn't hunt you — but if she *sees* you, it's over. No hiding. Running and thrown items make noise. 1–4 Rokus. |
| **Nightmare** | Almost impossible. No HUD, real darkness, one hit kills, no hiding spots, only a little trash and skulls to throw. She hears you run. |
| **Lovesick** | Roku is drunk and very affectionate. Survive the timer (4–12 min). Every hug makes you fall for her — a full heart and you lose. Throw gifts at her to cool her down. |

## Mutators

One per run (or let fate decide).

| Mutator | |
|---|---|
| **Reactor** | A countdown to the blast, three levels: **Failure** (30 min, flickering lights, red alarm at the end) · **Critical failure** (20 min, power failures plunge the complex into darkness) · **Meltdown** (17 min, red from the start, longer blackouts, heat slows stamina recovery, Roku gets faster in the last 3 minutes) |
| **Zero Hour** | One minute on the clock. Every apple adds 20 seconds (2:30 at most) — the clock is always nearly empty. |
| **Slippery Hands** | The item you hold slips out of your hands now and then. |
| **SUTEGOMA** | You are bleeding out. More medkits around. |
| **Twins** | A second Roku roams the map. |
| **No Food** | No apples, carrots, drinks or coffee — only trash to throw. |
| **Zoomies** | Roku runs everywhere from the very start. |
| **Razor Claws** | Roku's hits deal 50% more damage. |
| **Random** | Fate picks one. No rerolls. |
| **Chaos** | The mutator changes every N seconds. |

## Also

- **Speedrun panel** — time, apples and the split against your best run.
- **GON+ health and stamina bars** — at the bottom center, in the corner like the game, or terminal-style with numbers; they change color with the mode.
- **Two interface styles** — like the game's pause menu, or **Terminal**: a side panel like a computer in the complex.
- **Victory and defeat screens** for every mode and mutator.
- **Graphics / FPS** (in Settings) — render scale, shadows, reflections, fog, anti-aliasing, FPS limit,
  presets and an FPS counter. For PCs where the game drops frames.
- Everything is configurable in **Settings**.

## For developers

The code lives in `GONPlus/Scripts/gonplus/*.lua`; `main.lua` is a loader that joins the files in order
(`local`s from earlier files are visible in later ones) and reports errors as `file.lua:line`.

There is a hidden developer lab (F1) with time skips, test cheats, lighting tools and research scans.
Runs that use lab cheats never count for records.

---

## Credits

**GON+ by VinoPrincess** (ElyndraFae) — design, ideas, testing.
Code written with the help of AI (Claude by Anthropic).

Thanks to **BlackBoneGames** and **Tom** for GON: God of Nothing, and to the **UE4SS** team for the modding framework.
Thanks to **PerfectZero (mrdude2x)** — [RokuMenu](https://github.com/mrdude2x/Roku-Menu) showed how Roku's senses, chase reset and attack animations work (no code was copied).

This mod contains no game files. Licensed under the [MIT License](LICENSE).

---

### По-русски

GON+ — мод для GON: God of Nothing: режимы (Pure Stealth, Nightmare, Lovesick), мутаторы и рекорды, без читов.
Установка: UE4SS (экспериментальная сборка) → распаковать архив из Releases или с [Nexus Mods](https://www.nexusmods.com/gongodofnothing/mods/5) в `...\Roku3\Binaries\Win64\ue4ss\Mods\`.
