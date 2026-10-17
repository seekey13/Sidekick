--[[
    Settings: one file per job pair (config/addons/sidekick3/<character>/WHM_BLM.lua),
    and the row rule shared by the engine and the UI.

    A row is a spell family ("Cure"), a pick_one group ("barelement") or a labelled
    use ("Regen (keep up)", when one family has several):
        rows[key] = { on = bool, pick = action name or nil (= best tier),
                      targets = { [party or alliance slot] = true, [tracked name] = true },  -- buffs only
                      mods = { [modifier name] = true } }  -- buffs only: stratagems fired first
    A tracked player's name stays on the row after they're untracked, so tracking
    them again brings their buffs back.
    A row never saved uses its default: on, except buffs, sending the pet in and
    items, which are opt-in.
    `profiles` are named snapshots of the rest (core/profiles.lua).
    `ui` is shared by every job pair (its own file, ui.lua): the window, so the HUD
    looks the same whatever you play (shown at load, bar and font sizes in pixels,
    the panel's opacity in %, whether the HUD is locked in place), and whether the
    client runs in Japanese, which is the install's and not a job's.
]]--

local settings = {}

local DEFAULTS = {
    -- HP% lines: danger, critical; efficient above danger (behaviors/heal.lua);
    -- the focus member has its own. skip = { [name] = true }: never healed for their sake;
    -- alliance: the alliance's other parties healed too (v2's default: off).
    heal = { on = true, danger = 50, critical = 30,
             focus = '', focus_danger = 60, focus_critical = 40, skip = {}, alliance = false,
             cure_potency = 0, waltz_potency = 0,  -- +% from gear
             regen_potency = 0,                    -- +HP per Regen tick from gear
             reserve = false },  -- SCH: buff rows leave the last stratagem charge for healing (as v2's, opt-in)
    remove = { on = true },
    wake = { on = true },                  -- wake sleeping members with a heal that wakes
    recover = { on = true, mp = 30, tp = 1000,    -- under your MP% (a member's, for Devotion), your TP
                min_tp = 3000 },                   -- Chivalry from this much TP
    pet = { on = true, heal = 50 },        -- heal your pet under this HP%
    -- COR: the rolls kept up (names, '' for none; the second only on a COR main
    -- job) and how far Double-Up chases a total: 'lowest' | 'medium' | 'highest'.
    roll = { on = true, first = '', second = '', risk = 'medium' },
    buff = { on = true,
             hold_aoe = false,  -- hold an area buff spell (Protectra, songs) until the party's players gather
             gather = true },   -- ...and ask them to in party chat
    revive = { on = true },
    follow = { on = false, target = '', distance = 5 },  -- /follow them past this many yalms
    rest = { on = false, delay = 5, distance = 7 },  -- /heal after this many quiet seconds; up past distance from follow.target
    rows = {},
    profiles = {}, profile = '', parked = {},  -- named snapshots (core/profiles.lua)
    ui = { open = false, hp_width = 220, hp_height = 40, mp_width = 220, mp_height = 18,
           name_size = 22, text_size = 14, gap = 8, opacity = 100, locked = false,
           japanese = false },  -- send spell, ability and item names in Japanese
}
local UI_FILE = 'ui'

-- pick_one before label: labelled members of one group (geo_ja) stay one row.
function settings.key(a) return a.pick_one or a.label or a.family end

local OPT_IN = { buff = true, pet_send = true }

function settings.row(cfg, a)
    return cfg.rows[settings.key(a)] or { on = not (OPT_IN[a.role] or a.kind == 'item') }
end

-- The buff in `cat` named `name` (lower case): a spell, its family or its row key,
-- or the spell's Japanese name (typed on a Japanese client, in the DAT's encoding).
-- The second result is true when it names the spell itself, not its row.
function settings.buff_named(cat, name)
    for _, x in ipairs(cat) do
        if x.role == 'buff' then
            local spell = x.name:lower() == name or (x.jp or '') ~= '' and x.jp:lower() == name
            if spell or x.family:lower() == name or settings.key(x):lower() == name then return x, spell end
        end
    end
end

-- The catalog's actions for `role` whose row is on.
function settings.enabled(cat, cfg, role)
    local out = {}
    for _, a in ipairs(cat) do
        if a.role == role and settings.row(cfg, a).on then out[#out + 1] = a end
    end
    return out
end

-- The modifiers (Penury, Accession...) turned on for `a`'s row that fit `a`.
function settings.mods(cat, cfg, a)
    local on, out = settings.row(cfg, a).mods, {}
    if not on then return out end
    for _, m in ipairs(cat) do
        if m.role == 'modifier' and m.applies and on[m.name] and m.applies(a) then out[#out + 1] = m end
    end
    return out
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == 'table' and copy(v) or v end
    return out
end
settings.defaults_copy = copy

-- A fresh copy of the defaults, for tests and new files.
function settings.defaults() return copy(DEFAULTS) end

-- Ashita's settings library, loaded only in game. The job pair's file holds
-- everything but `ui`, which loads from and saves to its own file.
local lib, alias, loaded
function settings.load(job_pair)
    lib = lib or require('settings')
    alias = job_pair
    local function T_(t)
        for k, v in pairs(t) do if type(v) == 'table' then t[k] = T_(v) end end
        return T(t)
    end
    -- The library fills a key the file lacks with the defaults' own table and
    -- keeps those defaults (for the next character's load): give it copies, so
    -- what is written into the settings (a profile, a skipped name) stays out of them.
    local function detach(defaults)
        for k, v in pairs(defaults) do
            if type(v) == 'table' then defaults[k] = T_(settings.defaults_copy(v)) end
        end
    end
    local d = T_(settings.defaults())
    local ui = d.ui
    d.ui = nil
    loaded = lib.load(d, alias)
    detach(d)
    loaded.ui = lib.load(ui, UI_FILE)
    detach(ui)
    -- A pair's own Japanese client from before it moved to `ui`: carried over when
    -- on, and saved at once so the pair's file no longer holds it.
    local old = loaded.japanese
    if old ~= nil then
        loaded.japanese = nil
        if old == true then loaded.ui.japanese = true end
        settings.save()
    end
    return loaded
end

function settings.save()
    if not lib then return end
    local ui = loaded.ui
    loaded.ui = nil  -- kept out of the job pair's file
    lib.save(alias)
    loaded.ui = ui
    lib.save(UI_FILE)
end

-- The library loads every file again on a logout and login, into new tables:
-- the ones held are then no longer the ones it saves, so load them again.
function settings.switched()
    return lib ~= nil and loaded ~= nil and (lib.get(alias) ~= loaded or lib.get(UI_FILE) ~= loaded.ui)
end

return settings
