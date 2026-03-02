--[[
    Resource recovery action module
    Handles MP and TP recovery abilities
]]--

local recover = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Returns true if the player holds any of the ability's required buffs (or none are required).
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

-- Filter an ability list by requires_buff prerequisite.
local function filter_buff_prereqs(abilities, buffs)
    local out = {}
    for _, a in ipairs(abilities) do
        if has_required_buff(a, buffs) then table.insert(out, a) end
    end
    return out
end

function recover.execute(settings, job_def)
    if not settings.recover_enabled then return nil end
    if settings.pl_mode_enabled and settings.pl_connected_player then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    local function filter(key)
        return common.filter_abilities_by_level(
            job_def.abilities[key] or {}, settings,
            player.main_level, player.sub_level, job_def)
    end

    -- Priority 1: Devotion on focus recovery target
    if settings.focus_recovery_target then
        local tidx = nil
        for i = 1, 5 do
            local m = state.party[i]
            if m and m.name == settings.focus_recovery_target then tidx = i; break end
        end
        if tidx then
            local tm        = state.party[tidx]
            local threshold = settings.focus_recovery_threshold or 30
            if common.below_threshold(tm.mpp or 0, threshold) then
                for _, ability in ipairs(filter('recover_party_mp')) do
                    if ability.name == 'Devotion' then
                        local ok, reason    = action_core.is_usable(ability, job_def)
                        local entity_index  = tm.target_index
                        local in_range      = entity_index and common.is_in_range(entity_index, 20)
                        if ok and in_range then
                            local cmd = common.build_ability_command(ability, tidx)
                            if cmd then
                                return { command = cmd,
                                    description = string.format('Devotion on %s (MP: %.1f%%)',
                                        settings.focus_recovery_target, tm.mpp) }
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    -- Priority 2: Self MP recovery
    local mp_threshold = settings.recover_mp_threshold
    if mp_threshold and common.below_threshold(player.mpp or 0, mp_threshold) then
        local result = action_core.first_command(
            filter_buff_prereqs(filter('recover_mp'), player.buffs),
            job_def, settings, '[RECOVER]', nil,
            function(a) return string.format('MP recovery with %s (MP: %.1f%%)', a.name, player.mpp) end)
        if result then return result end
    end

    -- Priority 3: Self TP recovery
    local tp_threshold = settings.recover_tp_threshold
    if tp_threshold and common.below_threshold(player.tp or 0, tp_threshold) then
        return action_core.first_command(
            filter_buff_prereqs(filter('recover_tp'), player.buffs),
            job_def, settings, '[RECOVER]', nil,
            function(a) return string.format('TP recovery with %s (TP: %d)', a.name, player.tp) end)
    end

    return nil
end

return recover
