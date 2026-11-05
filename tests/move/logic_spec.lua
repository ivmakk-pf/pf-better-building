local logic = require("bb.move.logic")

local function fields(changes)
    local f = { builtByPlayer = true, preview = false, underConstruction = false, gridType = 3, requireGrid = false }
    for k, v in pairs(changes or {}) do
        f[k] = v
    end
    return f
end

describe("move logic", function()
    describe("isMovable", function()
        it("is true for a finished construction of the player with GridType Furniture or None", function()
            assert.is_true(logic.isMovable(fields()))
            assert.is_true(logic.isMovable(fields({ gridType = 0 })))
        end)

        it("is false for each reason alone", function()
            for _, changes in ipairs({
                { builtByPlayer = false },
                { preview = true },
                { underConstruction = true },
                { gridType = 18 },
                { gridType = 4 },
                { gridType = 1 },
                { requireGrid = true },
            }) do
                assert.is_false(logic.isMovable(fields(changes)))
            end
        end)
    end)

    describe("the move machine", function()
        local m
        local START = { "collisionOff", "preview", "free", "remember" }
        local CANCEL = { "collisionOn", "clear" }

        before_each(function()
            m = logic.machine()
        end)

        ---@param event "toggle"|"click"|"frame"|"cancel"|"exit"
        local function step(event, data)
            data = data or {}
            if data.targetValid == nil then data.targetValid = true end
            return logic.step(m, event, data)
        end

        local function enter()
            return step("toggle")
        end

        local function start()
            enter()
            return step("click", { movable = true })
        end

        it("starts in build", function()
            assert.are.equal("build", m.state)
        end)

        describe("toggle", function()
            it("from build gives Move mode and clears the selection", function()
                assert.are.same({ "clearSelection" }, enter())
                assert.are.equal("mode", m.state)
            end)

            it("from Move mode gives build", function()
                enter()
                assert.are.same({}, step("toggle"))
                assert.are.equal("build", m.state)
            end)

            it("from a move cancels it and gives build", function()
                start()
                assert.are.same(CANCEL, step("toggle"))
                assert.are.equal("build", m.state)
            end)
        end)

        describe("click", function()
            it("in Move mode on a movable construction starts the move", function()
                assert.are.same(START, start())
                assert.are.equal("moving", m.state)
            end)

            it("in Move mode on a construction that cannot move does nothing", function()
                enter()
                assert.are.same({}, step("click", { movable = false }))
                assert.are.same({}, step("click", { movable = true, targetValid = false }))
                assert.are.equal("mode", m.state)
            end)

            it("in build does nothing", function()
                assert.are.same({}, step("click", { movable = true }))
                assert.are.equal("build", m.state)
            end)

            it("commits a move after a frame with a valid place and gives build", function()
                start()
                assert.are.same({}, step("frame", { valid = true }))
                assert.are.same({ "commit", "clear" }, step("click"))
                assert.are.equal("build", m.state)
            end)

            it("keeps the move after a frame with an invalid place", function()
                start()
                step("frame", { valid = true })
                step("frame", { valid = false })
                assert.are.same({}, step("click"))
                assert.are.equal("moving", m.state)
            end)

            it("keeps the move before any frame", function()
                start()
                assert.are.same({}, step("click"))
                assert.are.equal("moving", m.state)
            end)
        end)

        describe("cancel and exit", function()
            it("a cancel of a move puts the target back and gives build", function()
                start()
                assert.are.same(CANCEL, step("cancel"))
                assert.are.equal("build", m.state)
            end)

            it("an exit gives build from each state, with the cancel actions only from a move", function()
                assert.are.same({}, step("exit"))
                assert.are.equal("build", m.state)
                enter()
                assert.are.same({}, step("exit"))
                assert.are.equal("build", m.state)
                start()
                assert.are.same(CANCEL, step("exit"))
                assert.are.equal("build", m.state)
            end)

            it("any event of a move with an invalid target cancels it", function()
                for _, event in ipairs({ "frame", "click", "cancel" }) do
                    m = logic.machine()
                    start()
                    assert.are.same(CANCEL, step(event, { valid = true, targetValid = false }))
                    assert.are.equal("build", m.state)
                end
            end)

            it("a frame or a cancel outside a move does nothing", function()
                for _, event in ipairs({ "frame", "cancel" }) do
                    assert.are.same({}, step(event, { valid = true }))
                    enter()
                    assert.are.same({}, step(event, { valid = true }))
                    assert.are.equal("mode", m.state)
                    m = logic.machine()
                end
            end)
        end)

        it("starts a new move with no stored place from the last one", function()
            start()
            step("frame", { valid = true })
            step("cancel")
            start()
            assert.are.same({}, step("click"))
        end)
    end)

    describe("dropUpgrades", function()
        local function at(x)
            return { X = x, Y = 0, Z = 0 }
        end

        it("drops the upgrades out of the radius of a moved workstation and keeps the others", function()
            local drop =
                logic.dropUpgrades(at(0), { { id = "near", pos = at(150) }, { id = "far", pos = at(450) } }, 300)
            assert.are.same({ "far" }, drop)
        end)

        it("drops the workstation of a moved upgrade when it is out of the radius", function()
            assert.are.same({ "bench" }, logic.dropUpgrades(at(1000), { { id = "bench", pos = at(0) } }, 300))
            assert.are.same({}, logic.dropUpgrades(at(200), { { id = "bench", pos = at(0) } }, 300))
        end)

        it("keeps an upgrade at the radius edge", function()
            assert.are.same({}, logic.dropUpgrades(at(0), { { id = "edge", pos = at(300) } }, 300))
        end)
    end)
end)
