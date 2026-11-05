local config_file = require("bb.core.config_file")

local SCHEMA = {
    { key = "allow_move", default = true, comment = "Move a construction." },
    { key = "range_m", default = 15, min = 1, max = 100, comment = "Range, in metres." },
    { key = "move_key", default = "V", keyName = true, comment = "Key of the move." },
}

describe("the mod schema", function()
    local schema = require("bb.core.schema")
    local config_logic = require("bb.core.config_logic")

    local function validate(raw)
        local warnings = {}
        local cfg = config_logic.validate(raw, schema, function(key, message)
            warnings[#warnings + 1] = key .. ": " .. message
        end)
        return cfg, warnings
    end

    it("has the three switches on, the move key V, and verbose off by default", function()
        local cfg, warnings = validate({})
        assert.are.same({
            allow_collision = true,
            allow_no_build_zones = true,
            allow_move = true,
            move_key = "V",
            verbose = false,
        }, cfg)
        assert.are.equal(0, #warnings)
    end)

    it("gives each entry a comment", function()
        for _, entry in ipairs(schema) do
            assert(type(entry.comment) == "string" and #entry.comment > 0, entry.key)
        end
    end)

    it("gives the default key and one warning that names the key for NOT_A_KEY", function()
        local cfg, warnings = validate({ move_key = "NOT_A_KEY" })
        assert.are.equal("V", cfg.move_key)
        assert.are.equal(1, #warnings)
        assert.matches("^move_key: ", warnings[1])
    end)

    it("gives the default switch and one warning for a text switch", function()
        local cfg, warnings = validate({ allow_move = "yes" })
        assert.are.equal(true, cfg.allow_move)
        assert.are.equal(1, #warnings)
        assert.matches("^allow_move: ", warnings[1])
    end)
end)

describe("config_file.text", function()
    it("writes each key with its default, as a Lua file that returns a table", function()
        local chunk = assert(load(config_file.text(SCHEMA)))
        local cfg = chunk()
        assert.are.equal(true, cfg.allow_move)
        assert.are.equal(15, cfg.range_m)
        assert.are.equal("V", cfg.move_key)
    end)

    it("writes the comment of each key above it, with the range of a number and the keys of a key entry", function()
        local text = config_file.text(SCHEMA)
        assert(text:find("%-%- Move a construction%.\n%s*allow_move = true,"), text)
        assert(text:find("%-%- Range, in metres%. %(1 to 100, default 15%)\n%s*range_m = 15,"), text)
        assert(
            text:find('%-%- Key of the move%. %(a letter A to Z or F1 to F12, default "V"%)\n%s*move_key = "V",'),
            text
        )
    end)
end)
