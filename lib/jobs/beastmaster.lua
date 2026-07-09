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

local common = require('lib.core.common')

-- Pet Food (biscuit) ammo tiers: id, item name (for /equip), equip level.
local PET_FOOD = {
    { id = 17016, name = 'Pet Food Alpha Biscuit',   level = 12 },
    { id = 17017, name = 'Pet Food Beta Biscuit',    level = 24 },
    { id = 17018, name = 'Pet Food Gamma Biscuit',   level = 36 },
    { id = 17019, name = 'Pet Food Delta Biscuit',   level = 48 },
    { id = 17020, name = 'Pet Food Epsilon Biscuit', level = 60 },
    { id = 17021, name = 'Pet Food Zeta Biscuit',    level = 72 },
}

-- Pet Poultice: with this in the ammo slot Reward grants the pet Regen instead
-- of the flat heal biscuits give. Single item, so a one-entry tier list.
local PET_POULTICE = {
    { id = 19252, name = 'Pet Poultice', level = 1 },
}

-- Pet Roborant: with this equipped Reward erases the pet's status ailments
-- instead of healing. Single item, so a one-entry tier list.
local PET_ROBORANT = {
    { id = 19251, name = 'Pet Roborant', level = 1 },
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

        -- Same Reward JA, but with a Pet Poultice equipped it grants the pet
        -- Regen instead of a heal. Shares Reward's recast (id 103) and, since only
        -- one ammo can be worn, never fires the same tick as the heal_pet Reward.
        buff = {
            {
                name = 'Reward (Regen)',
                level = 12,
                cost = 0,
                id = 103,
                command = '/ja "Reward" <me>',
                pet_required = true,
                requires_equipped_ammo = PET_POULTICE,  -- gate + auto-equip
                ammo_label = 'Pet Poultice',            -- UI count label
                -- Pet buffs aren't tracked, so we can't see the pet's Regen. It
                -- lasts 5 min, so reapply on that interval instead of every
                -- recast (avoids wasting poultices).
                reapply_interval = 300,
            },
        },

        -- Same Reward JA again, but with a Pet Roborant equipped it erases the
        -- pet's status ailments. Dormant until pet debuffs are tracked.
        pet_debuff_removal = {
            {
                name = 'Reward (Erase)',
                level = 12,
                cost = 0,
                id = 103,
                command = '/ja "Reward" <me>',
                debuff_id = common.ERASABLE_DEBUFFS,
                pet_required = true,
                requires_equipped_ammo = PET_ROBORANT,  -- gate + auto-equip
                ammo_label = 'Pet Roborant',            -- UI count label
            },
        },

        -- AoE party heal from a rabbit jug pet's Ready move. Ready is charge-based
        -- (like SCH stratagems): gated on a spare charge via validate_ability, not
        -- a plain recast, so it stays usable while the shared timer recharges.
        heal_aoe = {
            {
                name = 'Wild Carrot',
                level = 1,
                cost = 0,
                command = '/pet "Wild Carrot" <me>',
                pet_required = true,
                requires_pet_name = { 'Keeneared Steffi', 'Rabbit' },  -- rabbit jug pets only
                requires_ready_charge = true,  -- needs Ready charges (id 102)
                ready_charge_cost = 2,         -- Wild Carrot burns 2 charges, not 1
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_pet_enabled = true,
        heal_pet_threshold = 50,
        buff_enabled = true,
        heal_aoe_enabled = true,
        heal_aoe_threshold = 70,
        pet_debuff_removal_enabled = true,
    },

    -- Action priority order
    priority_order = {
        'heal_aoe',
        'heal_pet',
        'pet_debuff_removal',
        'buff',
    },

    -- BST-specific gating: pet presence, rabbit-only moves, and Ready charges.
    validate_ability = function(ability, common)
        if ability.pet_required and not common.get_pet_entity() then
            return false
        end

        -- Wild Carrot only exists on the rabbit jug pets (requires_pet_name).
        if not common.pet_type_ok(ability) then
            return false
        end

        -- Ready is charge-based; block when fewer charges banked than the move costs.
        if ability.requires_ready_charge then
            local gs = common.game_state
            if not gs or (gs.ready_charges or 0) < (ability.ready_charge_cost or 1) then
                return false
            end
        end

        return true
    end,
}
