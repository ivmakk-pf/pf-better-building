-- The one source of the config keys, defaults, and comments.
-- Its own file, so the tests can read it without the UE4SS globals of main.lua.
---@type BbConfigEntry[]
return {
    {
        key = "allow_collision",
        default = true,
        comment = "Build where a construction overlaps tree stumps, rocks, props, or ruins of the map. What you built, a player, or an animal still blocks it.",
    },
    {
        key = "allow_no_build_zones",
        default = true,
        comment = 'Build in a no-build zone (no "NO-BUILD ZONE"). A status effect that blocks building still blocks it.',
    },
    {
        key = "allow_move",
        default = true,
        comment = "Move a placed construction that does not snap to the build grid: Move mode with move_key and the Building Tool in build mode, the blue highlight, and the hint line.",
    },
    {
        key = "move_key",
        default = "V",
        keyName = true,
        comment = "Key that turns Move mode on and off in build mode. Pick a key that the game does not use.",
    },
    {
        key = "verbose",
        default = false,
        comment = "Extra lines in UE4SS.log, for a bug report. Keep off in normal play.",
    },
}
