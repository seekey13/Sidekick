--[[
    Beastmaster job definition
    Support automation for Beastmaster is pet-only:
    - Pet healing via Reward

    Reward only works when a Pet Food (biscuit) is equipped in the ammo slot, so
    the ability is gated on that (requires_equipped_ammo). Biscuit tier scales
    with level (any tier satisfies the check):
      17016 Alpha (12), 17017 Beta (24), 17018 Gamma (36),
      17019 Delta (48), 17020 Epsilon (60), 17021 Zeta (72).
    Auto-equipping the biscuit when it's only in inventory/wardrobe is a later
    feature; for now the player must equip it themselves (the UI shows the count
    of biscuits detected across inventory + wardrobes).
]]--

-- Pet Food (biscuit) item ids (ammo slot), all tiers.
local BISCUIT_ITEM_IDS = { 17016, 17017, 17018, 17019, 17020, 17021 }


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
                requires_equipped_ammo = BISCUIT_ITEM_IDS,  -- needs a biscuit equipped
                ammo_label = 'Biscuits',                     -- UI count label
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
