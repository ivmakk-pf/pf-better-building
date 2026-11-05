-- BetterBuilding: build over objects and in no-build zones, and move a placed construction that
-- does not snap to the build grid. Each feature has its own switch in config.lua.
local MOD = "BetterBuilding"
local VERSION = "1.0.0"

local SCHEMA = require("bb.core.schema")

-- Each feature: the warning key, the module, and the switches that turn it on. A feature that
-- fails to install logs one warning, and the others still install.
local FEATURES = {
    {
        key = "placement",
        module = "bb.placement.feature",
        on = function(cfg)
            return cfg.allow_collision or cfg.allow_no_build_zones
        end,
    },
    {
        key = "move",
        module = "bb.move.feature",
        on = function(cfg)
            return cfg.allow_move
        end,
    },
    {
        key = "move ui",
        module = "bb.move.ui",
        on = function(cfg)
            return cfg.allow_move
        end,
    },
}

local ctx = require("bb.core.context").new(MOD)
ctx.config = require("bb.core.config_file").load(SCHEMA, ctx.log)
ctx.bp = require("bb.hooks").new(ctx)

for _, feature in ipairs(FEATURES) do
    if feature.on(ctx.config) then
        local ok, err = pcall(function()
            require(feature.module).install(ctx)
        end)
        if not ok then
            ctx.warnOnce(feature.key, feature.key .. " not installed (a game change?): " .. tostring(err))
        end
    end
end
ctx.bp.start()

local cfg = ctx.config
local function onOff(value)
    return value and "on" or "off"
end
ctx.log(
    string.format(
        "v%s loaded (collision %s, no-build zones %s, move %s, key %s)",
        VERSION,
        onOff(cfg.allow_collision),
        onOff(cfg.allow_no_build_zones),
        onOff(cfg.allow_move),
        cfg.move_key
    )
)
