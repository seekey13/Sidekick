--[[
    Profiles: named snapshots of a job pair's settings (Dynamis, EXP...), as v2's.
    They live in the pair's own file, so each job pair has its own:
        cfg.profiles[name] = snapshot    cfg.profile = the one loaded, '' for Default
    Settings stay the auto-saving working copy: a change after a load is saved to
    it, never to the profile, which changes only on Save or Save as. Loading one
    from Default first parks the working copy (cfg.parked), so Default brings it back.

    Never in a snapshot, and never changed by a load: the profiles themselves, the
    HUD and the client's language (`ui`, its own file), and who the party is now:
    following, the focus member, the members healing skips and who Entrust goes on;
    and AFK sleep, the box's and not a profile's (new: v2's profiles carried it).
]]--

local settings = require('core.settings')
local util = require('core.util')

local profiles = {}

-- true: the whole key is kept; a table: those keys inside it.
local KEPT = { profiles = true, profile = true, parked = true, ui = true, follow = true, afk = true,
               heal = { focus = true, skip = true }, geo = { entrust = true } }

local copy = util.copy

-- The defaults under every key `t` lacks, as Ashita's library fills a file
-- saved before newer settings existed.
local function backfill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = copy(v)
        elseif type(v) == 'table' and type(t[k]) == 'table' then backfill(t[k], v) end
    end
    return t
end

-- `t` without the keys `kept` names.
local function without(t, kept)
    local out = {}
    for k, v in pairs(t) do
        if kept[k] ~= true then out[k] = type(kept[k]) == 'table' and type(v) == 'table' and without(v, kept[k]) or copy(v) end
    end
    return out
end

local function snapshot(cfg) return without(cfg, KEPT) end

-- Live settings become `source` (a snapshot, or {} for the defaults), in place:
-- Sidekick and Ashita's library hold this very table. What KEPT names stays.
local function apply(cfg, source)
    local new = backfill(snapshot(source), snapshot(settings.defaults()))
    for k in pairs(cfg) do
        if KEPT[k] ~= true then
            local keep = type(KEPT[k]) == 'table' and cfg[k] or {}
            cfg[k] = new[k]
            for sub in pairs(type(KEPT[k]) == 'table' and KEPT[k] or {}) do cfg[k][sub] = keep[sub] end
        end
    end
    for k, v in pairs(new) do
        if cfg[k] == nil then cfg[k] = v end
    end
end

-- A name a profile can have: not blank, not Default.
local function valid(name)
    return type(name) == 'string' and name ~= '' and name:lower() ~= 'default'
end

-- Every profile's name, case aside in order.
function profiles.names(cfg)
    local out = {}
    for name in pairs(cfg.profiles) do out[#out + 1] = name end
    table.sort(out, function (a, b) return a:lower() < b:lower() end)
    return out
end

-- The profile loaded, or nil for Default.
function profiles.active(cfg)
    local name = cfg.profile
    return name ~= '' and cfg.profiles[name] and name or nil
end

-- A name as chat gives it back: any case, spaces run together.
local function loose(name) return (name:lower():gsub('%s+', ' ')) end

-- The profile named `name`: exactly, else in any case and spacing (a command's
-- words are joined by single spaces, and chat isn't case-exact).
function profiles.find(cfg, name)
    if not valid(name) then return nil end
    if cfg.profiles[name] then return name end
    for stored in pairs(cfg.profiles) do
        if loose(stored) == loose(name) then return stored end
    end
end

-- Save as: the settings as they are now under `name`, over any profile of that name.
function profiles.save_as(cfg, name)
    if not valid(name) then return false end
    cfg.profiles[name] = snapshot(cfg)
    cfg.profile = name
    return true
end

-- Save: under the loaded profile's name, the settings as they are now; under
-- another name while one is loaded, that profile renamed (not saved again);
-- with Default loaded, a new profile. False for a name a profile can't have,
-- and for another profile's name: only Save as replaces one.
function profiles.save(cfg, name)
    if not valid(name) then return false end
    local active = profiles.active(cfg)
    if cfg.profiles[name] and name ~= active then return false end
    if not active or active == name then return profiles.save_as(cfg, name) end
    cfg.profiles[name], cfg.profiles[active] = cfg.profiles[active], nil
    cfg.profile = name
    return true
end

-- Load a profile by its stored name. Leaving Default parks the working copy,
-- as does the first load after a Save from Default (nothing parked yet); going
-- from one profile to another leaves it parked as it was.
function profiles.load(cfg, name)
    local snap = cfg.profiles[name]
    if not snap then return false end
    if not profiles.active(cfg) or not next(cfg.parked) then cfg.parked = snapshot(cfg) end
    apply(cfg, snap)
    cfg.profile = name
    return true
end

-- Back to Default: the parked working copy, else the settings as they are.
function profiles.load_default(cfg)
    if next(cfg.parked) then apply(cfg, cfg.parked) end
    cfg.parked, cfg.profile = {}, ''
end

-- New: the working copy back to the defaults, on Default. Profiles are kept.
function profiles.new(cfg)
    apply(cfg, {})
    cfg.parked, cfg.profile = {}, ''
end

-- Delete a profile; deleting the loaded one goes back to Default as it was parked.
function profiles.delete(cfg, name)
    if not cfg.profiles[name] then return false end
    local was_active = profiles.active(cfg) == name
    cfg.profiles[name] = nil
    if was_active then profiles.load_default(cfg) end
    return true
end

return profiles
