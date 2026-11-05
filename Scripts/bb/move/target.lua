-- The construction under the crosshair: the hit actor of the game's own screen-center trace
-- (ClientBlockingHit, which BuildTrace fills at each frame), the same target as Deconstruction.
local paths = require("bb.paths")

local M = {}

---@class BbTarget
---@field under fun(bpc: any): any the construction (an ABuildPartBase) under the crosshair, or nil
---@field fields fun(part: any): BbPartFields the values of the movable rule

---@param ctx BbContext
---@return BbTarget
function M.new(ctx)
    local finder = {} ---@type BbTarget
    local buildPart = nil

    -- The hit object of an FHitResult: a component, whose owner is the actor, or the actor itself.
    local function hitActor(hit)
        local object = ctx.try(function()
            return hit.HitObjectHandle.ReferenceObject:Get()
        end)
        if not ctx.valid(object) then return nil end
        local owner = ctx.try(function()
            return object:GetOwner()
        end)
        if ctx.valid(owner) then return owner end
        return object
    end

    function finder.under(bpc)
        if not ctx.valid(buildPart) then buildPart = StaticFindObject(paths.BUILD_PART) end
        local actor = hitActor(bpc.ClientBlockingHit)
        if actor and actor:IsA(buildPart) then return actor end
        return nil
    end

    function finder.fields(part)
        local config = part.BuildConfigLoaded
        return {
            builtByPlayer = part.bBuiltByPlayer == true,
            preview = part.bIsPreview == true,
            underConstruction = part.bUnderConstruction == true,
            gridType = config.GridType,
            requireGrid = config.bRequireGrid == true,
        }
    end

    return finder
end

return M
