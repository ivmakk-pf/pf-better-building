local logic = require("bb.placement.logic")

local ON = { allow_collision = true, allow_no_build_zones = true }
local OFF = { allow_collision = false, allow_no_build_zones = false }

local function result(changes)
    local r = { blocked = true, groundFail = false, hidePreview = false, characterPresent = false, ownPresent = false }
    for k, v in pairs(changes or {}) do
        r[k] = v
    end
    return r
end

describe("placement logic", function()
    describe("clearCollision", function()
        it("keeps a block by a construction that a player built", function()
            assert.is_false(logic.clearCollision(result({ ownPresent = true }), ON))
        end)

        it("clears a block by a world object with the collision switch on", function()
            assert.is_true(logic.clearCollision(result(), ON))
        end)

        it("keeps the block with the collision switch off", function()
            assert.is_false(logic.clearCollision(result(), OFF))
        end)

        it("keeps a missing ground, so the game shows CAN'T BUILD IN AIR", function()
            assert.is_false(logic.clearCollision(result({ groundFail = true }), ON))
        end)

        it("keeps a construction at the exact place of another one", function()
            assert.is_false(logic.clearCollision(result({ hidePreview = true }), ON))
        end)

        it("keeps a block by a character", function()
            assert.is_false(logic.clearCollision(result({ characterPresent = true }), ON))
        end)

        it("has nothing to clear for a result that is not blocked", function()
            assert.is_false(logic.clearCollision(result({ blocked = false }), ON))
        end)
    end)

    describe("clearZone", function()
        it("gives the value of the no-build zone switch", function()
            assert.is_true(logic.clearZone(ON))
            assert.is_false(logic.clearZone(OFF))
        end)
    end)
end)
