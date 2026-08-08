--[[
    Maneuver action module (Puppetmaster)

    Maneuver maintenance: keeps up to 3 configured elemental maneuvers applied to the
    player (the automaton reads them off the player, same as retail), stacking
    duplicates when the same element is picked in more than one slot. Works whether
    PUP is main or sub job -- the real gate is an automaton actually being out
    (common.targets.get_pet()), same convention as every other pet-required ability.

    Automaton Deploy now lives in pet_deploy.lua, shared with SMN (Assault) and
    BST (Fight) -- see that module for the send-pet-at-target behavior.

    Spec: docs/superpowers/specs/2026-08-08-pup-maneuver-deploy-design.md
]]--

local maneuver = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- ============================================================================
-- Maneuver upkeep helpers
-- ============================================================================

-- Occurrences of buff_id in a flat buffs array -- player.buffs carries the same
-- id more than once when a maneuver is stacked.
local function count_buff(buff_id, buffs)
    local count = 0
    for _, b in ipairs(buffs or {}) do
        if b == buff_id then
            count = count + 1
        end
    end
    return count
end

-- First entry in `desired` (in slot order) not yet matched by an existing buff
-- of the same id, counting duplicates -- so picking Fire Maneuver in two slots
-- correctly asks for a second stack once the first is already up. Returns nil
-- once every desired maneuver (at its requested multiplicity) is satisfied.
local function get_missing(desired, current_buffs)
    local satisfied = {}
    for _, ability in ipairs(desired) do
        local id = ability.buff_id
        local have = count_buff(id, current_buffs)
        satisfied[id] = satisfied[id] or 0
        if satisfied[id] < have then
            satisfied[id] = satisfied[id] + 1
        else
            return ability
        end
    end
    return nil
end

-- ============================================================================
-- Maneuver upkeep
-- ============================================================================

function maneuver.execute(settings, job_def, main_level, sub_level, player_resource)
    if not settings.maneuver_enabled then
        return nil
    end

    -- Do not apply maneuvers while resting
    if common.is_resting() then
        return nil
    end

    if not job_def or not job_def.abilities or not job_def.abilities.maneuver then
        return nil
    end

    if not common.targets.get_pet() then
        return nil
    end

    local player_buffs = common.game_state.player.buffs or {}

    -- Level/disabled filter, then drop anything Overload (299) is blocking --
    -- try_use does not check blocked_by on its own, so every caller with a
    -- blocked_by ability filters it explicitly first (same as
    -- heal.lua/status_removal.lua).
    local available = common.filter_abilities_by_level(job_def.abilities.maneuver, settings, main_level, sub_level, job_def)
    available = action_core.filter_self_buff_blocked(available, player_buffs)
    if #available == 0 then
        return nil
    end

    local function find_maneuver(name)
        if not name then return nil end
        for _, ability in ipairs(available) do
            if ability.name == name then
                return ability
            end
        end
        return nil
    end

    -- Desired list in slot order. Not deduped -- the same element picked twice
    -- means "keep two stacks up", which get_missing understands via count_buff.
    local desired = {}
    for _, key in ipairs({ 'maneuver1_name', 'maneuver2_name', 'maneuver3_name' }) do
        local ability = find_maneuver(settings[key])
        if ability then
            table.insert(desired, ability)
        end
    end
    if #desired == 0 then
        return nil
    end

    local missing = get_missing(desired, player_buffs)
    if not missing then
        return nil
    end

    -- One attempt per tick, not a burst -- try_use covers the recast-210 shared
    -- cooldown and the movement block. It does NOT cover Amnesia here: maneuvers
    -- cast via /pet, and common.is_command_blocked only checks Amnesia for /ja
    -- (and Silence for /ma) -- /pet is neither, so an Amnesia'd automaton would
    -- still be attempted (and presumably rejected server-side).
    return action_core.try_use(missing, job_def, settings, nil, 'Maneuver: ' .. missing.name)
end

return maneuver
