![version](https://img.shields.io/badge/version-1.0.1-blue) ![coverage](https://img.shields.io/badge/coverage-99%25-brightgreen)

# Better Building

Building overhaul: fewer collisions, build in no-build zones, move furniture.

The game refuses a lot of good spots with "AREA OBSTRUCTED" or "NO-BUILD ZONE", and a workbench that stands in the wrong place has to come down and go up again. This mod lets you build there and move a placed construction to a new spot. Each feature has its own switch, and each switch is on by default.

## Features

- **Build over objects**: place constructions over stumps, rocks, props, and ruins. Your own constructions, players, and animals still block, and the other build rules stay: ground, foundations, slopes, and resources.
- **Build in no-build zones**: place constructions where the game shows "NO-BUILD ZONE".
- **Move mode**: during build mode (`B`), press `V` to turn Move mode on. Workstations, storage, furniture, lamps, and decorations light up blue. Click one, then click a new spot to place it (`R` rotates). Walls, floors, foundations, and roofs do not move.

A move follows the normal build rules, so a workbench still needs a foundation. The construction keeps its items, durability, fuel, and upgrades. An upgrade stays linked while it stands near its workstation, and a lit brazier takes its heat with it.

## Known issues

- The click that places a moved construction plays the game's "can't build" sound. The construction still moves.
- `Esc` also opens the pause menu when it cancels a move.

## Save safety

The mod does not change the save format. A construction that you placed or moved with the mod is a normal construction in the save, so the save loads without the mod.

## Multiplayer

Not tested in co-op. To build over objects or in no-build zones, the host and each player who builds need the mod: the host checks each placement again. Moving works for the host and in a solo game. For a player who joins a hosted game, a click in Move mode moves nothing.

## Requirements

- Permafrost (Early Access), the update of 30 October 2026 or later.
- [UE4SS for Permafrost](https://www.nexusmods.com/permafrost/mods/42), the UE4SS build that the mod is tested with.

## Installation

1. Install [UE4SS for Permafrost](https://www.nexusmods.com/permafrost/mods/42).
2. Extract this mod's zip into the game folder (the folder with Permafrost.exe). The mod lands in Permafrost\Binaries\Win64\ue4ss\Mods. Full path example for Steam: `C:\Program Files (x86)\Steam\steamapps\common\Permafrost\Permafrost\Binaries\Win64\ue4ss\Mods\BetterBuilding`

## Uninstall

Delete the `BetterBuilding` folder from the `ue4ss\Mods` folder.

## Configuration

To change mod settings, edit `ue4ss\Mods\BetterBuilding\config.lua` while the game is closed (see [CONFIG.md](CONFIG.md) for every setting). Changes apply at the next game start.

## Development

The code is in `Scripts/bb/`: `hooks.lua` registers the Blueprint hooks and times them, `placement/` changes the placement checks, and `move/` moves a construction (`feature.lua` the move, `links.lua` the upgrades and the heat, `ui.lua` the hint line and the blue highlight). In each feature folder, `feature.lua` talks to the game, and `logic.lua` is game-free. The specs in `tests/` run with [busted](https://lunarmodules.github.io/busted/) on Lua 5.4, with fake UE4SS globals (`tests/fakes.lua`). They need the rocks `busted` and `luafilesystem` (and `luacov` for the coverage). From the repo root:

```
busted
busted --coverage
```

`./package.ps1` makes the install zip in `dist/`.

## License

Licensed under the GNU General Public License v3.0. Copyright (C) 2026 ivmakk.

Do not reupload this mod or a changed copy without credit and a link to this repository.
