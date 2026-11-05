local fakes = require("fakes")
local paths = require("bb.paths")

local HINTS = paths.TOOL .. ":ShowHUDInputHints"
local BUILD_TRACE = paths.BPC .. ":BuildTrace"

describe("move ui", function()
    local env, ctx, bpc, hit, bench, wall, rock
    local now, traces, loads = 0, 0, {}

    local function part(class, gridType)
        return fakes.widget(class, {
            isa = { "BuildPartBase" },
            bBuiltByPlayer = true,
            bIsPreview = false,
            bUnderConstruction = false,
            BuildConfigLoaded = { GridType = gridType, bRequireGrid = false },
        })
    end

    -- toolLater: the Building Tool class is not in memory at the start (it loads at the first equip).
    local function install(toolLater)
        env = fakes.install()
        for _, name in ipairs({ "bb.hooks", "bb.move.ui", "bb.move.target" }) do
            package.loaded[name] = nil
        end
        env.objects[paths.BPC] = fakes.object({ class = "Class", name = "BP_PlayerBuildingComponent_C" })
        if not toolLater then
            env.objects[paths.TOOL] = fakes.object({ class = "Class", name = "BP_Holdable_MultiTool_C" })
        end
        env.objects[paths.BUILD_PART] = fakes.object({ class = "Class", name = "BuildPartBase" })
        bench, wall = part("BP_Workbench_C", 3), part("BP_WoodenWall_C", 17)
        rock = fakes.object({ class = "BP_Rock_C" })
        hit = bench
        -- The highlight material is in memory unless a test removes it.
        env.objects[paths.REPAIR_MATERIAL] = fakes.object({ class = "MaterialInstanceConstant" })
        env.objects[paths.STATIC_MESH] = fakes.object({ class = "Class", name = "StaticMeshComponent" })
        loads = {}
        env.objects[paths.KSL] = fakes.object({
            class = "KismetSystemLibrary",
            LoadAsset = function(_, context, ptr, onLoaded, info)
                loads[#loads + 1] = { context = context, ptr = ptr, onLoaded = onLoaded, info = info }
            end,
        })
        bpc = fakes.object({
            class = "BP_PlayerBuildingComponent_C",
            BuildMode = 1,
            OwningCharacter = fakes.object({ class = "BP_SGKMasterCharacter_C" }),
            BuildingSystemConfig = { RepairMaterial = "soft pointer" },
            -- The game's screen-center hit; each read counts as one trace result.
            ClientBlockingHit = {
                HitObjectHandle = {
                    ReferenceObject = {
                        Get = function()
                            traces = traces + 1
                            return hit
                        end,
                    },
                },
            },
        })
        now, traces = 0, 0
        ctx = require("bb.core.context").new("T", function()
            return now
        end)
        ctx.config = { allow_move = true, move_key = "K", verbose = true }
        ctx.bp = require("bb.hooks").new(ctx)
        require("bb.move.ui").install(ctx)
        ctx.bp.start()
        if not toolLater then ctx.bp.wake("build mode") end
        ctx.emit("move mode", { on = true })
    end

    -- One frame, 0.2 s after the last one (step: the time to the last frame, in seconds).
    local function frame(step)
        now = now + (step or 0.2)
        env.hooks[BUILD_TRACE](fakes.param(bpc))
    end

    local function toggles(obj)
        local list = {}
        for _, call in ipairs(obj.calls) do
            if call[1] == "ToggleRepairPreview" then list[#list + 1] = call[2] end
        end
        return list
    end

    after_each(function()
        fakes.restore()
    end)

    describe("hint line", function()
        it("adds one temporary line with the move key at each equip of the Building Tool", function()
            install()
            local hud = fakes.widget("UW_HUD_C")
            env.hooks[HINTS](fakes.param("tool"), fakes.param(hud))
            assert.are.same(
                { "AddInputHint", "Move construction", nil, 2, { KeyName = "K" }, { KeyName = "None" }, true },
                hud.calls[1]
            )
            assert.are.equal(1, #hud.calls)
        end)

        describe("at the first equip", function()
            local hud, tool, otherTool

            -- The first equip loads the tool class and shows the hints before the hook exists.
            local function firstEquip()
                install(true)
                hud = fakes.widget("UW_HUD_C")
                env.objects[paths.PERMA_LIB] = fakes.object({
                    class = "PermaFunctionLibrary",
                    GetMainHUD_ByWorld = function(_, context)
                        assert(context == bpc.OwningCharacter, "the HUD of the local character")
                        return hud
                    end,
                })
                tool = fakes.widget("BP_Holdable_MultiTool_C", { OwningCharacter = bpc.OwningCharacter })
                otherTool = fakes.widget("BP_Holdable_MultiTool_C", { OwningCharacter = fakes.object({}) })
                env.allOf["BP_Holdable_MultiTool_C"] = { otherTool, tool }
                frame()
                env.objects[paths.TOOL] = fakes.object({ class = "Class", name = "BP_Holdable_MultiTool_C" })
            end

            it(
                "shows the hints of the local tool again when the hook registers at the entry into build mode",
                function()
                    firstEquip()
                    ctx.bp.wake("build mode")
                    assert.are.same({ "ClearTemporaryInputHints" }, fakes.callNames(hud))
                    assert.are.same({ "ShowHUDInputHints", hud }, tool.calls[1])
                    assert.are.same({}, otherTool.calls)
                end
            )

            it("waits for the first frame of this feature when the hook registers before it", function()
                install(true)
                hud = fakes.widget("UW_HUD_C")
                env.objects[paths.PERMA_LIB] = fakes.object({
                    class = "PermaFunctionLibrary",
                    GetMainHUD_ByWorld = function()
                        return hud
                    end,
                })
                tool = fakes.widget("BP_Holdable_MultiTool_C", { OwningCharacter = bpc.OwningCharacter })
                env.allOf["BP_Holdable_MultiTool_C"] = { tool }
                env.objects[paths.TOOL] = fakes.object({ class = "Class", name = "BP_Holdable_MultiTool_C" })
                ctx.bp.wake("build mode")
                assert.are.same({}, tool.calls)
                frame()
                assert.are.same({ "ShowHUDInputHints", hud }, tool.calls[1])
                frame()
                assert.are.equal(1, #tool.calls)
            end)

            it("shows nothing again when the tool is no longer held", function()
                firstEquip()
                bpc.BuildMode = 0
                ctx.bp.wake("build mode")
                assert.are.same({}, hud.calls)
                assert.are.same({}, tool.calls)
            end)
        end)

        it("gives one warning when the call throws", function()
            install()
            local hud = fakes.object({
                AddInputHint = function()
                    error("no hint")
                end,
            })
            env.hooks[HINTS](fakes.param("tool"), fakes.param(hud))
            env.hooks[HINTS](fakes.param("tool"), fakes.param(hud))
            local warnings = 0
            for _, line in ipairs(env.printed) do
                if line:find("WARN .*no hint") then warnings = warnings + 1 end
            end
            assert.are.equal(1, warnings)
        end)
    end)

    describe("highlight", function()
        it("calls nothing outside build mode", function()
            install()
            bpc.BuildMode = 2
            frame()
            assert.are.same({}, toggles(bench))
        end)

        it("loads the material asynchronously when it is not in memory, and turns the highlight on later", function()
            install()
            env.objects[paths.REPAIR_MATERIAL] = nil
            frame()
            assert.are.same({}, toggles(bench))
            assert.are.equal(1, #loads)
            assert.are.equal(bpc, loads[1].context)
            assert.are.equal("soft pointer", loads[1].ptr)
            assert.is_nil(loads[1].onLoaded)
            assert.are.same(
                { 0, "None", bpc },
                { loads[1].info.Linkage, loads[1].info.ExecutionFunction, loads[1].info.CallbackTarget }
            )
            frame(0.5)
            frame(0.5)
            assert.are.equal(1, #loads)
            frame(1.2)
            assert.are.equal(2, #loads)
            assert.are_not.equal(loads[1].info.UUID, loads[2].info.UUID)
            env.objects[paths.REPAIR_MATERIAL] = fakes.object({ class = "MaterialInstanceConstant" })
            frame(0.5)
            assert.are.same({ true }, toggles(bench))
        end)

        -- A lookup that misses walks the whole object array (a crash while the world streams).
        it("looks up a missing material at most every 0.5 s", function()
            install()
            env.objects[paths.REPAIR_MATERIAL] = nil
            local function lookups()
                local n = 0
                for _, call in ipairs(env.spy.StaticFindObject.calls) do
                    if call.vals[1] == paths.REPAIR_MATERIAL then n = n + 1 end
                end
                return n
            end
            frame()
            for _ = 1, 3 do
                frame(0.15)
            end
            assert.are.equal(1, lookups())
            frame(0.15)
            assert.are.equal(2, lookups())
        end)

        it("runs the camera trace at most every 0.1 s and keeps the last result between", function()
            install()
            frame()
            local chest = part("BP_Chest_C", 0)
            hit = chest
            frame(0.02)
            frame(0.02)
            assert.are.equal(1, traces)
            assert.are.same({}, toggles(chest))
            frame(0.1)
            assert.are.equal(2, traces)
            assert.are.same({ true }, toggles(chest))
        end)

        it("turns the highlight on once for a movable construction under the view", function()
            install()
            frame()
            frame()
            assert.are.same({ true }, toggles(bench))
        end)

        it("moves the highlight to a new movable construction", function()
            install()
            frame()
            local chest = part("BP_Chest_C", 0)
            hit = chest
            frame()
            assert.are.same({ true, false }, toggles(bench))
            assert.are.same({ true }, toggles(chest))
        end)

        it("turns it off for a grid construction, another object, or no hit, and turns nothing on", function()
            for _, other in ipairs({ "wall", "rock", "none" }) do
                install()
                frame()
                hit = ({ wall = wall, rock = rock, none = nil })[other]
                frame()
                assert.are.same({ true, false }, toggles(bench))
                assert.are.same({}, toggles(wall))
            end
        end)

        it("makes each highlight mesh blue with a dynamic instance of the repair material", function()
            install()
            local material = env.objects[paths.REPAIR_MATERIAL]
            local mid = fakes.widget("MaterialInstanceDynamic")
            local function mesh(slotMaterial)
                return fakes.widget("StaticMeshComponent", {
                    GetNumMaterials = function()
                        return 1
                    end,
                    GetMaterial = function()
                        return slotMaterial
                    end,
                    CreateDynamicMaterialInstance = function(self, index, source, name)
                        self.calls[#self.calls + 1] = { "CreateDynamicMaterialInstance", index, source, name }
                        return mid
                    end,
                })
            end
            local highlightMesh = mesh(material)
            local bodyMesh = mesh(fakes.object({ class = "MaterialInstanceConstant" }))
            bench.K2_GetComponentsByClass = function(_, class)
                assert(class == env.objects[paths.STATIC_MESH], "the static mesh class")
                -- The game's ToggleRepairPreview(true) made the highlight copy before this call.
                assert(#toggles(bench) == 1, "after the highlight is on")
                -- UE4SS gives the returned array as a Lua table of wrapped values (read with get).
                return { fakes.param(highlightMesh), fakes.param(bodyMesh) }
            end
            frame()
            assert.are.same({ { "CreateDynamicMaterialInstance", 0, material, "None" } }, highlightMesh.calls)
            assert.are.same({ { "SetVectorParameterValue", "Color", { R = 0.05, G = 0.35, B = 1, A = 1 } } }, mid.calls)
            assert.are.same({}, bodyMesh.calls)
        end)

        it("calls nothing outside Move mode", function()
            install()
            ctx.emit("move mode", { on = false })
            frame()
            assert.are.same({}, toggles(bench))
            assert.are.equal(0, traces)
        end)

        it("turns it off when Move mode ends and shows none until Move mode is on again", function()
            install()
            frame()
            ctx.emit("move mode", { on = false })
            assert.are.same({ true, false }, toggles(bench))
            frame()
            assert.are.same({ true, false }, toggles(bench))
            ctx.emit("move mode", { on = true })
            frame()
            assert.are.same({ true, false, true }, toggles(bench))
        end)

        it("makes no call on a construction that is gone", function()
            install()
            frame()
            bench.destroyed = true
            ctx.emit("move mode", { on = false })
            assert.are.same({ true }, toggles(bench))
        end)
    end)
end)
