--[[
    Puppetmaster job definition
    Support automation for Puppetmaster is pet-only:
    - Pet (automaton) healing via Repair

    Repair only works when an Automaton Oil is equipped in the ammo slot, so the
    ability is gated on that (requires_equipped_ammo). If an oil is owned
    (inventory or any wardrobe) but not worn, Sidekick auto-equips the best tier
    before healing; higher tiers heal more. Oils have no equip level requirement
    (level 1) but can only be equipped with PUP as MAIN job (ammo_main_job_only),
    so auto-equip is skipped when PUP is only the subjob. The UI shows the total
    count detected.
]]--

local common = require('lib.core.common')

-- Automaton Oil ammo tiers: id, item name (for /equip), equip level.
local OILS = {
    { id = 18731, name = 'Automaton Oil',    level = 15 },
    { id = 18732, name = 'Automat. Oil +1', level = 30 },
    { id = 18733, name = 'Automat. Oil +2', level = 50 },
}

return {
    job_id = 18,
    job_name = 'Puppetmaster',
    resource_type = 'tp',  -- melee/pet job; Repair itself costs nothing

    abilities = {
        -- Pet (automaton) healing
        heal_pet = {
            {
                name = 'Repair',
                level = 15,
                cost = 0,
                priority = 100,                 -- prefer Repair; fall to Role Reversal only when it's on cooldown
                recast_id = 206,
                command = '/ja "Repair" <me>',
                pet_required = true,
                requires_equipped_ammo = OILS,  -- gate + auto-equip tiers
                ammo_main_job_only = true,      -- only PUP main can equip oils
                ammo_label = 'Oils',            -- UI count label
            },
            {
                name = 'Role Reversal',
                level = 75,
                cost = 0,
                recast_id = 211,
                command = '/ja "Role Reversal" <me>',
                pet_required = true,
                ability_id = 179,  -- merit-unlocked: gated on HasAbility (180 is Ventriloquy)
            },
        },

        -- Strip the automaton's status ailments. Same Oil ammo as Repair, so no
        -- ammo contention. Dormant until pet debuffs are tracked.
        pet_debuff_removal = {
            {
                name = 'Maintenance',
                level = 30,
                cost = 0,
                recast_id = 214,
                command = '/ja "Maintenance" <me>',
                debuff_id = common.PET_CLEANSE_DEBUFFS,  -- not Erase's list; see common.lua
                pet_required = true,
                requires_equipped_ammo = OILS,  -- gate + auto-equip tiers
                ammo_main_job_only = true,      -- only PUP main can equip oils
                ammo_label = 'Oils',            -- UI count label
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_pet_enabled = true,
        heal_pet_threshold = 50,
        pet_debuff_removal_enabled = true,
    },

    -- Role Reversal swaps master/pet HP *percentages*, so heal_pet's pet-HP-only
    -- gate is not enough on its own: firing it blind either drops the player to a
    -- critical HP% or, when the player is the hurt one, makes the pet worse.
    -- Only allow it when the player is healthier than the pet and the post-swap
    -- player HP% stays above the floor below.
    -- ponytail: fixed 25% floor, not a setting -- validate_ability gets no
    -- settings arg. Promote to role_reversal_min_hpp if the fixed value chafes.
    validate_ability = function(ability, common)
        if ability.name ~= 'Role Reversal' then return true end

        local player = common.game_state and common.game_state.player
        if not player then return false end

        local pet_hpp = player.pet_hpp or 0
        return pet_hpp >= 25 and (player.hpp or 0) > pet_hpp
    end,

    -- Action priority order
    priority_order = {
        'item',
        'heal_pet',
        'pet_debuff_removal',
    },
}
