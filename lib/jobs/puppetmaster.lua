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

        -- Elemental Maneuvers: buff the PLAYER (not the automaton -- same as retail,
        -- the automaton reads its gambit charges off the master's own status), so
        -- upkeep diffs against player.buffs, not pet buff tracking. All eight share
        -- one server-side recast (210) and are blocked while Overload (299) is up.
        -- No main_job_only: this server allows a subjob-PUP automaton, so maneuver
        -- upkeep works either way -- the real gate is an automaton actually being
        -- out (checked in pet.execute_maneuver via common.targets.get_pet()).
        -- short_name is the element alone, shown in the UI's three maneuver slot
        -- dropdowns; settings still store the full `name`.
        maneuver = {
            { name = 'Fire Maneuver', short_name = 'Fire', level = 1, cost = 0, recast_id = 210, buff_id = 300,
              blocked_by = 299, pet_required = true, command = '/pet "Fire Maneuver" <me>' },
            { name = 'Ice Maneuver', short_name = 'Ice', level = 1, cost = 0, recast_id = 210, buff_id = 301,
              blocked_by = 299, pet_required = true, command = '/pet "Ice Maneuver" <me>' },
            { name = 'Wind Maneuver', short_name = 'Wind', level = 1, cost = 0, recast_id = 210, buff_id = 302,
              blocked_by = 299, pet_required = true, command = '/pet "Wind Maneuver" <me>' },
            { name = 'Earth Maneuver', short_name = 'Earth', level = 1, cost = 0, recast_id = 210, buff_id = 303,
              blocked_by = 299, pet_required = true, command = '/pet "Earth Maneuver" <me>' },
            { name = 'Thunder Maneuver', short_name = 'Thunder', level = 1, cost = 0, recast_id = 210, buff_id = 304,
              blocked_by = 299, pet_required = true, command = '/pet "Thunder Maneuver" <me>' },
            { name = 'Water Maneuver', short_name = 'Water', level = 1, cost = 0, recast_id = 210, buff_id = 305,
              blocked_by = 299, pet_required = true, command = '/pet "Water Maneuver" <me>' },
            { name = 'Light Maneuver', short_name = 'Light', level = 1, cost = 0, recast_id = 210, buff_id = 306,
              blocked_by = 299, pet_required = true, command = '/pet "Light Maneuver" <me>' },
            { name = 'Dark Maneuver', short_name = 'Dark', level = 1, cost = 0, recast_id = 210, buff_id = 307,
              blocked_by = 299, pet_required = true, command = '/pet "Dark Maneuver" <me>' },
        },

        -- Send the automaton at the player's current target when it has none of
        -- its own. Opt-in (pet_deploy_enabled, off by default); the <t>/<bt>
        -- target and its gate come from pet_deploy_target, applied in
        -- pet.execute_deploy (lib/actions/pet.lua) -- the <t> here is the
        -- default, rewritten to <bt> there when that mode is picked. When both
        -- main and sub job supply a pet_deploy entry, execute always reads index
        -- [1], i.e. the main job's entry wins.
        pet_deploy = {
            { 
                name = 'Deploy', 
                level = 1, 
                cost = 0, 
                recast_id = 207,
                pet_required = true, 
                command = '/pet "Deploy" <t>' 
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_pet_enabled = true,
        heal_pet_threshold = 50,
        pet_debuff_removal_enabled = true,
        pet_enabled = true,          -- "Pet" section master switch (Maneuver + Deploy)
        maneuver_enabled = true,
        pet_deploy_enabled = false,
        pet_deploy_target = '<t>',   -- '<t>' (engaged only) or '<bt>'
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
        'pet_deploy',
        'maneuver',
    },
}
