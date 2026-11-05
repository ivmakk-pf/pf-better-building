-- The rules of the placement switches. Game-free: plain values in, a decision out.
local M = {}

---@class BbCollisionResult
---@field blocked boolean CollisionBlocked of the game's CollisionCheck
---@field groundFail boolean GroundFail: no ground under the construction ("CAN'T BUILD IN AIR")
---@field hidePreview boolean HidePreview: the exact place of an existing construction
---@field characterPresent boolean a character (a player or an animal) overlaps the construction
---@field ownPresent boolean a construction that a player built overlaps the construction

-- True when the mod clears the block: a world object blocks, and no ground failure, no exact-place
-- stack, no character, and no construction that a player built.
---@param result BbCollisionResult
---@param switches { allow_collision: boolean }
---@return boolean
function M.clearCollision(result, switches)
    return switches.allow_collision == true
        and result.blocked
        and not result.groundFail
        and not result.hidePreview
        and not result.characterPresent
        and not result.ownPresent
end

-- True when the mod clears "NO-BUILD ZONE".
---@param switches { allow_no_build_zones: boolean }
---@return boolean
function M.clearZone(switches)
    return switches.allow_no_build_zones == true
end

return M
