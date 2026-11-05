-- The rules of a move: which construction can move, the move state machine, and the upgrade links
-- after a move. Game-free: plain values in, decisions and action names out.
local M = {}

-- EBuildGridType: None and Furniture (the class default) have no build grid (design Context 8).
local NO_GRID = { [0] = true, [3] = true }

---@class BbPartFields
---@field builtByPlayer boolean
---@field preview boolean
---@field underConstruction boolean
---@field gridType integer the GridType of the loaded config
---@field requireGrid boolean

---@param f BbPartFields
---@return boolean
function M.isMovable(f)
    local noGrid = NO_GRID[f.gridType] == true and not f.requireGrid
    return f.builtByPlayer and not f.preview and not f.underConstruction and noGrid
end

---@class BbMoveMachine
---@field state "build"|"mode"|"moving" the normal build mode, Move mode, or a move
---@field valid boolean the last frame's placement check passed

---@return BbMoveMachine
function M.machine()
    return { state = "build", valid = false }
end

local START = { "collisionOff", "preview", "free", "remember" }
local CANCEL = { "collisionOn", "clear" }

-- One event of Move mode, and the actions that the feature runs in order.
-- Events: toggle (the move key), click { movable }, frame { valid }, cancel, exit (the player
-- left build mode). Each has targetValid.
---@param m BbMoveMachine
---@param event "toggle"|"click"|"frame"|"cancel"|"exit"
---@param data { movable: boolean?, valid: boolean?, targetValid: boolean }
---@return string[]
function M.step(m, event, data)
    if m.state == "build" then
        if event == "toggle" then
            m.state = "mode"
            return { "clearSelection" }
        end
        return {}
    end
    if m.state == "mode" then
        if event == "toggle" or event == "exit" then
            m.state = "build"
        elseif event == "click" and data.movable and data.targetValid then
            m.state, m.valid = "moving", false
            return START
        end
        return {}
    end
    if not data.targetValid or event == "cancel" or event == "toggle" or event == "exit" then
        m.state = "build"
        return CANCEL
    end
    if event == "frame" then
        m.valid = data.valid == true
    elseif event == "click" and m.valid then
        m.state = "build"
        return { "commit", "clear" }
    end
    return {}
end

-- The ids of the links that a move breaks: each entry whose place is farther than radius from center.
---@param center { X: number, Y: number, Z: number }
---@param links { id: any, pos: { X: number, Y: number, Z: number } }[]
---@param radius number
---@return any[]
function M.dropUpgrades(center, links, radius)
    local drop = {}
    for _, link in ipairs(links) do
        local dx, dy, dz = link.pos.X - center.X, link.pos.Y - center.Y, link.pos.Z - center.Z
        if dx * dx + dy * dy + dz * dz > radius * radius then drop[#drop + 1] = link.id end
    end
    return drop
end

return M
