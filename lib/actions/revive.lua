--[[
    Revive action module
    Raises dead party/tracked/alliance members (entity_status == 3).
    Abilities that have idle_only = true are automatically excluded when
    the player is in combat, satisfying the "out-of-combat only" requirement.
]]--

local revive = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Returns true if the target already has a pending raise.
-- A pending raise is detected via the 0x029 packet handler in Medic.lua:
-- when the server rejects a raise cast on a dead target, the packet param
-- is the rejected spell ID — which we record as a pending raise flag.
local function is_raise_pending(server_id)
    return common.has_pending_raise(server_id)
end

-- Returns true if the player has every buff required by this ability.
-- Mirrors the same helper used in recover.lua (e.g. Scholar needs Addendum: White).
local function has_required_buff(ability, buffs)
    if not ability.requires_buff then return true end
    local ids = type(ability.requires_buff) == 'table'
                and ability.requires_buff or {ability.requires_buff}
    for _, req in ipairs(ids) do
        for _, active in ipairs(buffs) do
            if active == req then return true end
        end
    end
    return false
end

function revive.execute(settings, job_def, main_level, sub_level, player_resource)
    if not settings.revive_enabled then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    local revive_abilities = job_def.abilities and job_def.abilities.revive
    if not revive_abilities or #revive_abilities == 0 then return nil end

    local derived_main_level = player.main_level or main_level
    local derived_sub_level  = player.sub_level  or sub_level

    local available = common.filter_abilities_by_level(
        revive_abilities,
        settings,
        derived_main_level,
        derived_sub_level,
        job_def
    )
    if #available == 0 then return nil end

    local usable = action_core.filter_usable(available, job_def, settings)
    if #usable == 0 then return nil end

    -- Remove any abilities whose required buff (e.g. Addendum: White for Scholar) is not active.
    local buff_usable = {}
    for _, a in ipairs(usable) do
        if has_required_buff(a, player.buffs or {}) then
            table.insert(buff_usable, a)
        end
    end
    if #buff_usable == 0 then return nil end

    -- Try all buff_usable abilities on a target addressed by party index.
    -- Checks range first; tries the next ability if command build fails.
    local function try_party_index(m, i)
        if not (m and m.is_active and m.entity_status == 3
            and m.target_index and m.target_index > 0) then return nil end
        if is_raise_pending(m.server_id) then
            common.debugf('[REVIVE] Party[%d] %s already has a pending raise, skipping', i, m.name or '?')
            return nil
        end
        for _, ability in ipairs(buff_usable) do
            if common.is_in_range(m.target_index, ability.range or 20) then
                -- Check stratagems before casting (e.g. Scholar Penury to halve Raise MP)
                local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                if strat_result == false then
                    common.debugf('[REVIVE] Stratagem unavailable for %s on party[%d], trying next ability', ability.name, i)
                    goto continue_party_ability
                elseif strat_result then
                    common.debugf('[REVIVE] Firing stratagem before raising party[%d] %s with %s',
                        i, m.name or '?', ability.name)
                    return strat_result
                end

                local command = common.build_ability_command(ability, i)
                if command then
                    common.debugf('[REVIVE] Party[%d] %s is dead, raising with %s',
                        i, m.name or '?', ability.name)
                    return {
                        command     = command,
                        description = string.format('Raising %s with %s',
                            m.name or 'party member', ability.name),
                    }
                end
                common.debugf('[REVIVE] build_ability_command returned nil for party[%d] with %s', i, ability.name)
            else
                common.debugf('[REVIVE] Party[%d] %s out of range for %s', i, m.name or '?', ability.name)
            end
            ::continue_party_ability::
        end
        return nil
    end

    -- Try all buff_usable abilities on a target addressed by server ID.
    local function try_server_id(m, sid, tag)
        if not (m and m.is_active and m.entity_status == 3
            and m.target_index and m.target_index > 0) then return nil end
        if is_raise_pending(sid) then
            common.debugf('[REVIVE] %s %s already has a pending raise, skipping', tag, m.name or '?')
            return nil
        end
        for _, ability in ipairs(buff_usable) do
            if common.is_in_range(m.target_index, ability.range or 20) then
                -- Check stratagems before casting (e.g. Scholar Penury to halve Raise MP)
                local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                if strat_result == false then
                    common.debugf('[REVIVE] Stratagem unavailable for %s on %s %s, trying next ability',
                        ability.name, tag, m.name or '?')
                    goto continue_sid_ability
                elseif strat_result then
                    common.debugf('[REVIVE] Firing stratagem before raising %s %s with %s',
                        tag, m.name or '?', ability.name)
                    return strat_result
                end

                local command = common.build_ability_command_for_target(ability, sid)
                if command then
                    common.debugf('[REVIVE] %s %s is dead, raising with %s',
                        tag, m.name or '?', ability.name)
                    return {
                        command     = command,
                        description = string.format('Raising %s %s with %s',
                            tag, m.name or '?', ability.name),
                    }
                end
                common.debugf('[REVIVE] build_ability_command_for_target returned nil for %s %s with %s',
                    tag, m.name or '?', ability.name)
            else
                common.debugf('[REVIVE] %s %s out of range for %s', tag, m.name or '?', ability.name)
            end
            ::continue_sid_ability::
        end
        return nil
    end

    -- Scan party members (indices 1-5).
    -- Index 0 is the player, stored as state.player and not scanned for revival.
    for i = 1, 5 do
        local result = try_party_index(state.party[i], i)
        if result then return result end
    end

    -- Scan tracked targets.
    if state.tracked then
        for sid, tt in pairs(state.tracked) do
            local result = try_server_id(tt, sid, 'tracked')
            if result then return result end
        end
    end

    -- Scan alliance members (sub-parties 2 and 3).
    if state.alliance then
        for al_pi = 2, 3 do
            local sub_party = state.alliance[al_pi]
            if sub_party then
                for _, m in pairs(sub_party) do
                    local result = try_server_id(m, m and m.server_id, 'alliance')
                    if result then return result end
                end
            end
        end
    end

    return nil
end

return revive
