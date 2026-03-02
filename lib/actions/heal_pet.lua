--[[
    Pet healing action module
    Handles healing for player's geo pet
]]--

local heal_pet = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

function heal_pet.execute(settings, job_def)
    if not settings.heal_pet_enabled      then return nil end
    if not common.targets.get_pet()       then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end

    local abilities = common.filter_abilities_by_level(
        job_def.abilities.heal_pet or {}, settings,
        player.main_level, player.sub_level, job_def)
    if #abilities == 0 then return nil end

    local pet_hpp   = player.pet_hpp
    local threshold = settings.heal_pet_threshold or 50
    common.debugf('[HEAL_PET] Pet HP: %.1f%% (threshold: %.1f%%)', pet_hpp, threshold)
    if not common.below_threshold(pet_hpp, threshold) then return nil end

    return action_core.first_command(abilities, job_def, settings, '[HEAL_PET]', nil,
        function(a) return string.format('Healing pet with %s (Pet HP: %.1f%%)', a.name, pet_hpp) end)
end

return heal_pet
