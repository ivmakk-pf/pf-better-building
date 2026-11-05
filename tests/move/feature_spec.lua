local fakes = require("fakes")
local paths = require("bb.paths")

local BUILD_TRACE = paths.BPC .. ":BuildTrace"
local PREVIEW_LOCATION = paths.BPC .. ":PreviewLocation"
local CLICK = paths.BPC .. ":ClientPrimaryAction"
local CHECK_RESOURCES = paths.BPC .. ":CheckResources"
local HOLD = paths.TOOL .. ":LOCAL_OnHoldChange"
local MENU = paths.UI_MANAGER .. ":ToggleBuildingMenu"
local MODE = paths.BPC_NATIVE .. ":SetBuildMode"

-- A fake actor of a class that records each method call that props does not set.
local function actor(class, props)
    props = props or {}
    props.isa = props.isa or {}
    return fakes.widget(class, props)
end

local function config(gridType, requireGrid)
    return fakes.object({
        class = "UBuildPartConfig",
        name = "Config",
        ID = "Chest",
        GridType = gridType,
        bRequireGrid = requireGrid,
    })
end

local function part(class, props)
    local p = {
        bBuiltByPlayer = true,
        bIsPreview = false,
        bUnderConstruction = false,
        BuildConfigLoaded = config(3, false),
        MeshVariation = 2,
        isa = { "BuildPartBase" },
        HasAuthority = function()
            return true
        end,
        K2_GetActorLocation = function()
            return { X = 10, Y = 20, Z = 30 }
        end,
        K2_GetActorRotation = function()
            return { Pitch = 0, Yaw = 90, Roll = 0 }
        end,
    }
    for k, v in pairs(props or {}) do
        p[k] = v
    end
    return actor(class, p)
end

describe("move feature", function()
    local env, ctx, bpc, target, preview, collisionPreview, shown, timers, selectByTimer

    -- makeTarget: the construction under the view (a chest when nil).
    local function install(makeTarget)
        env = fakes.install()
        for _, name in ipairs({ "bb.hooks", "bb.move.feature", "bb.move.target", "bb.move.links" }) do
            package.loaded[name] = nil
        end
        env.objects[paths.BPC] = fakes.object({ class = "Class", name = "BP_PlayerBuildingComponent_C" })
        env.objects[paths.TOOL] = fakes.object({ class = "Class", name = "BP_Holdable_MultiTool_C" })
        env.objects[paths.BUILD_PART] = fakes.object({ class = "Class", name = "BuildPartBase" })
        env.objects[paths.WORKSTATION] = fakes.object({ class = "Class", name = "BP_MasterWorkstation_C" })
        env.objects[paths.UPGRADE] = fakes.object({ class = "Class", name = "BP_MasterWorkstationUpgrade_C" })
        target = makeTarget and makeTarget() or part("BP_Chest_C")
        timers = {}
        env.objects[paths.KSL] = fakes.object({
            class = "KismetSystemLibrary",
            K2_SetTimer = function(_, object, name, time, looping)
                timers[#timers + 1] = { object = object, name = name, time = time, looping = looping }
            end,
        })
        shown = {}
        preview = actor("BP_Chest_C", {
            K2_GetActorLocation = function()
                return { X = 500, Y = 20, Z = 30 }
            end,
            K2_GetActorRotation = function()
                return { Pitch = 0, Yaw = 180, Roll = 0 }
            end,
        })
        collisionPreview = actor("BP_Chest_C")
        -- The game's screen-center hit: its object is a component of the current target.
        local hitTarget = function()
            return target
        end
        bpc = fakes.widget("BP_PlayerBuildingComponent_C", {
            BuildMode = 1,
            PlacementEnabled = 1,
            bHasResources = false,
            BuildPartName = "Foundation",
            BuildPartConfig = config(0, true),
            BuildingSystemConfig = { WorkbenchUpgradeCheckRadius = 300 },
            ClientBlockingHit = {
                HitObjectHandle = {
                    ReferenceObject = {
                        Get = function()
                            return fakes.object({ class = "StaticMeshComponent", GetOwner = hitTarget })
                        end,
                    },
                },
            },
        })
        -- What the game does when the timer fires SelectLastBuildPart: a new preview of the last name.
        selectByTimer = function()
            local t = timers[#timers]
            assert(t and t.object == bpc and t.name == "SelectLastBuildPart" and t.looping == false, "the timer")
            shown[#shown + 1] = { name = bpc.LastBuildPartName, before = bpc.BuildPartName }
            bpc.BuildPartName = bpc.LastBuildPartName
            bpc.PreviewBuildPart, bpc.PreviewCollision = preview, collisionPreview
            bpc.BuildPartConfig = target.BuildConfigLoaded
            bpc.PlacementEnabled = 1
            bpc.bHasResources = false
            env.hooks[CHECK_RESOURCES](fakes.param(bpc))
        end
        ctx = require("bb.core.context").new("T")
        ctx.config = { allow_move = true, move_key = "V", verbose = true }
        ctx.bp = require("bb.hooks").new(ctx)
        require("bb.move.feature").install(ctx)
        ctx.bp.start()
        env.hooks[BUILD_TRACE](fakes.param(bpc))
    end

    -- A key press (the move key when nil).
    local function press(key)
        env.keys[key or "V"]()
    end

    -- A left click. When it starts a game timer, the timer fires (the game shows the move preview).
    local function click()
        local before = #timers
        env.hooks[CLICK](fakes.param(bpc))
        if #timers > before then selectByTimer() end
    end

    -- Move mode on, then a click on the target.
    local function start()
        press()
        click()
    end

    local function lines(pattern)
        local found = {}
        for _, line in ipairs(env.printed) do
            if line:find(pattern) then found[#found + 1] = line end
        end
        return found
    end

    local function count(obj, name)
        local n = 0
        for _, call in ipairs(obj.calls) do
            if call[1] == name then n = n + 1 end
        end
        return n
    end

    local function called(obj, name)
        return count(obj, name) > 0
    end

    after_each(function()
        fakes.restore()
    end)

    describe("Move mode", function()
        local exits = {
            {
                "the build menu",
                function()
                    env.hooks[MENU](fakes.param("ui"), fakes.param(true))
                end,
            },
            {
                "a mode change",
                function()
                    env.posts[MODE](fakes.param(bpc), fakes.param(2))
                end,
            },
            {
                "an unequip",
                function()
                    env.hooks[HOLD](fakes.param("tool"), fakes.param(false))
                end,
            },
        }

        local function events()
            local list = {}
            ctx.on("move mode", function(data)
                list[#list + 1] = data.on
            end)
            return list
        end

        it("turns on at the move key and clears a selected construction", function()
            install()
            bpc.PreviewBuildPart, bpc.PreviewCollision = preview, collisionPreview
            local modes = events()
            press()
            assert.is_true(called(preview, "K2_DestroyActor"))
            assert.is_true(called(collisionPreview, "K2_DestroyActor"))
            assert.are.same({ "None", "None", 0 }, { bpc.BuildPartName, bpc.LastBuildPartName, bpc.PlacementEnabled })
            assert.are.same({ true }, modes)
            assert.are.equal(0, #shown)
            assert.are.equal(1, #lines("move mode on"))
        end)

        it("turns off at the move key again, and a click then starts nothing", function()
            install()
            local modes = events()
            press()
            press()
            click()
            assert.are.same({ true, false }, modes)
            assert.are.equal(0, #shown)
            assert.are.equal(1, #lines("move mode off %(move key%)"))
        end)

        for _, exit in ipairs(exits) do
            it("turns off at " .. exit[1], function()
                install()
                local modes = events()
                press()
                exit[2]()
                click()
                assert.are.same({ true, false }, modes)
                assert.are.equal(0, #shown)
            end)
        end

        it("ends at the move start, and the player is in build mode after a commit or a cancel", function()
            install()
            local modes = events()
            start()
            assert.are.same({ true, false }, modes)
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            click()
            click()
            assert.are.equal(1, #shown)
            start()
            press("ESCAPE")
            click()
            assert.are.equal(2, #shown)
            -- One event for each change of state: Move mode, the move, build mode.
            assert.are.same({ true, false, false, true, false, false }, modes)
        end)

        it("stays on at a click on a construction that cannot move, and a click on one that can starts it", function()
            install()
            target.BuildConfigLoaded = config(17, false)
            press()
            click()
            assert.are.equal(0, #shown)
            assert.are.equal(1, #lines("cannot move"))
            target.BuildConfigLoaded = config(3, false)
            click()
            assert.are.equal(1, #shown)
        end)

        it("keeps the game's click gate closed", function()
            install()
            press()
            bpc.PlacementEnabled = 1
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            assert.are.equal(3, bpc.PlacementEnabled)
        end)
    end)

    describe("start", function()
        it("keeps the target visible with its collision off, and shows it as the free placement preview", function()
            install()
            start()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            assert.is_false(called(target, "SetActorHiddenInGame"))
            assert.are.same({ false }, target.last.SetActorEnableCollision)
            assert.are.equal(1, #shown)
            assert.are.same({ name = "Chest", before = "None" }, shown[1])
            assert.are.same({ 2 }, preview.last.SwitchMeshVariation)
            assert.is_true(bpc.bHasResources)
            assert.is_nil(rawget(bpc.last, "ShowBuildPartPreview"))
            assert.are.equal(1, #lines("move start BP_Chest_C"))
        end)

        it("closes the click gate and ignores a click before the timer shows the move preview", function()
            install()
            press()
            env.hooks[CLICK](fakes.param(bpc))
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            assert.are.equal(3, bpc.PlacementEnabled)
            env.hooks[CLICK](fakes.param(bpc))
            assert.is_false(called(target, "K2_SetActorLocationAndRotation"))
            assert.are.equal(0, #lines("move canceled"))
            assert.is_nil(preview.last.SwitchMeshVariation)
        end)

        it("keeps the resources free at each CheckResources during a move, and not without a move", function()
            install()
            env.hooks[CHECK_RESOURCES](fakes.param(bpc))
            assert.is_false(bpc.bHasResources)
            start()
            bpc.bHasResources = false
            env.hooks[CHECK_RESOURCES](fakes.param(bpc))
            assert.is_true(bpc.bHasResources)
        end)

        it("does not start again at a second click before the preview is ready", function()
            install()
            press()
            env.hooks[CLICK](fakes.param(bpc))
            click()
            assert.are.equal(1, #timers)
        end)

        local cases = {
            {
                "a grid construction",
                function()
                    target.BuildConfigLoaded = config(17, false)
                end,
                "cannot move",
            },
            {
                "a construction that needs the grid",
                function()
                    target.BuildConfigLoaded = config(3, true)
                end,
                "cannot move",
            },
            {
                "Deconstruct mode",
                function()
                    bpc.BuildMode = 2
                end,
                "not in build mode",
            },
            {
                "no Building Tool",
                function()
                    bpc.BuildMode = 0
                end,
                "not in build mode",
            },
            {
                "a client",
                function()
                    target.HasAuthority = function()
                        return false
                    end
                end,
                "only the host",
            },
            {
                "no construction under the view",
                function()
                    target = fakes.object({ class = "BP_Rock_C" })
                end,
                "no construction",
            },
        }
        for _, case in ipairs(cases) do
            it("does nothing for " .. case[1] .. ", with a verbose line", function()
                install()
                case[2]()
                start()
                assert.are.equal(0, #shown)
                assert.are.equal(1, #lines(case[3]))
            end)
        end

        it("does nothing before the building component is known", function()
            env = fakes.install()
            package.loaded["bb.move.feature"] = nil
            ctx = require("bb.core.context").new("T")
            ctx.config = { allow_move = true, move_key = "V", verbose = true }
            ctx.bp = require("bb.hooks").new(ctx)
            require("bb.move.feature").install(ctx)
            ctx.bp.start()
            press()
            assert.are.equal(1, #lines("no building component"))
        end)
    end)

    describe("cancel", function()
        local triggers = {
            {
                "Esc",
                function()
                    press("ESCAPE")
                end,
            },
            {
                "the move key",
                function()
                    press()
                end,
            },
            {
                "the build menu",
                function()
                    env.hooks[MENU](fakes.param("ui"), fakes.param(true))
                end,
            },
            {
                "a mode change",
                function()
                    env.posts[MODE](fakes.param(bpc), fakes.param(2))
                end,
            },
            {
                "an unequip",
                function()
                    env.hooks[HOLD](fakes.param("tool"), fakes.param(false))
                end,
            },
        }
        for _, trigger in ipairs(triggers) do
            it("puts the target back at " .. trigger[1], function()
                install()
                start()
                trigger[2]()
                assert.is_false(called(target, "SetActorHiddenInGame"))
                assert.are.same({ true }, target.last.SetActorEnableCollision)
                assert.is_false(called(target, "K2_SetActorLocationAndRotation"))
                assert.are.equal(1, #lines("move canceled"))
            end)
        end

        it("cancels when the target is gone, with no call on it", function()
            install()
            start()
            target.destroyed = true
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            assert.are.equal(1, #lines("move canceled"))
            assert.are.same({ false }, target.last.SetActorEnableCollision)
        end)

        it("does not cancel at the close of the build menu inside the preview start", function()
            install()
            start()
            env.hooks[MENU](fakes.param("ui"), fakes.param(false))
            env.posts[MODE](fakes.param(bpc), fakes.param(1))
            env.hooks[HOLD](fakes.param("tool"), fakes.param(true))
            assert.are.equal(0, #lines("move canceled"))
        end)

        it("does nothing for a cancel trigger with no move", function()
            install()
            press("ESCAPE")
            env.hooks[MENU](fakes.param("ui"), fakes.param(true))
            assert.are.equal(0, #lines("move canceled"))
            assert.is_nil(target.last.SetActorHiddenInGame)
        end)
    end)

    describe("gate and commit", function()
        it("stores the check result and closes the game's click gate at each frame of a move", function()
            install()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            assert.are.equal(1, bpc.PlacementEnabled)
            start()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            assert.are.equal(3, bpc.PlacementEnabled)
        end)

        it("moves the target to the preview place at a click on a valid place", function()
            install()
            start()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            env.hooks[CLICK](fakes.param(bpc))
            assert.is_true(called(target, "K2_DetachFromActor"))
            local move = target.last.K2_SetActorLocationAndRotation
            assert.are.same({ X = 500, Y = 20, Z = 30 }, move[1])
            assert.are.same({ Pitch = 0, Yaw = 180, Roll = 0 }, move[2])
            assert.is_false(called(target, "SetActorHiddenInGame"))
            assert.are.same({ true }, target.last.SetActorEnableCollision)
            assert.are.equal(1, #lines("move done BP_Chest_C from %(10, 20, 30%) yaw 90 to %(500, 20, 30%) yaw 180"))
        end)

        it("does not move the target at a click on an invalid place", function()
            install()
            start()
            bpc.PlacementEnabled = 2
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            env.hooks[CLICK](fakes.param(bpc))
            assert.is_false(called(target, "K2_SetActorLocationAndRotation"))
            assert.are.same({ false }, target.last.SetActorEnableCollision)
        end)

        it("does nothing at a click with no move", function()
            install()
            env.hooks[CLICK](fakes.param(bpc))
            assert.is_false(called(target, "K2_SetActorLocationAndRotation"))
        end)

        it("cancels at a click when the selection is no longer the move config", function()
            install()
            start()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            bpc.BuildPartConfig = config(3, false)
            env.hooks[CLICK](fakes.param(bpc))
            assert.is_false(called(target, "K2_SetActorLocationAndRotation"))
            assert.are.equal(1, #lines("move canceled"))
        end)
    end)

    describe("clear", function()
        local function expectCleared()
            assert.is_true(called(preview, "K2_DestroyActor"))
            assert.is_true(called(collisionPreview, "K2_DestroyActor"))
            -- DisablePlacement can load the red preview material: the mod calls no game function that loads.
            assert.is_false(called(bpc, "DisablePlacement"))
            assert.are.equal(0, bpc.PlacementEnabled)
            assert.are.equal("None", bpc.BuildPartName)
        end

        it("removes the preview and the selection after a commit", function()
            install()
            start()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            env.hooks[CLICK](fakes.param(bpc))
            expectCleared()
        end)

        it("removes the preview and the selection after a cancel", function()
            install()
            start()
            press("ESCAPE")
            expectCleared()
        end)
    end)

    describe("state after a move", function()
        -- The preview stands at X = 500 with yaw 180; the target stood at X = 10 with yaw 90.
        local function at(x)
            return function()
                return { X = x, Y = 20, Z = 30 }
            end
        end

        local function commit()
            start()
            env.hooks[PREVIEW_LOCATION](fakes.param(bpc))
            env.hooks[CLICK](fakes.param(bpc))
        end

        it("drops the upgrades out of range of a moved workstation and searches again once", function()
            local near = actor("BP_Upgrade_C", { K2_GetActorLocation = at(600) })
            local far = actor("BP_Upgrade_C", { K2_GetActorLocation = at(10) })
            local bench
            install(function()
                bench = part("BP_Workbench_C", { isa = { "BuildPartBase", "BP_MasterWorkstation_C" } })
                near.UpgradedWorkstation, far.UpgradedWorkstation = bench, bench
                -- A TArray property, as the game gives it: ForEach with a param for each element.
                bench.AddedUpgrades = {
                    ForEach = function(_, fn)
                        for i, u in ipairs({ near, far }) do
                            fn(i, fakes.param(u))
                        end
                    end,
                }
                return bench
            end)
            commit()
            assert.are.same({ near }, bench.AddedUpgrades)
            assert.is_nil(rawget(far, "UpgradedWorkstation"))
            assert.are.equal(bench, near.UpgradedWorkstation)
            assert.are.equal(1, count(bench, "FindWorkstationUpgrades"))
            assert.are.equal(1, #lines("upgrades dropped 1"))
        end)

        it("leaves the old workstation of a moved upgrade out of range and searches again once", function()
            local bench = actor("BP_Workbench_C", { K2_GetActorLocation = at(10) })
            local other = actor("BP_Upgrade_C")
            local upgrade
            install(function()
                upgrade = part("BP_Upgrade_C", { isa = { "BuildPartBase", "BP_MasterWorkstationUpgrade_C" } })
                upgrade.UpgradedWorkstation = bench
                bench.AddedUpgrades = { other, upgrade }
                return upgrade
            end)
            commit()
            assert.are.same({ other }, bench.AddedUpgrades)
            assert.is_nil(rawget(upgrade, "UpgradedWorkstation"))
            assert.is_true(called(upgrade, "FindAndUpgradeWorkstation"))
        end)

        it("keeps the workstation of a moved upgrade in range", function()
            local bench = actor("BP_Workbench_C", { K2_GetActorLocation = at(600) })
            local upgrade
            install(function()
                upgrade = part("BP_Upgrade_C", { isa = { "BuildPartBase", "BP_MasterWorkstationUpgrade_C" } })
                upgrade.UpgradedWorkstation = bench
                bench.AddedUpgrades = { upgrade }
                return upgrade
            end)
            commit()
            assert.are.same({ upgrade }, bench.AddedUpgrades)
            assert.are.equal(bench, upgrade.UpgradedWorkstation)
            -- The game's search would link it to the first compatible workstation that it finds.
            assert.is_false(called(upgrade, "FindAndUpgradeWorkstation"))
        end)

        it("searches for a workstation after a move of an upgrade with none", function()
            local upgrade
            install(function()
                upgrade = part("BP_Upgrade_C", { isa = { "BuildPartBase", "BP_MasterWorkstationUpgrade_C" } })
                return upgrade
            end)
            commit()
            assert.are.equal(1, count(upgrade, "FindAndUpgradeWorkstation"))
        end)

        it("moves the heat zone and the snow mask by the same change", function()
            local heat = actor("BP_HeatPlace_C", {
                K2_GetActorLocation = at(10),
                K2_GetActorRotation = function()
                    return { Pitch = 0, Yaw = 90, Roll = 0 }
                end,
            })
            local snow = actor("BP_SnowMask_C", {
                K2_GetActorLocation = at(60),
                K2_GetActorRotation = function()
                    return { Pitch = 0, Yaw = 0, Roll = 0 }
                end,
            })
            install(function()
                local brazier = part("BP_Brazier_C", { isa = { "BuildPartBase", "BP_MasterWorkstation_C" } })
                brazier.AddedUpgrades = {}
                brazier.HeatZoneInstance, brazier.SnowMaskRef = heat, snow
                return brazier
            end)
            commit()
            assert.are.same({ { X = 500, Y = 20, Z = 30 }, { Pitch = 0, Yaw = 180, Roll = 0 } }, {
                heat.last.K2_SetActorLocationAndRotation[1],
                heat.last.K2_SetActorLocationAndRotation[2],
            })
            assert.are.same({ X = 550, Y = 20, Z = 30 }, snow.last.K2_SetActorLocationAndRotation[1])
            assert.are.equal(90, snow.last.K2_SetActorLocationAndRotation[2].Yaw)
        end)

        it("makes no extra call for a construction with no links, heat, or snow", function()
            install()
            commit()
            assert.is_false(called(target, "FindWorkstationUpgrades"))
            assert.is_false(called(target, "FindAndUpgradeWorkstation"))
        end)

        it("gives no warning when the workstation classes are not in memory", function()
            install()
            env.objects[paths.WORKSTATION], env.objects[paths.UPGRADE] = nil, nil
            commit()
            assert.are.same({}, lines("WARN"))
        end)
    end)
end)
