local fakes = require("fakes")

local FEATURE_MODULES = { "bb.placement.feature", "bb.move.feature", "bb.move.ui" }

-- Loads Scripts/main.lua with this config and stub feature modules. installs maps a module name to
-- a function that its install calls. Returns the fake env, the modules in install order, and the
-- count of start calls of the hook registry.
local function loadMain(config, installs)
    installs = installs or {}
    local env = fakes.install()
    local order, starts = {}, { n = 0 }
    package.loaded["bb.core.config_file"] = {
        load = function()
            return config
        end,
    }
    package.loaded["bb.hooks"] = {
        new = function()
            return {
                start = function()
                    starts.n = starts.n + 1
                end,
            }
        end,
    }
    for _, name in ipairs(FEATURE_MODULES) do
        package.loaded[name] = {
            install = function(ctx)
                order[#order + 1] = name
                assert(ctx.bp, "the hook registry is set before the features install")
                if installs[name] then installs[name](ctx) end
            end,
        }
    end
    dofile("Scripts/main.lua")
    return env, order, starts.n
end

local function lines(env, pattern)
    local found = {}
    for _, line in ipairs(env.printed) do
        if line:find(pattern) then found[#found + 1] = line end
    end
    return found
end

local DEFAULTS = {
    allow_collision = true,
    allow_no_build_zones = true,
    allow_move = true,
    move_key = "V",
    verbose = false,
}

local function with(changes)
    local cfg = {}
    for k, v in pairs(DEFAULTS) do
        cfg[k] = v
    end
    for k, v in pairs(changes) do
        cfg[k] = v
    end
    return cfg
end

describe("main", function()
    after_each(function()
        fakes.restore()
        package.loaded["bb.core.config_file"] = nil
        package.loaded["bb.hooks"] = nil
        for _, name in ipairs(FEATURE_MODULES) do
            package.loaded[name] = nil
        end
    end)

    it("installs each feature in order, then starts the hook registry once", function()
        local _, order, starts = loadMain(DEFAULTS)
        assert.are.same(FEATURE_MODULES, order)
        assert.are.equal(1, starts)
    end)

    it("prints the load line with the switches and the key", function()
        local env = loadMain(DEFAULTS)
        assert.are.equal(
            1,
            #lines(env, "^%[BetterBuilding%] v1%.0%.1 loaded %(collision on, no%-build zones on, move on, key V%)\n$")
        )
    end)

    it("gives one warning for a feature whose install throws, and still installs the others", function()
        local env, order = loadMain(DEFAULTS, {
            ["bb.placement.feature"] = function()
                error("no component")
            end,
        })
        assert.are.same(FEATURE_MODULES, order)
        assert.are.equal(1, #lines(env, "WARN placement not installed %(a game change%?%): .*no component"))
        assert.are.equal(1, #lines(env, "loaded"))
    end)

    it("skips the move feature and its UI with allow_move off", function()
        local env, order = loadMain(with({ allow_move = false }))
        assert.are.same({ "bb.placement.feature" }, order)
        assert.are.equal(1, #lines(env, "move off"))
    end)

    it("skips the placement feature with both placement switches off", function()
        local env, order = loadMain(with({ allow_collision = false, allow_no_build_zones = false }))
        assert.are.same({ "bb.move.feature", "bb.move.ui" }, order)
        assert.are.equal(1, #lines(env, "collision off, no%-build zones off"))
    end)

    it("installs the placement feature with one placement switch on", function()
        local _, order = loadMain(with({ allow_collision = false }))
        assert.are.equal("bb.placement.feature", order[1])
    end)
end)
