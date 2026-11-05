-- Move construction: the move key turns Move mode on and off. In Move mode, a click on the
-- construction under the crosshair shows it as the game's placement preview, and a click on a valid
-- place moves the original actor there. The original actor stays, so its contents,
-- durability, and fuel stay, and the save reads its new transform.
local logic = require("bb.move.logic")
local paths = require("bb.paths")

local M = {}

local BUILD = 1 -- EBuildMode
local GATE = 3 -- a PlacementEnabled value that the game's click does not accept
local TIMER_DELAY = 0.01 -- s, the game timer that shows the move preview

---@param ctx BbContext
function M.install(ctx)
    local cfg = ctx.config
    local finder = require("bb.move.target").new(ctx)
    require("bb.move.links").install(ctx)
    local machine = logic.machine()
    local bpc = nil ---@type any the local building component (BuildTrace runs only for the local controller)
    local target = nil ---@type any
    local moveConfig = nil ---@type any
    local ready = false -- the game shows the move preview (the timer fired)
    local old = nil ---@type { loc: FVector, rot: FRotator }?

    local function className(obj)
        return ctx.try(function()
            return obj:GetClass():GetFName():ToString()
        end) or "?"
    end

    local function same(a, b)
        return ctx.valid(a) and ctx.valid(b) and a:GetAddress() == b:GetAddress()
    end

    local function place(loc, rot)
        return string.format("(%.0f, %.0f, %.0f) yaw %.0f", loc.X, loc.Y, loc.Z, rot.Yaw)
    end

    local actions = {}

    -- The target stays visible at its old place during the move, so the player can compare the
    -- places. Its collision is off, so it does not block its own preview.
    function actions.collisionOff()
        target:SetActorEnableCollision(false)
    end

    -- The game's own SelectLastBuildPart shows the preview. It runs from a game timer, outside the
    -- UE4SS lock, because it can load assets synchronously (a deadlock from Lua). SelectBuildPart
    -- returns at once for the name of the current selection, so BuildPartName is cleared first.
    function actions.preview()
        moveConfig, ready = target.BuildConfigLoaded, false
        bpc.LastBuildPartName = moveConfig.ID
        bpc.BuildPartName = FName("None")
        local lib = StaticFindObject(paths.KSL) ---@type any
        lib:K2_SetTimer(bpc, "SelectLastBuildPart", TIMER_DELAY, false, false, 0, 0)
    end

    function actions.free()
        bpc.bHasResources = true
    end

    function actions.remember()
        old = { loc = target:K2_GetActorLocation(), rot = target:K2_GetActorRotation() }
    end

    function actions.collisionOn()
        if not ctx.valid(target) then return end
        target:SetActorEnableCollision(true)
    end

    function actions.commit()
        local preview = bpc.PreviewBuildPart
        local loc, rot = preview:K2_GetActorLocation(), preview:K2_GetActorRotation()
        target:K2_DetachFromActor(1, 1, 1)
        target:K2_SetActorLocationAndRotation(loc, rot, false, {}, true)
        actions.collisionOn()
        if old then
            ctx.trace(
                "move done " .. className(target) .. " from " .. place(old.loc, old.rot) .. " to " .. place(loc, rot)
            )
            ctx.emit("move committed", { target = target, bpc = bpc, old = old, loc = loc, rot = rot })
        end
    end

    -- No construction stays selected in Move mode or after a move. No
    -- DisablePlacement: it can load the red preview material. LastBuildPartName = None also stops a
    -- timer that has not fired.
    function actions.clearSelection()
        for _, preview in ipairs({ bpc.PreviewBuildPart, bpc.PreviewCollision }) do
            if ctx.valid(preview) then preview:K2_DestroyActor() end
        end
        bpc.PlacementEnabled = 0
        bpc.BuildPartName = FName("None")
        bpc.LastBuildPartName = FName("None")
    end

    function actions.clear()
        actions.clearSelection()
        target, moveConfig, old = nil, nil, nil
    end

    -- Runs one event; a change of state tells the highlight whether Move mode is on.
    local function run(event, data)
        local before = machine.state
        data.targetValid = ctx.valid(target)
        for _, name in ipairs(logic.step(machine, event, data)) do
            actions[name]()
        end
        if machine.state ~= before then ctx.emit("move mode", { on = machine.state == "mode" }) end
    end

    -- The player left build mode, or a cancel trigger of a move.
    local function exit(reason, event)
        if machine.state == "moving" then
            ctx.trace("move canceled (" .. reason .. ")")
        elseif machine.state == "mode" and event ~= "cancel" then
            ctx.trace("move mode off (" .. reason .. ")")
        end
        run(event, {})
    end

    local function cancel(reason)
        exit(reason, "cancel")
    end

    local function toggle()
        if not ctx.valid(bpc) then return ctx.trace("move key: no building component yet") end
        if machine.state == "build" then
            if bpc.BuildMode ~= BUILD then return ctx.trace("move key: not in build mode") end
            ctx.trace("move mode on")
            return run("toggle", {})
        end
        exit("move key", "toggle")
    end

    -- A click in Move mode: the construction under the crosshair starts its move when it can move.
    local function clickInMode()
        local part = finder.under(bpc)
        local movable = false
        if not part then
            ctx.trace("click: no construction under the crosshair")
        elseif not logic.isMovable(finder.fields(part)) then
            ctx.trace("click: " .. className(part) .. " cannot move")
        elseif not part:HasAuthority() then
            ctx.trace("click: only the host can move a construction")
        else
            movable, target = true, part
            ctx.trace("move start " .. className(part))
        end
        run("click", { movable = movable })
    end

    local listen = {}

    -- The entry into build mode wakes the hooks of the Building Tool: the tool is in hand, so its
    -- class is in memory. The wake runs outside this hook, so no hook registers inside a hook call.
    local building = false
    local wake = ctx.guard("build mode", function()
        ctx.bp.wake("build mode")
    end)
    ctx.bp.listen("move bpc", paths.BPC, "BuildTrace", function(self)
        bpc = self:get()
        local inBuild = bpc.BuildMode ~= 0
        if inBuild and not building then ExecuteInGameThread(wake) end
        building = inBuild
    end, listen)

    ctx.bp.listen("move resources", paths.BPC, "CheckResources", function(self)
        if machine.state == "moving" then self:get().bHasResources = true end
    end, listen)

    -- Each frame of a move: the game's checks ran; keep their result and close the click gate. The
    -- gate is closed also before the timer shows the move preview, so a click cannot build the old
    -- selection. The first frame with the move config makes the preview ready and gives it the mesh.
    ctx.bp.listen("move frame", paths.BPC, "PreviewLocation", function(self)
        if machine.state == "build" then return end
        local component = self:get()
        if machine.state == "mode" then
            component.PlacementEnabled = GATE
            return
        end
        if not ctx.valid(target) then return cancel("target gone") end
        local placement = component.PlacementEnabled
        component.PlacementEnabled = GATE
        if not ready then
            local preview = component.PreviewBuildPart
            if not (same(component.BuildPartConfig, moveConfig) and ctx.valid(preview)) then return end
            ready = true
            preview:SwitchMeshVariation(target.MeshVariation)
        end
        run("frame", { valid = placement == 1 })
    end, { timed = true, perFrame = true })

    -- The click: the game's body did nothing (the gate), so the mod commits a valid place.
    ctx.bp.listen("move click", paths.BPC, "ClientPrimaryAction", function()
        if machine.state == "mode" then return clickInMode() end
        if machine.state ~= "moving" or not ready then return end
        if not same(bpc.BuildPartConfig, moveConfig) then return cancel("selection changed") end
        run("click", {})
    end, { timed = true })

    ctx.bp.listen("move unequip", paths.TOOL, "LOCAL_OnHoldChange", function(_, heldP)
        if heldP:get() == false then exit("tool put away", "exit") end
    end, { wait = "build mode" })

    -- The right click opens the build menu. ShowBuildPartPreview closes it (false), which is no exit.
    ctx.hook("move menu", paths.UI_MANAGER .. ":ToggleBuildingMenu", function(_, showP)
        if showP:get() == true then exit("build menu", "exit") end
    end)

    ctx.hook("move mode", paths.BPC_NATIVE .. ":SetBuildMode", function(_, modeP)
        if modeP:get() ~= BUILD then exit("mode change", "exit") end
    end, { post = true })

    RegisterKeyBind(Key[cfg.move_key], function()
        ExecuteInGameThread(ctx.guard("move key", toggle))
    end)
    RegisterKeyBind(Key.ESCAPE, function()
        ExecuteInGameThread(ctx.guard("move escape", function()
            cancel("Esc")
        end))
    end)
end

return M
