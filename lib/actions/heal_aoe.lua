--[[
    AOE healing action module
    Handles party-wide or area-based healing
]]--

local heal_aoe = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

function heal_aoe.execute(settings, job_def)
    if not settings.heal_aoe_enabled then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    local abilities = common.filter_abilities_by_level(
        job_def.abilities.heal_aoe or {}, settings,
        player.main_level, player.sub_level, job_def)
    if #abilities == 0 then return nil end

    -- Average HP of alive, non-full party members
    local in_pl_mode   = settings.pl_mode_enabled and settings.pl_connected_player
    local total, count = 0, 0
    for i = 0, 5 do
        local m = i == 0 and state.player or state.party[i]
        if m and not (in_pl_mode and common.is_trust(i)) then
            local hpp = m.hpp or 0
            if common.is_active_member(hpp) then
                total = total + hpp
                count = count + 1
            end
        end
    end
    local avg_hp    = count > 0 and (total / count) or 100
    local threshold = settings.heal_aoe_threshold or 70
    common.debugf('[HEAL_AOE] Avg HP: %.1f%% (threshold: %.1f%%)', avg_hp, threshold)
    if not common.below_threshold(avg_hp, threshold) then return nil end

    return action_core.first_command(abilities, job_def, settings, '[HEAL_AOE]', nil,
        function(a) return string.format('AOE healing with %s (avg HP: %.1f%%)', a.name, avg_hp) end)
end

return heal_aoe
