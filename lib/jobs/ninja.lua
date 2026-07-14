--[[
    Ninja job definition
    Support automation for Ninja is buffs only:
    - Ninja stances: Yonin / Innin (mutually exclusive -> one group)
    - Ninjutsu utility: Utsusemi (shadows), Tonko (movement), Monomi (Sneak/Hide)
    - Sange (throws shuriken)

    TWO different item requirements, deliberately kept apart:

    * Ninjutsu need a TOOL in INVENTORY (not equipped) to cast. Each family has
      its own tool, and Shikanofuda (2972) substitutes for any of the three, so
      requires_item lists { family tool, Shikanofuda } and count_equippable_items
      sums both. The UI shows that count in green (red when 0); a spell with zero
      matching tools is grayed and never cast (see filter_abilities_by_level).

    * Sange throws a shuriken, so it needs one EQUIPPED in the ammo slot -- the
      same requires_equipped_ammo gate + auto-equip used by BST Reward / PUP
      Repair. Best owned tier <= level is auto-equipped before it fires.

    NOTE (verify in-game): the source table left Utsusemi: Ni's buff_id blank and
    put the shadow set on Tonko: Ni; read as a row shift, so here Tonko (both
    tiers) detects buff 69 and Utsusemi (both tiers) detects the shadow set.
]]--

-- Ninjutsu tools -- inventory consumables, NOT equipment. Each family lists its
-- own tool plus Shikanofuda (2972), the universal substitute; only .id is read
-- for counting, name kept for readability.
local UTSUSEMI_TOOLS = { { id = 1179, name = 'Shihei' },          { id = 2972, name = 'Shikanofuda' } }
local TONKO_TOOLS    = { { id = 1194, name = 'Shinobi-tabi' },    { id = 2972, name = 'Shikanofuda' } }
local MONOMI_TOOLS   = { { id = 2553, name = 'Sanjaku-Tenugui' }, { id = 2972, name = 'Shikanofuda' } }

-- Shuriken ammo tiers thrown by Sange: id, /equip name, equip level (worst->best).
local SHURIKENS = {
    { id = 17301, name = 'Shuriken',       level = 18 },
    { id = 17302, name = 'Juji Shuriken',  level = 28 },
    { id = 17303, name = 'Manji Shuriken', level = 48 },
    { id = 17304, name = 'Fuma Shuriken',  level = 60 },
    { id = 18712, name = 'Koga Shuriken',  level = 75 },
}

-- Utsusemi shadow buffs (Copy Image tiers): any present == shadows still up.
local SHADOWS = { 66, 444, 445, 446 }

return {
    job_id = 13,
    job_name = 'Ninja',
    resource_type = 'tp',

    abilities = {
        buff = {
            -- Stances: Yonin/Innin are JAs (no tool), mutually exclusive and share
            -- a recast, so one group -> single-select dropdown in the UI.
            {
                name = 'Yonin',
                level = 40,
                cost = 0,
                id = 146,
                command = '/ja "Yonin" <me>',
                buff_id = 420,
                group = 'nin_stance',
            },
            {
                name = 'Innin',
                level = 40,
                cost = 0,
                id = 147,
                command = '/ja "Innin" <me>',
                buff_id = 421,
                group = 'nin_stance',
            },

            -- Utsusemi (shadows). Ichi/Ni share the shadow buff set + group; higher
            -- cost sorts Ni first so it's the default selected tier.
            {
                name = 'Utsusemi: Ni',
                level = 37,
                cost = 0,
                id = 339,
                command = '/ma "Utsusemi: Ni" <me>',
                buff_id = SHADOWS,
                group = 'utsusemi',
                requires_item = UTSUSEMI_TOOLS,
                item_label = 'Shihei',
                one_shadow_buff = 66,  -- Copy Image (1) -- see "Cast with 1 Shadow"
            },
            {
                name = 'Utsusemi: Ichi',
                level = 12,
                cost = 0,
                id = 338,
                command = '/ma "Utsusemi: Ichi" <me>',
                buff_id = SHADOWS,
                group = 'utsusemi',
                requires_item = UTSUSEMI_TOOLS,
                item_label = 'Shihei',
                one_shadow_buff = 66,  -- Copy Image (1) -- see "Cast with 1 Shadow"
            },

            -- Tonko (movement/Sneak). Ichi/Ni share buff 69 + group. Idle only --
            -- sneaking is a between-fights thing, not a combat recast.
            {
                name = 'Tonko: Ni',
                level = 34,
                cost = 0,
                id = 354,
                command = '/ma "Tonko: Ni" <me>',
                buff_id = 69,
                group = 'tonko',
                requires_item = TONKO_TOOLS,
                item_label = 'Shinobi-tabi',
                idle_only = true,
            },
            {
                name = 'Tonko: Ichi',
                level = 9,
                cost = 0,
                id = 353,
                command = '/ma "Tonko: Ichi" <me>',
                buff_id = 69,
                group = 'tonko',
                requires_item = TONKO_TOOLS,
                item_label = 'Shinobi-tabi',
                idle_only = true,
            },

            -- Monomi (Sneak). Ungrouped single tier. Idle only.
            {
                name = 'Monomi: Ichi',
                level = 25,
                cost = 0,
                id = 318,
                command = '/ma "Monomi: Ichi" <me>',
                buff_id = 71,
                requires_item = MONOMI_TOOLS,
                item_label = 'Sanjaku-Tenugui',
                idle_only = true,
            },

            -- Sange: JA that throws a shuriken, so it needs one EQUIPPED in the
            -- ammo slot (auto-equipped like BST food / PUP oil).
            {
                name = 'Sange',
                level = 75,
                cost = 0,
                id = 145,
                ability_id = 171,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Sange" <me>',
                buff_id = 352,
                requires_equipped_ammo = SHURIKENS,  -- gate + auto-equip tiers
                ammo_main_job_only = true,           -- Sange is a NIN-main merit
                ammo_label = 'Shuriken',             -- UI count label
                combat_only = true,
            },
        },
    },

    default_settings = {
        buff_enabled = true,
        cast_with_1_shadow = false,  -- see lib/actions/buff.lua self-buff branch
    },

    priority_order = {
        'item',
        'buff',
    },
}
