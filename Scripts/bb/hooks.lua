-- The registration of the Blueprint hooks and the timing counter that the features share.
-- A Blueprint class is in memory only after its asset loads, so each hook registers at a trigger
-- where its class should be in memory: the start and each map load, or, for a hook that waits for
-- build mode, the entry into build mode (the Building Tool is in hand then).
-- The class lookup is StaticFindObject: a class in memory is a hash lookup, but a miss walks the
-- whole object array, and a walk while the async loading thread makes objects can read a half-made
-- object: a native crash. So there is no retry on a timer, and each trigger is a rare event.
-- The hooks of one path share one registration, and each listener runs in its own guard.
-- No NotifyOnNewObject: UE4SS runs its callback on the thread that makes the object, also the async
-- loading thread, and that callback waits for the Lua lock while a hook on the game thread holds it
-- and waits for the async loading: the game hangs.
local M = {}

---@class BbListenOpts
---@field timed boolean? the calls go through the timing counter
---@field perFrame boolean? with timed: the hook runs once each frame, so its calls count the frames
---@field onRegister function? runs once, in a guard, right after the hook registers
---@field wait "build mode"? the class loads with the Building Tool: the hook registers at wake(), not at the start or a map load

---@class BbHooks
---@field listen fun(key: string, classPath: string, fnName: string, fn: function, opts: BbListenOpts)
---@field start fun() installs the triggers and registers what is in memory already
---@field wake fun(reason: string) registers the waiting hooks of build mode whose class is in memory
---@field timed fun(fn: function, perFrame: boolean?): function fn through the timing counter

---@param ctx BbContext
---@return BbHooks
function M.new(ctx)
    local reg = {} ---@type BbHooks
    local paths = {} ---@type { path: string, classPath: string, listeners: function[], done: boolean, wait: string? }[]
    local byPath = {} ---@type table<string, table>

    -- The timing window: the time of the timed calls, the call count, and the frames (the most
    -- calls of one per-frame hook). It logs once a second, at the first call after the second.
    local window = { start = nil, time = 0, calls = 0, frames = {} }

    local function flush(now)
        local frames = 0
        for _, n in pairs(window.frames) do
            if n > frames then frames = n end
        end
        if frames == 0 then frames = window.calls end
        ctx.log(
            string.format(
                "timing %.3f ms each frame (frames %d, calls %d)",
                window.time * 1000 / math.max(frames, 1),
                frames,
                window.calls
            )
        )
        window.start, window.time, window.calls, window.frames = now, 0, 0, {}
    end

    function reg.timed(fn, perFrame)
        local id = {}
        return function(...)
            if not ctx.config.verbose then return fn(...) end
            local t0 = ctx.now()
            if window.start == nil then window.start = t0 end
            if t0 - window.start >= 1 then flush(t0) end
            local result = fn(...)
            window.time = window.time + (ctx.now() - t0)
            window.calls = window.calls + 1
            if perFrame then window.frames[id] = (window.frames[id] or 0) + 1 end
            return result
        end
    end

    function reg.listen(key, classPath, fnName, fn, opts)
        local path = classPath .. ":" .. fnName
        local entry = byPath[path]
        if not entry then
            entry =
                { path = path, classPath = classPath, listeners = {}, onRegister = {}, done = false, wait = opts.wait }
            byPath[path] = entry
            paths[#paths + 1] = entry
        end
        local guarded = ctx.guard(key, fn)
        if opts.timed then guarded = reg.timed(guarded, opts.perFrame) end
        entry.listeners[#entry.listeners + 1] = guarded
        if opts.onRegister then
            entry.onRegister[#entry.onRegister + 1] = ctx.guard(key .. " registered", opts.onRegister)
        end
    end

    local function register(entry, reason)
        entry.done = true
        local listeners = entry.listeners
        if
            ctx.hook("hook " .. entry.path, entry.path, function(...)
                for _, fn in ipairs(listeners) do
                    fn(...)
                end
            end)
        then
            ctx.trace("hook " .. entry.path .. " (" .. reason .. ")")
            for _, fn in ipairs(entry.onRegister) do
                fn()
            end
        end
    end

    -- Registers each hook of this wait kind (nil: no wait) that is not registered yet and whose
    -- class is in memory now. Each class path is looked up once in a pass: the hooks of one class share it.
    local function arm(reason, wait)
        local found = {} ---@type table<string, boolean>
        for _, entry in ipairs(paths) do
            if not entry.done and entry.wait == wait then
                if found[entry.classPath] == nil then
                    found[entry.classPath] = ctx.valid(ctx.try(function()
                        return StaticFindObject(entry.classPath)
                    end))
                end
                if found[entry.classPath] then register(entry, reason) end
            end
        end
    end

    function reg.start()
        arm("start")
        RegisterLoadMapPostHook(function()
            ExecuteInGameThread(ctx.guard("map load", function()
                arm("map load")
            end))
        end)
    end

    function reg.wake(reason)
        arm(reason, "build mode")
    end

    return reg
end

return M
