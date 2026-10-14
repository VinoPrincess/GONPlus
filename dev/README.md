# GON+ — for developers

## Code layout
`GONPlus/Scripts/main.lua` is only a loader. It joins `GONPlus/Scripts/gonplus/*.lua` in the order listed in `FILES`
into one Lua chunk, so a `local` from an earlier file is visible in later ones. Errors are reported as `file.lua:line`.

Rules that keep the mod from crashing the game:
- **Never keep a game object between ticks.** Store its address (`obj:GetAddress()`) and look it up again
  (`rokuAt(addr)`, `allRokus()`, `FindAllOf`). An object the game destroyed crashes UE4SS on access, past `pcall`.
- **Talk to a Roku's AI only through `aiCtrl(r)` / `ctrlCall(r, fn)`** — the controller must exist and possess her.
- A Roku that just appeared is left alone for 3 s of game time (`rokuSettled(r)`).
- Everything per run is forgotten on a new run: register resets with `onForgetRefs(fn)`.
- Hooks only set flags; all work runs in the single game-thread scheduler (`every`, `after`).
- The main chunk is close to Lua's 200-locals limit: wrap new big sections in `; (function() ... end)()`
  and expose only what other files need as globals.

## Tests (no game needed)
Mocks of UE4SS in `dev/tests/mock.lua`, tests in `dev/tests/t_*.lua`. They catch Lua errors and check the logic of
the menu and the modes; they don't know what game variables really mean, so new game variables still need a check in the game.

    sh dev/tests/run_tests.sh                      # Lua 5.4 as "lua" in PATH
    LUA=/path/to/lua5.4 sh dev/tests/run_tests.sh
    TEST_VERBOSE=1 sh dev/tests/run_tests.sh       # with the mod's log

Each test prints `PASS name N checks` or `FAIL` with the list of failed checks.
