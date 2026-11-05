local fakes = require("fakes")

describe("context", function()
    local env, context

    before_each(function()
        env = fakes.install()
        package.loaded["bb.core.context"] = nil
        context = require("bb.core.context")
    end)

    after_each(function()
        fakes.restore()
    end)

    it("gives the time of the clock that the caller sets", function()
        local t = 12.5
        local ctx = context.new("BetterBuilding", function()
            return t
        end)
        assert.are.equal(12.5, ctx.now())
        t = 13.25
        assert.are.equal(13.25, ctx.now())
    end)

    it("uses os.clock with no clock given", function()
        local ctx = context.new("BetterBuilding")
        assert.are.equal("number", type(ctx.now()))
    end)

    it("calls each subscriber of an event in order, with the data", function()
        local ctx = context.new("BetterBuilding")
        local calls = {}
        ctx.on("hit", function(data)
            calls[#calls + 1] = "a " .. data.style
        end)
        ctx.on("hit", function(data)
            calls[#calls + 1] = "b " .. data.style
        end)
        ctx.on("kill", function()
            calls[#calls + 1] = "kill"
        end)
        ctx.emit("hit", { style = "head" })
        assert.are.same({ "a head", "b head" }, calls)
    end)

    it("does nothing for an event with no subscriber", function()
        local ctx = context.new("BetterBuilding")
        ctx.emit("kill", {})
        assert.are.equal(0, #env.printed)
    end)

    it("logs a throwing subscriber once and still calls the others", function()
        local ctx = context.new("BetterBuilding")
        local calls = 0
        ctx.on("hit", function()
            error("broken")
        end)
        ctx.on("hit", function()
            calls = calls + 1
        end)
        ctx.emit("hit", {})
        ctx.emit("hit", {})
        assert.are.equal(2, calls)
        assert.are.equal(1, #env.printed)
        assert.matches("^%[BetterBuilding%] WARN .*hit.*broken", env.printed[1])
    end)

    it("registers a hook with a second callback from after, each in its own guard", function()
        local ctx = context.new("BetterBuilding")
        local calls = {}
        assert.is_true(ctx.hook("effect", "/Script/X.Y:Z", function()
            calls[#calls + 1] = "pre"
        end, {
            after = function()
                calls[#calls + 1] = "post"
                error("broken post")
            end,
        }))
        env.hooks["/Script/X.Y:Z"]()
        env.posts["/Script/X.Y:Z"]()
        env.posts["/Script/X.Y:Z"]()
        assert.are.same({ "pre", "post", "post" }, calls)
        assert.are.equal(1, #env.printed)
        assert.matches("WARN effect after: .*broken post", env.printed[1])
    end)
end)
