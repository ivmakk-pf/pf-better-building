# Better Building settings

The mod writes `config.lua` in its folder (`ue4ss\Mods\BetterBuilding\`) at the first game start.

1. Close the game.
2. Open `config.lua` in a text editor.
3. Change a value and save the file.
4. Start the game. A change applies at the next game start.

A wrong value (a text for a switch, or a key that is not on the list) gives the default and one warning line in `UE4SS.log`.

| Setting | Default | What it does |
|---|---|---|
| `allow_collision` | `true` | Build where a construction overlaps tree stumps, rocks, props, or ruins of the map. What you built, a player, or an animal still blocks it. `false` keeps "AREA OBSTRUCTED" as in the game. |
| `allow_no_build_zones` | `true` | Build where the game shows "NO-BUILD ZONE". "EFFECT RESTRICTED" still blocks. `false` keeps the no-build zones as in the game. |
| `allow_move` | `true` | Move a construction that does not snap to the build grid in Move mode, with the blue highlight and the "Move construction" hint. `false` turns all of this off. |
| `move_key` | `"V"` | The key that turns Move mode on and off while you hold the Building Tool in build mode. A letter `"A"` to `"Z"` or `"F1"` to `"F12"`. Pick a key that the game does not use. |
| `verbose` | `false` | Extra lines in `UE4SS.log`, for a bug report. Keep it off in normal play. |
