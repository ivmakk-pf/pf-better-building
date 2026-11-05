-- Collision and no-build zones: post hooks of the game's single placement checks write their out
-- parameters, so the later checks of AdditionalBuildChecks still run as in the game.
-- A Blueprint hook runs after the function body, and a write to an out parameter reaches the caller.
local logic = require("bb.placement.logic")
local paths = require("bb.paths")

local M = {}

-- The object types WorldStatic to Destructible (EObjectTypeQuery 0 to 5): the class filter Character
-- keeps only the characters.
local OBJECT_TYPES = { 0, 1, 2, 3, 4, 5 }
local OVERLAP_KEEP = 0.1 -- s

---@param ctx BbContext
function M.install(ctx)
    local cfg = ctx.config
    local lastLine = {} ---@type table<string, string>

    -- One verbose line for each write, with no repeat of the same line on the next frames. Each kind
    -- (collision, zone) keeps its own last line, because the game runs both checks in each frame.
    local function traceWrite(kind, line)
        if line == lastLine[kind] then return end
        lastLine[kind] = line
        ctx.trace(line)
    end

    local function className(obj)
        return ctx.try(function()
            return obj:GetClass():GetFName():ToString()
        end) or "?"
    end

    -- The engine objects of the overlaps, found once.
    local ksl = nil ---@type any
    local character = nil ---@type UClass?
    local buildPart = nil ---@type UClass?

    -- The last overlap result: the construction, its time, whether a character overlapped, and
    -- whether a construction that a player built overlapped. The game runs CollisionCheck at each
    -- frame (and more than once), so one overlap serves 0.1 s.
    local last = { key = nil, time = -math.huge, character = false, own = false }

    -- True when a character overlaps the bounds of the construction (only the box
    -- overlap finds one).
    local function characterAt(part)
        local origin, extent = {}, {}
        part:GetActorBounds(true, origin, extent, false)
        local out = {}
        ksl:BoxOverlapActors(part, origin, extent, OBJECT_TYPES, character --[[@as UClass]], { part }, out)
        return #out > 0
    end

    -- An element of an array that UE4SS filled: a wrapped value or the object itself.
    local function unwrap(value)
        return ctx.try(function()
            return value:get()
        end) or value
    end

    local function ownBuilt(actor)
        return ctx.valid(actor)
            and actor:IsA(buildPart --[[@as UClass]])
            and actor.bBuiltByPlayer == true
            and actor.bIsPreview ~= true
    end

    -- True when a collision box of the construction overlaps a construction that a player built: the
    -- game's own overlap of CollisionCheck, with its object types. The bounds box is
    -- larger than the collision boxes, so it would block a foundation that snaps next to another one.
    local function ownAt(bpc, part)
        local types = { 0, 1, 2, 3, 5, 6, bpc.BuildPartCollisionObjectType }
        local found = false
        part.BuildCollisions:ForEach(function(_, element)
            if found then return end
            local box = element:get()
            local out = {}
            ksl:ComponentOverlapComponents(box, box:K2_GetComponentToWorld(), types, nil, { part }, out)
            for _, component in ipairs(out) do
                if ownBuilt(unwrap(component):GetOwner()) then
                    found = true
                    return
                end
            end
        end)
        return found
    end

    -- The place of the construction: the preview actor moves at each frame, so a result is kept
    -- only for the same actor at the same place and rotation.
    local function placeKey(part)
        local loc, rot = part:K2_GetActorLocation(), part:K2_GetActorRotation()
        return string.format("%x %.1f %.1f %.1f %.1f", part:GetAddress(), loc.X, loc.Y, loc.Z, rot.Yaw)
    end

    ---@return boolean character, boolean own
    local function overlapsAt(bpc, part)
        local now, key = ctx.now(), placeKey(part)
        if key == last.key and now - last.time < OVERLAP_KEEP then return last.character, last.own end
        if not ctx.valid(ksl) then
            ksl = StaticFindObject(paths.KSL)
            character = StaticFindObject(paths.CHARACTER) --[[@as UClass]]
            buildPart = StaticFindObject(paths.BUILD_PART) --[[@as UClass]]
        end
        local characterFound = characterAt(part)
        local ownFound = not characterFound and ownAt(bpc, part)
        last.key, last.time, last.character, last.own = key, now, characterFound, ownFound
        return characterFound, ownFound
    end

    if cfg.allow_collision then
        ctx.bp.listen("collision", paths.BPC, "CollisionCheck", function(selfP, partP, blockedP, hideP, groundP)
            if blockedP:get() ~= true then return end
            local result = {
                blocked = true,
                groundFail = groundP:get() == true,
                hidePreview = hideP:get() == true,
                characterPresent = false,
                ownPresent = false,
            }
            if result.groundFail or result.hidePreview then return end
            local part = partP:get()
            result.characterPresent, result.ownPresent = overlapsAt(selfP:get(), part)
            if logic.clearCollision(result, cfg) then
                blockedP:set(false)
                traceWrite("collision", "collision cleared for " .. className(part))
            elseif result.ownPresent then
                traceWrite("collision", "collision kept for " .. className(part) .. ": own construction")
            end
        end, { timed = true })
    end

    if logic.clearZone(cfg) then
        ctx.bp.listen("zone", paths.BPC, "CheckForExclusionZone", function(_, partP, canP)
            if canP:get() ~= false then return end
            canP:set(true)
            traceWrite("zone", "no-build zone cleared for " .. className(partP:get()))
        end, { timed = true, perFrame = true })
    end
end

return M
