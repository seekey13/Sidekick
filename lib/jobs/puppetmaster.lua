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
                id = 206,
                command = '/ja "Repair" <me>',
                pet_required = true,
                requires_equipped_ammo = OILS,  -- gate + auto-equip tiers
                ammo_main_job_only = true,      -- only PUP main can equip oils
                ammo_label = 'Oils',            -- UI count label
            },
        },

        -- Strip the automaton's status ailments. Same Oil ammo as Repair, so no
        -- ammo contention. Dormant until pet debuffs are tracked.
        pet_debuff_removal = {
            {
                name = 'Maintenance',
                level = 30,
                cost = 0,
                id = 214,
                command = '/ja "Maintenance" <me>',
                debuff_id = common.ERASABLE_DEBUFFS,
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

    -- Action priority order
    priority_order = {
        'heal_pet',
        'pet_debuff_removal',
    },
}
