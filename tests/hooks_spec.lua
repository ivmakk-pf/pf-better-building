local fakes = require("fakes")
local match = require("luassert.match")

local BPC = "/Game/X/BP_PlayerBuildingComponent.BP_PlayerBuildingComponent_C"

describe("bb.hooks", function()
    local env, ctx, reg, now

    before_each(function()
        env = fakes.install()
        package.loaded["bb.hooks"] = nil
        now = 0
        ctx = require("bb.core.context").new("T", function()
            return now
        end)
        ctx.config = { verbose = true }
        reg = require("bb.hooks").new(ctx)
    end)

    after_each(function()
        fakes.restore()
    end)

    local function lines(pattern)
        local found = {}
        for _, line in ipairs(env.printed) do
            if line:find(pattern) then found[#found + 1] = line end
        end
        return found
    end

    local function load()
        env.objects[BPC] = fakes.object({ class = "Class", name = "BP_PlayerBuildingComponent_C" })
    end

    it("registers a hook at the map load when its class is in memory, once per path", function()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        assert.spy(env.spy.RegisterHook).was.not_called()
        load()
        env.loadMap.post[1]()
        env.loadMap.post[1]()
        assert.spy(env.spy.RegisterHook).was.called(1)
        assert.is_function(env.hooks[BPC .. ":CheckForExclusionZone"])
        assert.are.equal(1, #lines("hook .*CheckForExclusionZone %(map load%)"))
    end)

    it("registers at the start when the class is in memory already", function()
        load()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        assert.spy(env.spy.RegisterHook).was.called(1)
    end)

    it("registers from a retry each second, with one deferred call each run, and then stops the retry", function()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        local deferred = {}
        -- A variable key, so LuaLS keeps the UE4SS type of the global (testing-tooling.md).
        local name = "ExecuteInGameThread"
        _G[name] = function(fn)
            deferred[#deferred + 1] = fn
        end
        assert.spy(env.spy.LoopAsync).was.called_with(1000, match._)
        env.tick()
        assert.are.equal(1, #deferred)
        deferred[1]()
        assert.spy(env.spy.RegisterHook).was.not_called()
        load()
        env.tick()
        deferred[2]()
        assert.spy(env.spy.RegisterHook).was.called(1)
        assert.are.equal(1, #lines("hook .*CheckForExclusionZone %(retry%)"))
        env.tick()
        assert.are.equal(0, #env.loops)
        assert.are.equal(2, #deferred)
    end)

    it("queues no second deferred call while one waits", function()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        local deferred = {}
        local name = "ExecuteInGameThread"
        _G[name] = function(fn)
            deferred[#deferred + 1] = fn
        end
        env.tick()
        env.tick()
        assert.are.equal(1, #deferred)
    end)

    it("starts no retry when each hook registers at the start, and watches no new objects", function()
        load()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        assert.spy(env.spy.LoopAsync).was.not_called()
        assert.spy(env.spy.NotifyOnNewObject).was.not_called()
    end)

    it("shares one hook between two listeners of one path, each in its own guard", function()
        local calls = {}
        reg.listen("a", BPC, "PreviewLocation", function()
            error("broken")
        end, {})
        reg.listen("b", BPC, "PreviewLocation", function(self)
            calls[#calls + 1] = self
        end, {})
        load()
        reg.start()
        assert.spy(env.spy.RegisterHook).was.called(1)
        env.hooks[BPC .. ":PreviewLocation"]("bpc")
        env.hooks[BPC .. ":PreviewLocation"]("bpc")
        assert.are.same({ "bpc", "bpc" }, calls)
        assert.are.equal(1, #lines("WARN a: .*broken"))
    end)

    it("gives one warning for a failed registration and does not try it again", function()
        env.failHook = ":CollisionCheck"
        reg.listen("collision", BPC, "CollisionCheck", function() end, {})
        load()
        reg.start()
        env.loadMap.post[1]()
        assert.spy(env.spy.RegisterHook).was.called(1)
        assert.are.equal(1, #lines("WARN .*CollisionCheck"))
    end)

    it("logs the mean time of the timed calls for each frame once a second, with verbose on", function()
        reg.listen("preview", BPC, "PreviewLocation", function()
            now = now + 0.00002
        end, { timed = true, perFrame = true })
        reg.listen("zone", BPC, "CheckForExclusionZone", function()
            now = now + 0.00001
        end, { timed = true })
        load()
        reg.start()
        for _ = 1, 4 do
            env.hooks[BPC .. ":PreviewLocation"]()
            env.hooks[BPC .. ":CheckForExclusionZone"]()
            now = now + 0.3
        end
        assert.are.equal(0, #lines("timing "))
        env.hooks[BPC .. ":PreviewLocation"]()
        local timing = lines("timing ")
        assert.are.equal(1, #timing)
        assert.matches("timing 0%.030 ms each frame %(frames 4, calls 8%)", timing[1])
    end)

    it("times nothing with verbose off", function()
        ctx.config.verbose = false
        reg.listen("preview", BPC, "PreviewLocation", function()
            now = now + 0.3
        end, { timed = true, perFrame = true })
        load()
        reg.start()
        for _ = 1, 5 do
            env.hooks[BPC .. ":PreviewLocation"]()
        end
        assert.are.equal(0, #lines("timing "))
    end)

    it("wraps a function in the timing counter for a hook that a feature registers itself", function()
        local timed = reg.timed(function(x)
            now = now + 0.001
            return x * 2
        end, true)
        assert.are.equal(4, timed(2))
        now = now + 1.5
        timed(1)
        assert.matches("timing 1%.000 ms each frame %(frames 1, calls 1%)", lines("timing ")[1])
    end)
end)
