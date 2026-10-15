--[[
    Settings: one file per job pair (config/addons/sidekick3/<character>/WHM_BLM.lua),
    and the row rule shared by the engine and the UI.

    A row is a spell family ("Cure") or a pick_one group ("barelement"):
        rows[key] = { on = bool, pick = action name or nil (= best tier),
                      targets = { [party slot] = true } }    -- buffs only
    A row never saved uses its default: on, except buffs, which are opt-in.
]]--

local settings = {}

local DEFAULTS = {
    heal = { on = true, threshold = 75, critical = 30, focus = '', focus_threshold = 85,
             cure_potency = 0, waltz_potency = 0 },  -- +% from gear, applied to each cure's potency
    remove = { on = true },
    buff = { on = true },
    revive = { on = true },
    japanese = false,  -- send spell and ability names in Japanese
    rows = {},
}

function settings.key(a) return a.pick_one or a.family end

function settings.row(cfg, a)
    return cfg.rows[settings.key(a)] or { on = a.role ~= 'buff' }
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
