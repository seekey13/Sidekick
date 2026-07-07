--[[
    Puppetmaster job definition
    Support automation for Puppetmaster is pet-only:
    - Pet (automaton) healing via Repair

    Repair only works when an Automaton Oil is equipped in the ammo slot, so the
    ability is gated on that (requires_equipped_ammo). Higher tiers heal more:
      18731 Automaton Oil, 18732 Automaton Oil +1, 18733 Automaton Oil +2.
    Auto-equipping the oil when it's only in inventory/wardrobe is a later
    feature; for now the player must equip it themselves (the UI shows the count
    of oils detected across inventory + wardrobes).
]]--

-- Automaton Oil item ids (ammo slot), all tiers.
local OIL_ITEM_IDS = { 18731, 18732, 18733 }


return {
    job_id = 18,  -- Puppetmaster
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
                requires_equipped_ammo = OIL_ITEM_IDS,  -- needs an oil equipped
                ammo_label = 'Oils',                    -- UI count label
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
