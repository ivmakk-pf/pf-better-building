-- The state that does not follow an actor move: the links between a workstation and its
-- upgrades, and the heat zone and snow mask that a brazier or a smelter spawns at its place.
local logic = require("bb.move.logic")
local paths = require("bb.paths")

local M = {}

-- The elements of a TArray property, or of a Lua table (the specs).
local function elements(array)
    local list = {}
    if type(array) == "table" and not array.ForEach then
        for _, e in ipairs(array) do
            list[#list + 1] = e
        end
    elseif array then
        array:ForEach(function(_, e)
            list[#list + 1] = e:get()
        end)
    end
    return list
end

---@param ctx BbContext
function M.install(ctx)
    -- True when a class in the class chain of the object has the name of the class at path. It looks
    -- up no class: a lookup of a class that is not in memory walks the whole object array.
    local function isA(obj, path)
        local name = path:match("%.([^.]+)$")
        local class = obj:GetClass()
        for _ = 1, 16 do
            if not ctx.valid(class) then return false end
            if class:GetFName():ToString() == name then return true end
            class = class:GetSuperStruct()
        end
        return false
    end

    local function same(a, b)
        return a:GetAddress() == b:GetAddress()
    end

    local function radiusOf(bpc)
        return bpc.BuildingSystemConfig.WorkbenchUpgradeCheckRadius
    end

    -- A moved workstation: the upgrades out of range leave it, then the game's own search runs.
    local function relinkStation(station, loc, radius)
        local upgrades = elements(station.AddedUpgrades)
        local links = {}
        for i, u in ipairs(upgrades) do
            links[i] = { id = i, pos = u:K2_GetActorLocation() }
        end
        local drop = {}
        for _, i in ipairs(logic.dropUpgrades(loc, links, radius)) do
            drop[i] = true
        end
        local kept, dropped = {}, 0
        for i, u in ipairs(upgrades) do
            if drop[i] then
                u.UpgradedWorkstation = nil
                dropped = dropped + 1
            else
                kept[#kept + 1] = u
            end
        end
        if dropped > 0 then
            station.AddedUpgrades = kept
            ctx.trace("upgrades dropped " .. dropped)
        end
        station:FindWorkstationUpgrades()
    end

    -- A moved upgrade: it keeps a workstation that is still in range. Else it leaves it, and the
    -- game's own search runs. The search links to the first compatible workstation that it finds and
    -- keeps no old link, so it must not run while the old link stays.
    local function relinkUpgrade(upgrade, loc, radius)
        local station = upgrade.UpgradedWorkstation
        if ctx.valid(station) then
            local links = { { id = 1, pos = station:K2_GetActorLocation() } }
            if #logic.dropUpgrades(loc, links, radius) == 0 then return end
            local kept = {}
            for _, u in ipairs(elements(station.AddedUpgrades)) do
                if not same(u, upgrade) then kept[#kept + 1] = u end
            end
            station.AddedUpgrades = kept
            upgrade.UpgradedWorkstation = nil
            ctx.trace("upgrade left its workstation")
        end
        upgrade:FindAndUpgradeWorkstation()
    end

    -- The heat zone and the snow mask stand apart from the construction: they move by the same change.
    local function moveAttached(target, data)
        local dx, dy, dz = data.loc.X - data.old.loc.X, data.loc.Y - data.old.loc.Y, data.loc.Z - data.old.loc.Z
        local dyaw = data.rot.Yaw - data.old.rot.Yaw
        for _, name in ipairs({ "HeatZoneInstance", "SnowMaskRef" }) do
            local obj = ctx.try(function()
                return target[name]
            end)
            if ctx.valid(obj) then
                local loc, rot = obj:K2_GetActorLocation(), obj:K2_GetActorRotation()
                obj:K2_SetActorLocationAndRotation(
                    { X = loc.X + dx, Y = loc.Y + dy, Z = loc.Z + dz },
                    { Pitch = rot.Pitch, Yaw = rot.Yaw + dyaw, Roll = rot.Roll },
                    false,
                    {},
                    true
                )
                ctx.trace("moved " .. name)
            end
        end
    end

    ctx.on("move committed", function(data)
        local target = data.target
        if isA(target, paths.WORKSTATION) then
            relinkStation(target, data.loc, radiusOf(data.bpc))
            moveAttached(target, data)
        elseif isA(target, paths.UPGRADE) then
            relinkUpgrade(target, data.loc, radiusOf(data.bpc))
        end
    end)
end

return M
