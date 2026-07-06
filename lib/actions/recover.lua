--[[
    Resource recovery action module
    Handles MP and TP recovery abilities
]]--

local recover = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- Filter an ability list by requires_buff prerequisite.
local function filter_buff_prereqs(abilities, buffs)
    local out = {}
    for _, a in ipairs(abilities) do
        if not a.requires_buff or action_core.has_any_buff(buffs, a.requires_buff) then
            table.insert(out, a)
        end
    end
    return out
end

-- Filter out any ability that has a min_tp field if the player's current TP is below the threshold.
-- The threshold is taken from the matching setting key (chivalry_min_tp) when available,
-- falling back to the ability's own min_tp default.
local function filter_tp_prereqs(abilities, player_tp, settings)
    local out = {}
    for _, a in ipairs(abilities) do
        if a.min_tp then
            local min_tp = settings.chivalry_min_tp or a.min_tp
            if (player_tp or 0) >= min_tp then
                table.insert(out, a)
            end
        else
            table.insert(out, a)
        end
    end
    return out
end

function recover.execute(settings, job_def)
    if not settings.recover_enabled then return nil end

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
            filter_tp_prereqs(
                filter_buff_prereqs(filter('recover_mp'), player.buffs),
                player.tp, settings),
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
