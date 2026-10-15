GON+  v1.0.2  -  modes, mutators and records for GON: God of Nothing
==================================================================

No cheats. You only choose how you want to play.
A choice window opens at the start of every run (mouse, or arrows + Enter;
mouse wheel scrolls; right click / Backspace / BACK button goes back).


INSTALL
-------
1. Install UE4SS for the game: the EXPERIMENTAL build ("experimental-latest"
   on the UE4SS GitHub releases page), not the old stable v3.0.1 - the game runs
   on Unreal 5.7 and the old version can crash with mods.
2. Copy the GONPlus folder into
      ...\GON God Of Nothing\Roku3\Binaries\Win64\ue4ss\Mods\
3. Keep the empty file enabled.txt inside GONPlus - it turns the mod on.

Settings and records are saved to GONPlus\settings.txt and GONPlus\records.txt.
When updating, replace the Scripts folder and keep those two files.


MODES
-----
Normal       The game as it is: collect the apples and get out. Without a
             mutator you pick the difficulty: Easy / Normal / Hard / Nightmare
             (Hard + no HUD, real darkness, one hit kills, no hiding spots,
             only a little trash and skulls to throw, she hears you run).
Pure Stealth Roku doesn't hunt you. If she SEES you - it's over. No hiding.
             Running and thrown items make noise. 1 to 4 Rokus.
Reactor      Countdown to the blast. Three levels:
               Failure (30 min)  - flickering lights, red alarm at the end
               Critical failure (20 min) - power failures plunge the
                                   complex into darkness for seconds
               Meltdown (17 min) - red from the start, longer blackouts,
                                   the heat slows stamina recovery, and in
                                   the last 3 minutes Roku gets faster
SUTEGOMA     You are bleeding out. Running makes it worse, medkits only buy
             time (half the heal, but a bandage), her hits open the wound,
             hiding presses it. She roams far and follows your blood.
Lovesick     Roku is drunk and very affectionate. Survive the timer (4-12 min).
             Every hug makes you fall for her; a full heart means you lose.
             Throw gifts at her (or spank her) to cool her down.
Bashful      She feels your gaze. Don't stare at her, don't come close.


MUTATORS (one per run)
----------------------
Zero Hour         One minute on the clock; every apple adds 20 seconds.
Darkness          The lights are out. Your flashlight is all you've got.
Blackouts         Now and then you see absolutely nothing for a few seconds.
No HUD            No bars, no counter, no crosshair.
No Hiding         The hiding spots don't work.
One Hit           Her first hit is the last one.
Heat              Stamina comes back twice as slowly.
Slippery Hands    The item you hold slips out of your hands now and then.
Twins             A second Roku roams the map.
No Food           No apples, carrots, drinks or coffee - only trash to throw.
Zoomies           Roku runs everywhere from the very start.
Razor Claws       Roku's hits deal 50% more damage.
Random            Fate picks one. No rerolls.
Chaos             The mutator changes every N seconds (see Settings).


RECORDS
-------
Every mode + mutator combination keeps its own best run. The speedrun panel
(top right) shows your time, apples and the difference to your best.


SETTINGS
--------
Interface      game style (like the pause menu) or Terminal (a side panel
               like a computer in the complex); menu animations on/off.
Bars           GON+ health and stamina bars: corner (like the game), center,
               or terminal (thin bars with numbers).
Graphics/FPS   for PCs where the game drops frames: render scale, quality,
               shadows, reflections, fog, anti-aliasing, effects, FPS limit,
               presets and an FPS counter. "game" = the game's own value;
               "Reset to game" puts everything back.
Game pop-ups   off hides the game's own pop-ups: +RUN+, item names,
               "note acquired - pause to read".
Also           chaos timing, speedrun panel size and position.


CREDITS
-------
GON+ by VinoPrincess (ElyndraFae)
Design, ideas, testing: VinoPrincess
Code written with the help of AI (Claude by Anthropic)

Thanks:
  BlackBoneGames and Tom - for GON: God of Nothing
  The UE4SS team - for the modding framework
