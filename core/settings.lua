--[[
    Settings: one file per job pair (config/addons/sidekick/<character>/WHM_BLM.lua),
    and the row rule shared by the engine and the UI.

    A row is a spell family ("Cure"), a pick_one group ("barelement") or a labelled
    use ("Regen (keep up)", when one family has several):
        rows[key] = { on = bool, pick = action name or nil (= best tier),
                      targets = { [party or alliance slot] = true, [tracked name] = true },  -- buffs only
                      mods = { [modifier name] = true },  -- buffs only: stratagems, Embolden fired first
                      hold = true,  -- buffs only: the spell waits while one of its mods can't go
                      match = true }  -- enspells, storms: Auto, the tier matching the sky, `pick` when none does (core/sky.lua)
    A tracked player's name stays on the row after they're untracked, so tracking
    them again brings their buffs back. A row never saved uses its default: on, but
    for buffs (a luopan's Geo- spells too), sending the pet in and items.
    gates[key] = 'combat' | 'idle': the row goes only in combat, or only out of it
    (can.gate), one or the other; none, any time. Kept apart from `rows` so setting
    one never makes a row whose `on` would have to be guessed. An action's own gate
    (Berserk, Spectral Jig: core/knowledge.lua) comes first. Waking ignores it
    (behaviors/wake.lua), and so does a modifier sharing the key (SCH's Accession).
    `profiles` are named snapshots of the rest (core/profiles.lua). `ui` is the
    install's, shared by every job pair in its own file (ui.lua): the HUD's look and
    whether the client runs in Japanese.
]]--

local util = require('core.util')

local settings = {}

local DEFAULTS = {
    -- HP% lines: efficient under threshold, danger, critical (behaviors/heal.lua);
    -- the focus member has its own. skip = { [name] = true }: never healed for their sake.
    -- The alliance's other parties are healed whenever a heal reaches them.
    -- never = { [spell or ability name] = true }: healing never uses that one, its row's other tiers
    -- still; waking still does.
    heal = { on = true, threshold = 75, danger = 50, critical = 30,
             focus = '', focus_threshold = 85, focus_danger = 60, focus_critical = 40, skip = {}, never = {},
             cure_potency = 0, waltz_potency = 0,  -- +% from gear
             regen_potency = 0,                    -- +HP per Regen tick from gear
             reserve = false },  -- SCH: buff rows leave the last stratagem charge for healing (as v2's, opt-in)
    -- skip = { [status name] = true }: debuffs left on everyone without a set of their own.
    -- off = { [name] = true }: removal leaves that player alone, Doom too.
    -- own = { [name] = { set = true, skip = { [status] = true } } }: that player's debuffs, instead of skip.
    -- doom_retries: Cursnas sent again after one misses a Doom read from packets (a trust's, the alliance's, a
    -- tracked player's); past them the Doom is taken as gone (core/removal.lua).
    remove = { on = true, skip = {}, off = {}, own = {}, doom_retries = 5 },
    wake = { on = true },                  -- wake sleeping members with a heal that wakes
    recover = { on = true, mp = 30, tp = 1000,    -- under your MP% (a member's, for Devotion), your TP
                min_tp = 3000 },                   -- Chivalry from this much TP
    pet = { on = true, heal = 50,          -- heal your pet under this HP%
            at_t = false },                -- send it in at your own target (<t>) while engaged, not <bt>
    -- The job modules' sections (roll, song, geo, rune, maneuver) come from their
    -- `settings` (core/jobs.lua).
    buff = { on = true,
             hold_aoe = false,  -- hold an area buff spell (Protectra, songs, rolls) until the party's players gather
             gather = true,     -- ...and ask them to in party chat
             one_shadow = false },  -- NIN: recast Utsusemi at its last shadow (v2's Cast with 1 Shadow)
    revive = { on = true },
    follow = { on = false, target = '', distance = 5 },  -- /follow them past this many yalms
    rest = { on = false, mp = 50, distance = 7 },  -- /heal under this MP% until full; up past distance from follow.target
    afk = { on = true, minutes = 10 },  -- sleep after this long with no party movement or combat (core/afk.lua; v2's, on)
    rows = {},
    gates = {},  -- [row key] = 'combat' | 'idle' (the header)
    profiles = {}, profile = '', parked = {},  -- named snapshots (core/profiles.lua)
    ui = { open = false, hp_width = 220, hp_height = 40, mp_width = 220, mp_height = 18, tp_width = 220, tp_height = 8,
           name_size = 22, text_size = 14, gap = 8, locked = false,
           hide_mp = true,  -- leave out the MP bar of a member or pet with no MP (0/0)
           widget = false,  -- the widget, v2's floating one (/sk widget)
           widget_size = 16,  -- its text and icons' height, in pixels
           list_rows = 8,  -- the most choices a drop-down's list shows before it scrolls (kit.LIST_ROWS.default)
           zone_stop = false,  -- After zone stop: automation stops as you zone (v2's Stop after zone)
           load_stopped = true,  -- Always load stopped: off, a load starts automation as it was left (v2's Load stopped)
           running = false,  -- ...as it was left: kept by Sidekick.lua while load_stopped is off
           japanese = false },  -- send spell, ability and item names in Japanese
}
local UI_FILE = 'ui'

-- pick_one before label: labelled members of one group (geo_ja) stay one row.
function settings.key(a) return a.pick_one or a.label or a.family end

local OPT_IN = { buff = true, pet_send = true }

local OPT_IN_LUOPAN = { buff = true, debuff = true }  -- a Geo- spell, like a buff

function settings.row(cfg, a)
    return cfg.rows[settings.key(a)] or { on = not (OPT_IN[a.role] or OPT_IN_LUOPAN[a.luopan] or a.kind == 'item') }
end

-- The buff in `cat` named `name` (lower case): a spell, its family or its row key
-- (a luopan's Geo- buffs too),
-- or the spell's Japanese name (typed on a Japanese client, in the DAT's encoding).
-- The second result is true when it names the spell itself, not its row.
function settings.buff_named(cat, name)
    for _, x in ipairs(cat) do
        if x.role == 'buff' or x.luopan == 'buff' then
            local spell = x.name:lower() == name or (x.jp or '') ~= '' and x.jp:lower() == name
            if spell or x.family:lower() == name or settings.key(x):lower() == name then return x, spell end
        end
    end
end

-- Whether healing never uses heal `a` (a Cure II, a Regen): unticked on its own under Heal
-- (heal.never), its row aside. Waking still may.
function settings.never_heal(cfg, a)
    local never = cfg.heal and cfg.heal.never
    return a.role == 'heal' and type(never) == 'table' and never[a.name] == true
end

-- The catalog's actions for `role` whose row is on.
function settings.enabled(cat, cfg, role)
    local out = {}
    for _, a in ipairs(cat) do
        if a.role == role and settings.row(cfg, a).on then out[#out + 1] = a end
    end
    return out
end

-- A pick-one group named by more families than this is named by its key ('Barelement').
settings.LABEL_FAMILIES = 3

-- Row `key`'s name in English as the list shows it, its note aside: its label ('Regen (keep up)') or family,
-- a pick-one group's families ('Light Arts / Dark Arts'), or its key for more than LABEL_FAMILIES. `acts`: its actions.
function settings.name(key, acts)
    local a = acts[1]
    if not a.pick_one then return a.label or a.family end
    local families, seen = {}, {}
    for _, x in ipairs(acts) do
        if not seen[x.family] then seen[x.family] = true; families[#families + 1] = x.family end
    end
    if #families <= settings.LABEL_FAMILIES then return table.concat(families, ' / ') end
    return util.capitalize((key:gsub('_', ' ')))
end

-- The buff rows' order, the Buffs list's and the order buffs are cast in alike: the higher priority first
-- (core/knowledge.lua), then by name (settings.name; in English on any client, so casting never follows the
-- UI's language). A row's priority is its pick's (Addendum: Black's 0, Indi-Refresh's 50), else its highest
-- action's. -> { [key] = place, 1 first }
function settings.buff_order(cat, cfg)
    local acts_of, keys = {}, {}
    for _, a in ipairs(cat) do
        if a.role == 'buff' then
            local key = settings.key(a)
            if not acts_of[key] then acts_of[key] = {}; keys[#keys + 1] = key end
            table.insert(acts_of[key], a)
        end
    end
    local priority, name = {}, {}
    for _, key in ipairs(keys) do
        local acts = acts_of[key]
        local pick, best, picked = settings.row(cfg, acts[1]).pick, -math.huge, nil
        for _, a in ipairs(acts) do
            best = math.max(best, a.priority or 0)
            if a.name == pick then picked = a.priority or 0 end
        end
        priority[key], name[key] = picked or best, settings.name(key, acts):lower()
    end
    table.sort(keys, function (x, y)
        if priority[x] ~= priority[y] then return priority[x] > priority[y] end
        if name[x] ~= name[y] then return name[x] < name[y] end
        return x < y
    end)
    local place = {}
    for i, key in ipairs(keys) do place[key] = i end
    return place
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

-- A fresh copy of the defaults, the job modules' sections too, for tests and new files.
-- core.jobs is required here, not above: the job modules require this file.
function settings.defaults()
    local out = util.copy(DEFAULTS)
    for _, sections in require('core.jobs').each('settings') do
        for k, v in pairs(sections) do
            assert(out[k] == nil, 'a job module repeats a setting: ' .. k)
            out[k] = util.copy(v)
        end
    end
    return out
end

-- `t` and every table in it as Ashita's T{} tables.
local function T_(t)
    for k, v in pairs(t) do if type(v) == 'table' then t[k] = T_(v) end end
    return T(t)
end

-- The library fills a key the file lacks with the defaults' own table and keeps
-- those defaults (for the next character's load): give it copies, so what is
-- written into the settings (a profile, a skipped name) stays out of them.
local function detach(defaults)
    for k, v in pairs(defaults) do
        if type(v) == 'table' then defaults[k] = T_(util.copy(v)) end
    end
end

-- Ashita's settings library, loaded only in game. The job pair's file holds
-- everything but `ui`, which loads from and saves to its own file.
local lib, alias, loaded
function settings.load(job_pair)
    lib = lib or require('settings')
    alias = job_pair
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
