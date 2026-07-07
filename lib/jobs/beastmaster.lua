--[[
    Beastmaster job definition
    Support automation for Beastmaster is pet-only:
    - Pet healing via Reward

    Reward only works when a Pet Food (biscuit) is equipped in the ammo slot, so
    the ability is gated on that (requires_equipped_ammo). If a biscuit is owned
    (inventory or any wardrobe) but not worn, Medic auto-equips the best tier the
    player's level allows before healing. Levels below are the biscuit's equip
    requirement. The UI shows the total count detected.
]]--

-- Pet Food (biscuit) ammo tiers: id, item name (for /equip), equip level.
local PET_FOOD = {
    { id = 17016, name = 'Pet Food Alpha Biscuit',   level = 12 },
    { id = 17017, name = 'Pet Food Beta Biscuit',    level = 24 },
    { id = 17018, name = 'Pet Food Gamma Biscuit',   level = 36 },
    { id = 17019, name = 'Pet Food Delta Biscuit',   level = 48 },
    { id = 17020, name = 'Pet Food Epsilon Biscuit', level = 60 },
    { id = 17021, name = 'Pet Food Zeta Biscuit',    level = 72 },
}


return {
    job_id = 9,  -- Beastmaster
    job_name = 'Beastmaster',
    resource_type = 'tp',  -- melee/pet job; Reward itself costs nothing

    abilities = {
        -- Pet healing
        heal_pet = {
            {
                name = 'Reward',
                level = 12,
                cost = 0,
                id = 103,
                command = '/ja "Reward" <me>',
                pet_required = true,
                requires_equipped_ammo = PET_FOOD,  -- gate + auto-equip tiers
                ammo_label = 'Biscuits',            -- UI count label
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_pet_enabled = true,
        heal_pet_threshold = 50,
    },

    -- Action priority order
    priority_order = {
        'heal_pet',
    },
}
