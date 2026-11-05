-- Validates the settings of config.lua against the schema. Game-free: no UE4SS global.
local M = {}

---@class BbConfigEntry
---@field key string
---@field default boolean|number|string the type of the default is the type of the setting
---@field min? number with max: a number outside min to max gives the default
---@field max? number
---@field keyName? boolean the value is a key: a letter A to Z or F1 to F12, the names that UE4SS and Unreal share
---@field comment string written above the key in a new config.lua

M.KEY_NAMES = "a letter A to Z or F1 to F12"

-- True for a key name that UE4SS (Key.V) and Unreal (the FKey "V") both know.
---@param value string
---@return boolean
function M.isKeyName(value)
    if value:match("^[A-Z]$") then return true end
    local n = tonumber(value:match("^F(%d%d?)$"))
    return n ~= nil and n >= 1 and n <= 12
end

-- Returns a table with one value for each schema key.
---@param raw table<string, any> the table that config.lua returns
---@param schema BbConfigEntry[]
---@param warn fun(key: string, message: string)
---@return table<string, any>
function M.validate(raw, schema, warn)
    local cfg = {}
    for _, entry in ipairs(schema) do
        local key, value = entry.key, raw[entry.key]
        if value == nil then
            cfg[key] = entry.default
        elseif type(value) ~= type(entry.default) then
            warn(
                key,
                "wrong type "
                    .. type(value)
                    .. ", expected "
                    .. type(entry.default)
                    .. "; using "
                    .. tostring(entry.default)
            )
            cfg[key] = entry.default
        elseif value ~= value or value == math.huge or value == -math.huge then
            warn(key, "not a finite number; using " .. tostring(entry.default))
            cfg[key] = entry.default
        elseif entry.min and (value < entry.min or value > entry.max) then
            warn(
                key,
                string.format(
                    "%s is outside %s to %s; using %s",
                    tostring(value),
                    tostring(entry.min),
                    tostring(entry.max),
                    tostring(entry.default)
                )
            )
            cfg[key] = entry.default
        elseif entry.keyName and not M.isKeyName(value) then
            warn(key, string.format("%q is not %s; using %q", value, M.KEY_NAMES, entry.default))
            cfg[key] = entry.default
        else
            cfg[key] = value
        end
    end
    return cfg
end

return M
