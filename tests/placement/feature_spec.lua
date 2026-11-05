local fakes = require("fakes")
local paths = require("bb.paths")

local COLLISION = paths.BPC .. ":CollisionCheck"
local ZONE = paths.BPC .. ":CheckForExclusionZone"

describe("placement feature", function()
    local env, ctx, overlaps, boxCalls, hits, compCalls
    local now = 0
    local bpc = { BuildPartCollisionObjectType = 7 }

    -- Installs the feature with these switches and registers its hooks (the class is in memory).
    local function install(config)
        env = fakes.install()
        for _, name in ipairs({ "bb.hooks", "bb.placement.feature" }) do
            package.loaded[name] = nil
        end
        overlaps, boxCalls, hits, compCalls = {}, 0, {}, {}
        env.objects[paths.BPC] = fakes.object({ class = "Class", name = "BP_PlayerBuildingComponent_C" })
        env.objects[paths.CHARACTER] = fakes.object({ class = "Class", name = "Character" })
        env.objects[paths.BUILD_PART] = fakes.object({ class = "Class", name = "BuildPartBase" })
        env.objects[paths.KSL] = fakes.object({
            class = "KismetSystemLibrary",
            -- The game's own overlap of one collision box: hits are the overlapped components.
            ComponentOverlapComponents = function(_, box, transform, types, cls, ignore, out)
                compCalls[#compCalls + 1] =
                    { box = box, transform = transform, types = types, cls = cls, ignore = ignore }
                for i, c in ipairs(hits) do
                    out[i] = c
                end
                return #hits > 0
            end,
            BoxOverlapActors = function(_, _, origin, extent, types, cls, ignore, out)
                boxCalls = boxCalls + 1
                assert(origin.X == 1 and extent.X == 50, "the box is the bounds of the part")
                assert(cls.name == "Character" and #types > 0 and ignore[1] ~= nil, "a Character overlap")
                for i, a in ipairs(overlaps) do
                    out[i] = a
                end
                return #overlaps > 0
            end,
        })
        now = 0
        ctx = require("bb.core.context").new("T", function()
            return now
        end)
        ctx.config = config
        ctx.bp = require("bb.hooks").new(ctx)
        require("bb.placement.feature").install(ctx)
        ctx.bp.start()
    end

    -- The collision box of each part (BuildCollisions, a TArray property).
    local box = fakes.object({
        class = "BoxComponent",
        K2_GetComponentToWorld = function()
            return "transform"
        end,
    })

    local function part()
        return fakes.object({
            class = "BP_WoodenFoundation_C",
            location = { X = 0, Y = 0, Z = 0 },
            rotation = { Pitch = 0, Yaw = 0, Roll = 0 },
            K2_GetActorLocation = function(self)
                return { X = self.location.X, Y = self.location.Y, Z = self.location.Z }
            end,
            K2_GetActorRotation = function(self)
                return { Pitch = self.rotation.Pitch, Yaw = self.rotation.Yaw, Roll = self.rotation.Roll }
            end,
            BuildCollisions = {
                ForEach = function(_, fn)
                    fn(1, fakes.param(box))
                end,
            },
            GetActorBounds = function(_, _, origin, extent)
                origin.X, origin.Y, origin.Z = 1, 2, 3
                extent.X, extent.Y, extent.Z = 50, 50, 10
            end,
        })
    end

    -- A component of an actor of this class, with these properties.
    local function hit(class, props)
        props = props or {}
        props.class = class
        local owner = fakes.object(props)
        return fakes.object({
            class = "StaticMeshComponent",
            GetOwner = function()
                return owner
            end,
        })
    end

    local function own(props)
        local p = { isa = { "BuildPartBase" }, bBuiltByPlayer = true, bIsPreview = false }
        for k, v in pairs(props or {}) do
            p[k] = v
        end
        return hit("BP_WoodenWall_C", p)
    end

    -- One CollisionCheck result for the construction p (a new one when nil).
    local function collision(blocked, hide, ground, p)
        local b = fakes.param(blocked)
        env.hooks[COLLISION](fakes.param(bpc), fakes.param(p or part()), b, fakes.param(hide), fakes.param(ground))
        return b.value
    end

    local function lines(pattern)
        local found = {}
        for _, line in ipairs(env.printed) do
            if line:find(pattern) then found[#found + 1] = line end
        end
        return found
    end

    after_each(function()
        fakes.restore()
    end)

    local ON = { allow_collision = true, allow_no_build_zones = true, verbose = true }

    describe("collision", function()
        it("clears a block with ground, no stack, and no character", function()
            install(ON)
            assert.is_false(collision(true, false, false))
            assert.are.equal(1, boxCalls)
            assert.are.equal(1, #lines("collision cleared for BP_WoodenFoundation_C"))
        end)

        it("keeps the block when a collision box overlaps a construction that a player built", function()
            install(ON)
            local p = part()
            hits = { hit("BP_Rock_C"), own() }
            assert.is_true(collision(true, false, false, p))
            assert.are.equal(1, #compCalls)
            local call = compCalls[1]
            assert.are.equal(box, call.box)
            assert.are.equal("transform", call.transform)
            assert.are.same({ 0, 1, 2, 3, 5, 6, 7 }, call.types)
            assert.is_nil(call.cls)
            assert.are.equal(p, call.ignore[1])
            assert.are.equal(0, #lines("collision cleared"))
            assert.are.equal(1, #lines("collision kept for BP_WoodenFoundation_C: own construction"))
        end)

        it("reads wrapped elements of the overlap result too", function()
            install(ON)
            hits = { fakes.param(own()) }
            assert.is_true(collision(true, false, false))
        end)

        it("clears the block for a world object, a ruin, or a preview", function()
            for _, h in ipairs({ hit("BP_Rock_C"), own({ bBuiltByPlayer = false }), own({ bIsPreview = true }) }) do
                install(ON)
                hits = { h }
                assert.is_false(collision(true, false, false))
            end
        end)

        it("keeps the own construction result of one part for 0.1 s", function()
            install(ON)
            local p = part()
            hits = { own() }
            collision(true, false, false, p)
            now = 0.05
            hits = {}
            assert.is_true(collision(true, false, false, p))
            assert.are.equal(1, #compCalls)
            now = 0.2
            assert.is_false(collision(true, false, false, p))
            assert.are.equal(2, #compCalls)
        end)

        it("runs the overlaps again when the preview moved or turned within 0.1 s", function()
            install(ON)
            local p = part()
            collision(true, false, false, p)
            hits = { own() }
            now = 0.02
            p.location.X = 200
            assert.is_true(collision(true, false, false, p))
            assert.are.equal(2, #compCalls)
            hits = {}
            now = 0.04
            p.rotation.Yaw = 90
            assert.is_false(collision(true, false, false, p))
            assert.are.equal(3, #compCalls)
            assert.are.equal(3, boxCalls)
        end)

        it("runs no overlap for a result that is not blocked", function()
            install(ON)
            assert.is_false(collision(false, false, false))
            assert.are.equal(0, boxCalls)
        end)

        it("keeps the block when a character overlaps", function()
            install(ON)
            overlaps = { fakes.object({ class = "BP_Deer_C" }) }
            assert.is_true(collision(true, false, false))
        end)

        it("keeps the block for a ground failure or an exact-place stack, with no overlap", function()
            install(ON)
            assert.is_true(collision(true, false, true))
            assert.is_true(collision(true, true, false))
            assert.are.equal(0, boxCalls)
        end)

        it("keeps the overlap result of one construction for 0.1 s", function()
            install(ON)
            local p = part()
            collision(true, false, false, p)
            now = 0.05
            overlaps = { fakes.object({ class = "BP_Deer_C" }) }
            assert.is_false(collision(true, false, false, p))
            assert.are.equal(1, boxCalls)
            now = 0.2
            assert.is_true(collision(true, false, false, p))
            assert.are.equal(2, boxCalls)
            assert.is_true(collision(true, false, false))
            assert.are.equal(3, boxCalls)
        end)

        it("logs one line for each kind of write, also when the two kinds alternate", function()
            install(ON)
            local p = part()
            for _ = 1, 2 do
                collision(true, false, false, p)
                env.hooks[ZONE](fakes.param("bpc"), fakes.param(p), fakes.param(false))
            end
            assert.are.equal(1, #lines("collision cleared"))
            assert.are.equal(1, #lines("no%-build zone cleared"))
        end)

        it("logs a repeated write once", function()
            install(ON)
            collision(true, false, false)
            collision(true, false, false)
            assert.are.equal(1, #lines("collision cleared"))
        end)

        it("gives one warning and writes nothing when the overlap throws", function()
            install(ON)
            env.objects[paths.KSL].BoxOverlapActors = function()
                error("no box")
            end
            assert.is_true(collision(true, false, false))
            assert.is_true(collision(true, false, false))
            assert.are.equal(1, #lines("WARN .*no box"))
        end)

        it("registers no collision hook with its switch off", function()
            install({ allow_collision = false, allow_no_build_zones = true, verbose = false })
            assert.is_nil(env.hooks[COLLISION])
            assert.is_function(env.hooks[ZONE])
        end)
    end)

    describe("no-build zone", function()
        it("writes bCanBuildHere = true when it was false", function()
            install(ON)
            local can = fakes.param(false)
            env.hooks[ZONE](fakes.param("bpc"), fakes.param(part()), can)
            assert.is_true(can.value)
            assert.are.equal(1, #lines("no%-build zone cleared for BP_WoodenFoundation_C"))
        end)

        it("writes nothing when it was true", function()
            install(ON)
            local can = fakes.param(true)
            local writes = 0
            can.set = function()
                writes = writes + 1
            end
            env.hooks[ZONE](fakes.param("bpc"), fakes.param(part()), can)
            assert.are.equal(0, writes)
        end)

        it("registers no zone hook with its switch off", function()
            install({ allow_collision = true, allow_no_build_zones = false, verbose = false })
            assert.is_nil(env.hooks[ZONE])
            assert.is_function(env.hooks[COLLISION])
        end)
    end)
end)
