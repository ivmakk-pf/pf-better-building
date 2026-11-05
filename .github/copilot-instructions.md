# Copilot code-review instructions

This repo is a UE4SS Lua mod for *Permafrost*, a co-op Unreal Engine 5.4 game. The mod runs in UE4SS (Lua 5.4): it hooks game UFunctions with `RegisterHook`, watches new objects with `NotifyOnNewObject`, and reads and writes UObject properties at runtime. Review with these traps in mind; a general Lua review misses most of them.

## This mod

BetterBuilding lets the player build over world objects and in no-build zones, and move a placed construction that does not snap to the build grid. Each feature has its own switch in `config.lua`. The code is in `Scripts/bb/`: `hooks.lua` (the registry of the Blueprint hooks and the timing counter), `placement/` (the placement checks), and `move/` (`feature.lua` the move, `target.lua` the construction under the crosshair, `links.lua` the upgrades and the heat, `ui.lua` the hint line and the blue highlight). In each feature folder, `feature.lua` talks to the game, and `logic.lua` is game-free and tested (the `*_logic.lua` rule below means these files). The shared helpers (log, warn once, guard, hook, config) are in `Scripts/bb/core/`.

- **Hook registry.** The Blueprint hooks are on `BP_PlayerBuildingComponent_C` and `BP_Holdable_MultiTool_C`. `hooks.lua` registers each one at a trigger where its class should be in memory: the building component hooks at the mod start and at each map load, and the Building Tool hooks (`wait = "build mode"`) at `wake()`, which the move feature calls at each entry into build mode. The hooks of one path share one registration, and each listener runs in its own guard.
- **Collision.** The post hook of `CollisionCheck` writes `bBlocked = false` only when the game blocked the place, with ground (`GroundFail` false), no exact-place stack (`HidePreview` false), no character in the bounds box of the construction (`BoxOverlapActors` with the class `Character`), and no construction that a player built under a collision box (`ComponentOverlapComponents` of each `BuildCollisions` box, with the object types of the game's own check). An owner counts as own when it is an `ABuildPartBase` with `bBuiltByPlayer` and no `bIsPreview`. One overlap result serves 0.1 s for the same actor at the same place and yaw.
- **No-build zones.** The post hook of `CheckForExclusionZone` writes `bCanBuildHere = true` when it was false. The status effect check is a different check and stays.
- **Move mode.** The move key toggles Move mode in build mode. A click (`ClientPrimaryAction`) on a movable construction under the crosshair (the hit actor of `ClientBlockingHit`) starts a move: its collision goes off, and the game's `SelectLastBuildPart` shows its preview from a game timer (`K2_SetTimer`). `PreviewLocation` keeps `PlacementEnabled` at a closed gate in Move mode and in a move, so the game's own click never builds. `CheckResources` makes a move free. A click on a valid place moves the original actor to the preview transform. The build menu (`ToggleBuildingMenu`), a mode change (`SetBuildMode`), the unequip (`LOCAL_OnHoldChange`), a right click, and `Esc` end Move mode or cancel a move.
- **Movable.** A construction built by a player, not a preview, not under construction, with a no-grid `GridType` and no `bRequireGrid`. Only the side with authority (`HasAuthority()`) moves it.
- **Links.** After a move, a workstation drops the upgrades that are out of `WorkbenchUpgradeCheckRadius` and runs `FindWorkstationUpgrades`. A moved upgrade keeps a workstation that is still in range, else it leaves it and runs `FindAndUpgradeWorkstation`. The heat zone and the snow mask of a workstation move by the same change.
- **Highlight.** In Move mode only, `BuildTrace` (at most every 0.1 s) turns the game's repair highlight (`ToggleRepairPreview`) on for the movable construction under the crosshair and colors it blue with a dynamic material instance of the repair material (the vector parameter `Color`).

Invariants:

- **No synchronous asset load from Lua.** UE4SS holds one lock for all Lua code, also on the async loading thread, so a synchronous load inside a hook deadlocks the game while it streams the world. A game function that can load (`SelectLastBuildPart`) runs from a game timer. The repair material loads with the latent `LoadAsset`, and before each use `Conv_SoftObjectReferenceToObject` of the soft reference `BuildingSystemConfig.RepairMaterial` checks that it is in memory (a hash lookup in the engine, no walk of the object array). Flag a `LoadAsset` without the latent info, a `LoadSynchronous`, and a direct call of a game function that loads.
- **No lookup that can miss on a timer or each frame.** `StaticFindObject` of an object that is not in memory walks the whole object array, and a walk while the async loading thread makes objects reads a half-made object: a native crash (seen in a world load, from a retry each second). Flag a `StaticFindObject`, `FindFirstOf`, or `FindAllOf` in a `LoopAsync`, in a per-frame hook, or of a class that can be missing outside a rare trigger. A class check by name walks the class chain (`GetSuperStruct`).
- **No `NotifyOnNewObject`.** Its callback runs on the thread that makes the object and waits for the Lua lock: the game hangs. Flag a new one.
- **The game's checks still run.** The placement hooks write only the out parameters of the single checks, so the later checks of `AdditionalBuildChecks` run as in the game. Flag a write to the final result of the placement.
- **Own constructions always block.** There is no switch for it. Flag a change that lets a placement overlap a construction that a player built.
- **No construction stays selected** in Move mode or after a move: the previews are destroyed, `PlacementEnabled` is 0, and the part names are `None`. Flag a `DisablePlacement` call: it can load the red preview material.
- **A move changes no resources.** No cost, no refund, and no build time. Flag a call of the game's build or deconstruct path.
- **Arrays.** A `TArray` that a UFunction returns arrives as a Lua table of wrapped values (read each element with `:get()`). A `TArray` property is an array object (walk it with `ForEach` and `:get()`).

## UE4SS traps

- **Object life.** A UObject can be destroyed at any time. Flag a stored object reference that is used without an `IsValid()` check.
- **Hook callbacks must not break the game.** Each callback body runs in `pcall`, and an error logs once. Flag a callback without `pcall`, and a log call in a per-call path with no once-only guard.
- **Blueprint hooks.** A Blueprint UFunction (`/Game/...`) exists only after its asset loads. Flag a `RegisterHook` on a `/Game/` path at mod start with no retry or load hook.
- **Full paths.** `RegisterHook` and `NotifyOnNewObject` need the full path (`/Script/Permafrost.Class:Function`, `/Game/.../BP_X.BP_X_C`). Flag a short class name.
- **Parameters.** Hook parameters are `RemoteUnrealParam`: read with `:get()`, write with `:set()`. Flag a direct use of the parameter as a value.
- **New objects.** The properties of an object from `NotifyOnNewObject` are not set at the callback. Flag a property read in that callback with no deferral.
- **Game thread.** Key bind and `LoopAsync` callbacks run outside the game thread. Flag UObject work there that is not inside `ExecuteInGameThread`.
- **Native crashes.** `pcall` does not catch a native crash. Flag a read of a whole struct or of soft object fields when the code needs only one field.
- **The Lua `debug` library.** Flag a local named `debug`, `print`, or another standard name that hides a library.

## Multiplayer

- **Side.** A `SERVER_` function body, `AUTHORITY_` functions, and inventory grants run on the host. Flag code that changes shared state (damage, loot, inventory) on a client, and host logic with no `HasAuthority()` check where both sides run the code.
- **Multiplayer kind.** The README states who must install the mod (Local only, Host, Every player). Flag a change that moves code to the other side without a README update.
- **This mod.** The host checks each placement again, so building over objects and in no-build zones needs the mod on the host and on each player who builds. A move runs only where the construction has authority: the host or a solo game.

## Performance

- Flag `FindAllOf`, `FindFirstOf`, `StaticFindObject`, string building, or table building in a tick hook, a `LoopAsync` with a short interval, or a hook of a function that runs often.
- `CollisionCheck`, `CheckForExclusionZone`, `PreviewLocation`, and `BuildTrace` run each frame in build mode. The overlaps keep one result for 0.1 s, and the highlight reads the target at most every 0.1 s. Flag work in these hooks before their early returns. `FindAllOf` runs only when the hint line registers.

## Compatibility

- The mod must work with the vanilla game and with the mods named in the README. Flag a write of a game property that another named mod also writes, and an inventory grant that bypasses the game's own pickup path.

## Structure and tests

- **Pure logic is separated and tested.** Logic that does not need the running game lives in a `*_logic.lua` file with no UE4SS global and no UObject, tested under `tests/`. Flag new pure logic in a hook callback, and new pure logic with no test.
- **One function for each hook target,** named `<feature>On<Target>`.

## Release and config hygiene

- **Verbose ships off.** The `verbose` default is `false`. Debug lines go behind it; without it only the load line, warnings, and errors log.
- **The mod folder name never changes.** It is the `ue4ss\Mods\` folder and the home of the player's `config.lua`. Flag any rename.
- **The config file belongs to the player.** The mod writes `config.lua` only when it is missing. Flag code that overwrites it, and a `config.lua` in the repo or the zip.
- **The version** is the `VERSION` constant in `Scripts/main.lua`, printed in the load line.
- **No committed package output.** Flag `dist/` or a zip in the diff.
- **No game content.** Flag a header pasted from the UE4SS dump or an extracted game asset.
- **Changelog matches the change.** A player-visible change adds an `[Unreleased]` entry to `CHANGELOG.md` in player-facing wording. An internal-only refactor gets none.
