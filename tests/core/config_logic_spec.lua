local config_logic = require("bb.core.config_logic")

local SCHEMA = {
    { key = "allow_move", default = true, comment = "switch" },
    { key = "range_m", default = 15, min = 1, max = 100, comment = "range" },
    { key = "verbose", default = false, comment = "log" },
}

local function collect()
    local warnings = {}
    return warnings, function(key, message)
        warnings[#warnings + 1] = key .. ": " .. message
    end
end

describe("config_logic.validate", function()
    it("gives the default for a missing key, with no warning", function()
        local warnings, warn = collect()
        local cfg = config_logic.validate({}, SCHEMA, warn)
        assert.are.equal(true, cfg.allow_move)
        assert.are.equal(15, cfg.range_m)
        assert.are.equal(false, cfg.verbose)
        assert.are.equal(0, #warnings)
    end)

    it("keeps a valid value", function()
        local warnings, warn = collect()
        local cfg = config_logic.validate({ allow_move = false, range_m = 30 }, SCHEMA, warn)
        assert.are.equal(false, cfg.allow_move)
        assert.are.equal(30, cfg.range_m)
        assert.are.equal(0, #warnings)
    end)

    it("gives the default for a wrong type, with one warning", function()
        local warnings, warn = collect()
        local cfg = config_logic.validate({ allow_move = "yes", range_m = 20 }, SCHEMA, warn)
        assert.are.equal(true, cfg.allow_move)
        assert.are.equal(20, cfg.range_m)
        assert.are.equal(1, #warnings)
        assert.matches("^allow_move: ", warnings[1])
    end)

    it("gives the default for a number outside the range, with one warning that names the key", function()
        local warnings, warn = collect()
        local cfg = config_logic.validate({ range_m = 500 }, SCHEMA, warn)
        assert.are.equal(15, cfg.range_m)
        assert.are.same({ "range_m: 500 is outside 1 to 100; using 15" }, warnings)
    end)

    it("keeps a number at the range edge, with no warning", function()
        local warnings, warn = collect()
        local cfg = config_logic.validate({ range_m = 100 }, SCHEMA, warn)
        assert.are.equal(100, cfg.range_m)
        assert.are.equal(0, #warnings)
    end)

    it("gives the default for an infinite number or NaN, with one warning", function()
        for _, value in ipairs({ math.huge, -math.huge, 0 / 0 }) do
            local warnings, warn = collect()
            local cfg = config_logic.validate({ range_m = value }, SCHEMA, warn)
            assert.are.equal(15, cfg.range_m)
            assert.are.equal(1, #warnings)
        end
    end)

    it("ignores an unknown key", function()
        local warnings, warn = collect()
        local cfg = config_logic.validate({ old_setting = 3 }, SCHEMA, warn)
        assert.are.equal(nil, cfg.old_setting)
        assert.are.equal(0, #warnings)
    end)

    describe("a key entry", function()
        local KEYS = { { key = "move_key", default = "V", keyName = true, comment = "key" } }

        it("keeps a letter or a function key F1 to F12", function()
            for _, value in ipairs({ "A", "V", "Z", "F1", "F9", "F12" }) do
                local warnings, warn = collect()
                local cfg = config_logic.validate({ move_key = value }, KEYS, warn)
                assert.are.equal(value, cfg.move_key)
                assert.are.equal(0, #warnings)
            end
        end)

        it("gives the default and one warning that names the key for any other text", function()
            for _, value in ipairs({ "NOT_A_KEY", "v", "F13", "F0", "", "SPACE", "VV" }) do
                local warnings, warn = collect()
                local cfg = config_logic.validate({ move_key = value }, KEYS, warn)
                assert.are.equal("V", cfg.move_key)
                assert.are.equal(1, #warnings)
                assert.matches("^move_key: ", warnings[1])
            end
        end)
    end)
end)
