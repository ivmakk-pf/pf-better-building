local fakes = require("fakes")

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

    -- A lookup of a class that is not in memory walks the whole object array: one for each class.
    it("looks up each class once in a pass, also with several hooks on it", function()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.listen("collision", BPC, "CollisionCheck", function() end, {})
        reg.start()
        assert.spy(env.spy.StaticFindObject).was.called(1)
        load()
        env.loadMap.post[1]()
        assert.spy(env.spy.StaticFindObject).was.called(2)
        assert.spy(env.spy.RegisterHook).was.called(2)
    end)

    it("registers at the start when the class is in memory already", function()
        load()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        assert.spy(env.spy.RegisterHook).was.called(1)
    end)

    -- A lookup of a class that is not in memory walks the whole object array, which crashed the game
    -- while it streamed the world: no lookup runs on a timer.
    it("starts no loop and watches no new objects, also while a hook waits for its class", function()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        assert.spy(env.spy.LoopAsync).was.not_called()
        assert.spy(env.spy.NotifyOnNewObject).was.not_called()
        assert.spy(env.spy.StaticFindObject).was.called(1)
    end)

    it("registers a hook that waits for build mode only at wake, never at the start or a map load", function()
        local TOOL = "/Game/X/BP_Holdable_MultiTool.BP_Holdable_MultiTool_C"
        env.objects[TOOL] = fakes.object({ class = "Class", name = "BP_Holdable_MultiTool_C" })
        reg.listen("hint", TOOL, "ShowHUDInputHints", function() end, { wait = "build mode" })
        reg.start()
        env.loadMap.post[1]()
        assert.spy(env.spy.StaticFindObject).was.not_called()
        assert.spy(env.spy.RegisterHook).was.not_called()
        reg.wake("build mode")
        reg.wake("build mode")
        assert.spy(env.spy.RegisterHook).was.called(1)
        assert.spy(env.spy.StaticFindObject).was.called(1)
        assert.are.equal(1, #lines("hook .*ShowHUDInputHints %(build mode%)"))
    end)

    it("looks up no class of a hook with no wait at wake", function()
        reg.listen("zone", BPC, "CheckForExclusionZone", function() end, {})
        reg.start()
        reg.wake("build mode")
        assert.spy(env.spy.StaticFindObject).was.called(1)
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
