--[[
    Pet action module -- everything that automates a controllable pet
    (Puppetmaster automaton / Summoner avatar / Beastmaster jug pet):

      * Maneuver upkeep (PUP only): keeps up to 3 configured elemental
        maneuvers applied to the player (the automaton reads them off the
        player, same as retail), stacking duplicates when the same element is
        picked in more than one slot.
      * Send pet at target (PUP Deploy / SMN Assault / BST Fight -- the feature has
        no name of its own; the UI labels it with whichever ability the job has):
        sends the pet at
        the player's current battle target whenever it doesn't already have a
        live target of its own (read off the pet entity's own TargetIndex).
        Opt-in (pet_deploy_enabled, off by default) and combat-only. Shared
        across all three jobs so none of them duplicate that check; each job
        supplies its own single-entry abilities.pet_deploy list
        (name/recast_id/command differ per job; everything else here is
        generic). execute_deploy() always reads job_def.abilities.pet_deploy[1]
        -- if a player mains and subs two different pet-control jobs at once,
        the main job's entry wins (e.g. BST/SMN with Carbuncle summoned would
        still try Fight, not Assault).

    Maneuver upkeep has no combat gate; send-pet-at-target does -- that's a real
    behavioral difference between the two, not an oversight.

    Both sit under the UI's "Pet Control" section and its `pet_enabled` master switch.

    Spec: docs/superpowers/specs/2026-08-08-pup-maneuver-deploy-design.md
    Spec: docs/superpowers/specs/2026-08-08-pet-deploy-smn-bst-design.md
]]--

local pet = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- ============================================================================
-- Maneuver upkeep helpers
-- ============================================================================

-- First entry in `desired` (in slot order) not yet matched by an existing buff
-- of the same id, counting duplicates -- so picking Fire Maneuver in two slots
-- correctly asks for a second stack once the first is already up. Returns nil
-- once every desired maneuver (at its requested multiplicity) is satisfied.
local function get_missing(desired, current_buffs)
    local satisfied = {}
    for _, ability in ipairs(desired) do
        local id = ability.buff_id
        local have = action_core.count_instances(current_buffs, id)
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

function pet.execute_maneuver(settings, job_def, main_level, sub_level, player_resource)
    -- pet_enabled is the UI's "Pet" section master switch, over both features here
    if not settings.pet_enabled or not settings.maneuver_enabled then
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
    -- means "keep two stacks up", which get_missing understands via count_instances.
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

-- ============================================================================
-- Automaton/avatar/pet Deploy
-- ============================================================================

-- True when the pet already has a live (HP% > 0) target of its own, read
-- straight off the pet entity's own TargetIndex -- the same field
-- common.lua's refresh_game_state reads to locate the pet's target for
-- position tracking, so no packet parsing is needed here.
local function pet_has_live_target(pet_entity)
    local idx = pet_entity.TargetIndex
    if not idx or idx == 0 then
        return false
    end
    local e = GetEntity(idx)
    return e ~= nil and (e.HPPercent or 0) > 0
end

function pet.execute_deploy(settings, job_def, main_level, sub_level, player_resource)
    if not settings.pet_enabled or not settings.pet_deploy_enabled then
        return nil
    end

    if not job_def or not job_def.abilities or not job_def.abilities.pet_deploy then
        return nil
    end

    local pet_entity = common.targets.get_pet()
    if not pet_entity then
        return nil
    end

    -- Deploy is combat-only by design -- unlike maneuver upkeep, which has no such gate.
    if not common.is_combat() then
        return nil
    end

    if pet_has_live_target(pet_entity) then
        return nil
    end

    local target = common.targets.get_t()
    if not target or (target.HPPercent or 0) <= 0 then
        return nil
    end

    -- Only send the pet at an actual mob -- same SpawnFlags 0x10 check
    -- common.is_combat() uses -- so a party member the player happened to have
    -- targeted can't be Deployed at.
    local is_mob = bit.band(target.SpawnFlags or 0, 0x10) ~= 0
    if not is_mob then
        return nil
    end

    local ability = job_def.abilities.pet_deploy[1]
    if not ability then
        return nil
    end

    return action_core.try_use(ability, job_def, settings, nil, ability.name)
end

return pet
