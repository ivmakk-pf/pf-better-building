-- The helpers that all features of BetterBuilding share: the log, the warnings, the guards,
-- the hook registration, the clock, and the events between features. Its own file, so the specs of a feature can make a real context.
local M = {}

---@class BbContext
---@field config table<string, any> the validated settings of config.lua
---@field bp BbHooks the registry of the Blueprint hooks (main.lua sets it before the features install)
---@field log fun(message: string)
---@field warnOnce fun(key: string, message: string)
---@field trace fun(message: string) logs only when `verbose` is on
---@field try fun(fn: fun(): any): any the result of fn, nil when it errors (a stale object, a changed game)
---@field valid fun(obj: any): boolean
---@field guard fun(key: string, fn: function): fun(...): any fn in a pcall that logs each distinct error once; gives the value of fn, nil on an error
---@field hook fun(key: string, path: string, fn: function, opts: { required: boolean?, post: boolean?, after: function? }?): boolean registers fn in a guard (as the second callback with post, which runs after a native body; with after, fn first and after second, each in its own guard); a failure logs one warning, or throws when required
---@field hooks table<string, integer[]> the pre and post ids of each registered hook path
---@field now fun(): number the time in seconds, from the clock of M.new
---@field on fun(name: string, fn: fun(data: table)) subscribes fn to an event
---@field emit fun(name: string, data: table) calls each subscriber of the event in order; a throwing subscriber logs one warning

---@param fn fun(): any
---@return any
local function try(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function valid(obj)
    return obj ~= nil and try(function()
        return obj:IsValid()
    end) == true
end

---@param mod string the tag of each log line
---@param clock (fun(): number)? the source of ctx.now(), os.clock when nil (the specs set their own)
---@return BbContext ctx with an empty config: the caller sets ctx.config after the config load
function M.new(mod, clock)
    local ctx = { config = {}, try = try, valid = valid, hooks = {}, now = clock or os.clock } ---@type BbContext
    local warned = {}
    local subscribers = {} ---@type table<string, function[]>

    function ctx.log(message)
        print("[" .. mod .. "] " .. message .. "\n")
    end

    function ctx.warnOnce(key, message)
        if warned[key] then return end
        warned[key] = true
        ctx.log("WARN " .. message)
    end

    -- Not named "debug": that would hide the Lua debug library.
    function ctx.trace(message)
        if ctx.config.verbose then ctx.log(message) end
    end

    -- The value of fn comes back, so a hook callback can replace the return value of its function.
    function ctx.guard(key, fn)
        return function(...)
            local ok, result = pcall(fn, ...)
            if not ok then
                ctx.warnOnce(key, key .. ": " .. tostring(result))
                return nil
            end
            return result
        end
    end

    local function noop() end

    function ctx.hook(key, path, fn, opts)
        local guarded = ctx.guard(key, fn)
        local ok, pre, post
        if opts and opts.post then
            ok, pre, post = pcall(RegisterHook, path, noop, guarded)
        elseif opts and opts.after then
            ok, pre, post = pcall(RegisterHook, path, guarded, ctx.guard(key .. " after", opts.after))
        else
            ok, pre, post = pcall(RegisterHook, path, guarded)
        end
        if not ok then
            if opts and opts.required then error(key .. " hook failed: " .. tostring(pre)) end
            ctx.warnOnce(key .. " hook", key .. " hook failed (a game change?): " .. tostring(pre))
            return false
        end
        ctx.hooks[path] = { pre, post }
        return true
    end

    function ctx.on(name, fn)
        subscribers[name] = subscribers[name] or {}
        table.insert(subscribers[name], ctx.guard("event " .. name, fn))
    end

    function ctx.emit(name, data)
        for _, fn in ipairs(subscribers[name] or {}) do
            fn(data)
        end
    end

    return ctx
end

return M
