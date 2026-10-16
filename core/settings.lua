--[[
    Settings: one file per job pair (config/addons/sidekick3/<character>/WHM_BLM.lua),
    and the row rule shared by the engine and the UI.

    A row is a spell family ("Cure"), a pick_one group ("barelement") or a labelled
    use ("Regen (keep up)", when one family has several):
        rows[key] = { on = bool, pick = action name or nil (= best tier),
                      targets = { [party slot] = true } }    -- buffs only
    A row never saved uses its default: on, except buffs and sending the pet in,
    which are opt-in.
    `ui` is the window: open at load, section layout, auto-fit or custom size.
]]--

local settings = {}

local DEFAULTS = {
    -- HP% lines: danger, critical; efficient above danger (behaviors/heal.lua);
    -- the focus member has its own. skip = { [name] = true }: never healed for their sake.
    heal = { on = true, danger = 50, critical = 30,
             focus = '', focus_danger = 60, focus_critical = 40, skip = {},
             cure_potency = 0, waltz_potency = 0,  -- +% from gear
             regen_potency = 0 },                  -- +HP per Regen tick from gear
    remove = { on = true },
    wake = { on = true },                  -- wake sleeping members with a heal that wakes
    recover = { on = true, mp = 30, tp = 1000,    -- under your MP% (a member's, for Devotion), your TP
                min_tp = 3000 },                   -- Chivalry from this much TP
    pet = { on = true, heal = 50 },        -- heal your pet under this HP%
    buff = { on = true },
    revive = { on = true },
    follow = { on = false, target = '', distance = 5 },  -- /follow them past this many yalms
    rest = { on = false, delay = 5, distance = 7 },  -- /heal after this many quiet seconds; up past distance from follow.target
    japanese = false,  -- send spell and ability names in Japanese
    rows = {},
    ui = { open = false, display = 'headers', size = 'auto' },  -- display: headers | tabs | groups; size: auto | custom
}

-- pick_one before label: labelled members of one group (geo_ja) stay one row.
function settings.key(a) return a.pick_one or a.label or a.family end

local OPT_IN = { buff = true, pet_send = true }

function settings.row(cfg, a)
    return cfg.rows[settings.key(a)] or { on = not OPT_IN[a.role] }
end

-- The catalog's actions for `role` whose row is on.
function settings.enabled(cat, cfg, role)
    local out = {}
    for _, a in ipairs(cat) do
        if a.role == role and settings.row(cfg, a).on then out[#out + 1] = a end
    end
    return out
end

-- A fresh copy of the defaults, for tests and new files.
function settings.defaults()
    local function copy(t)
        local out = {}
        for k, v in pairs(t) do out[k] = type(v) == 'table' and copy(v) or v end
        return out
    end
    return copy(DEFAULTS)
end

-- Ashita's settings library, loaded only in game.
local lib, alias
function settings.load(job_pair)
    lib = lib or require('settings')
    alias = job_pair
    local function T_(t)
        for k, v in pairs(t) do if type(v) == 'table' then t[k] = T_(v) end end
        return T(t)
    end
    return lib.load(T_(settings.defaults()), alias)
end

function settings.save()
    if lib then lib.save(alias) end
end

return settings
