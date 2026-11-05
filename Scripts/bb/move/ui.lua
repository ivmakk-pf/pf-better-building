-- The move in the game UI: a line for the move key in the hint list of the Building
-- Tool, and the game's repair highlight in blue on a construction that can move, while Move mode
-- is on and the player looks at it.
local logic = require("bb.move.logic")
local paths = require("bb.paths")

local M = {}

local BUILD = 1 -- EBuildMode
local CHARACTER_INPUTS = 2 -- EPermaInputMapType, as the Building Tool's own lines use
local TRACE_EVERY = 0.1 -- s
local LOAD_EVERY = 2 -- s, between two async loads of the highlight material
local COLOR = "Color" -- the vector parameter of the highlight material (yellow in the game)
local BLUE = { R = 0.05, G = 0.35, B = 1, A = 1 }

---@param ctx BbContext
function M.install(ctx)
    local finder = require("bb.move.target").new(ctx)
    local lit = nil ---@type any the construction with the highlight on
    local active = false -- Move mode is on
    local localBpc = nil ---@type any the building component of the local player (BuildTrace runs only there)
    local lastTrace = -math.huge
    local lastLoad, loadId = -math.huge, 9200

    -- The tool class loads at the first equip, so its hints showed before this hook existed: when
    -- the hook registers while the local tool is held, the game shows its hints again, and the
    -- hook adds the move line. Runs once, when the hook registers at the entry into build mode. When
    -- this feature's BuildTrace has not run yet in that frame, the call waits for it.
    local hintsPending = false
    local function showHintsAgain()
        if not ctx.valid(localBpc) then
            hintsPending = true
            return
        end
        if localBpc.BuildMode == 0 then return end
        local character = localBpc.OwningCharacter
        local tools = FindAllOf("BP_Holdable_MultiTool_C") or {} ---@type any[]
        for _, tool in ipairs(tools) do
            if ctx.valid(tool) and tool.OwningCharacter:GetAddress() == character:GetAddress() then
                local lib = StaticFindObject(paths.PERMA_LIB) ---@type any
                local hud = lib:GetMainHUD_ByWorld(character)
                hud:ClearTemporaryInputHints()
                tool:ShowHUDInputHints(hud)
                return
            end
        end
    end

    -- The game clears the temporary hints at each equip, so the line never doubles.
    ctx.bp.listen("move hint", paths.TOOL, "ShowHUDInputHints", function(_, hudP)
        local hud = hudP:get()
        local key, noPad = { KeyName = FName(ctx.config.move_key) }, { KeyName = FName("None") }
        hud:AddInputHint(FText("Move construction"), nil, CHARACTER_INPUTS, key, noPad, true)
    end, { onRegister = showHintsAgain, wait = "build mode" })
    local showHintsLater = ctx.guard("move hint registered", showHintsAgain)

    local function off()
        if lit and ctx.valid(lit) then lit:ToggleRepairPreview(false) end
        lit = nil
    end

    local function same(a, b)
        return a ~= nil and b ~= nil and a:GetAddress() == b:GetAddress()
    end

    -- ToggleRepairPreview(true) loads its material synchronously when it is not in memory, which
    -- deadlocks inside a Lua hook while the game streams the world. So the mod loads it
    -- asynchronously (the latent LoadAsset) and turns the highlight on only when it is in memory.
    -- Nothing holds the material after the load, so the game can free it again: the check runs each time.
    -- The check resolves the soft reference of the building config: the engine finds a soft
    -- reference in its hash tables only. A lookup by path (StaticFindObject) walks the whole object
    -- array when it misses, which can crash the game while it streams the world.
    ---@return any material the material when it is in memory, else nil
    local function materialReady(bpc)
        local lib = StaticFindObject(paths.KSL) ---@type any
        local soft = bpc.BuildingSystemConfig.RepairMaterial
        local material = ctx.try(function()
            return lib:Conv_SoftObjectReferenceToObject(soft)
        end)
        if ctx.valid(material) then return material end
        local now = ctx.now()
        if now - lastLoad < LOAD_EVERY then return nil end
        lastLoad, loadId = now, loadId + 1
        local info = { Linkage = 0, UUID = loadId, ExecutionFunction = FName("None"), CallbackTarget = bpc }
        lib:LoadAsset(bpc, soft, nil, info)
        ctx.trace("highlight material: async load started")
        return nil
    end

    -- The highlight copies of the meshes hold the repair material. A dynamic instance of it on each
    -- copy takes another color, and loads nothing (the material is in memory).
    local function blue(part, material)
        local meshes = part:K2_GetComponentsByClass(StaticFindObject(paths.STATIC_MESH)) or {}
        for _, entry in ipairs(meshes) do
            local mesh = entry:get() -- UE4SS wraps each element of a returned array
            for i = 0, mesh:GetNumMaterials() - 1 do
                if same(mesh:GetMaterial(i), material) then
                    local instance = mesh:CreateDynamicMaterialInstance(i, material, FName("None"))
                    instance:SetVectorParameterValue(FName(COLOR), BLUE)
                end
            end
        end
    end

    ctx.bp.listen("move highlight", paths.BPC, "BuildTrace", function(self)
        local bpc = self:get()
        localBpc = bpc
        if hintsPending then
            hintsPending = false
            showHintsLater()
        end
        if not active then return end
        if bpc.BuildMode ~= BUILD then return off() end
        -- The read of the hit and the movable check run at most every 0.1 s.
        local now = ctx.now()
        if now - lastTrace < TRACE_EVERY then return end
        lastTrace = now
        local part = finder.under(bpc)
        if part and not logic.isMovable(finder.fields(part)) then part = nil end
        if same(part, lit) then return end
        off()
        local material = part and materialReady(bpc)
        if part and material then
            part:ToggleRepairPreview(true)
            lit = part
            blue(part, material)
        end
    end, { timed = true, perFrame = true })

    -- The feature ends Move mode at a move start, a commit, a cancel, and when the player leaves build mode.
    ctx.on("move mode", function(data)
        active = data.on
        if not active then off() end
    end)
end

return M
