--[[
    Client resources as plain tables: { [id] = row }, the runtime catalog's
    source. The offline tests' data (tests/data/*.lua) was dumped in this
    shape, so keep a row's fields as they are.
]]--

local resources = {}

function resources.spells(rm)
    local out = {}
    for id = 1, 1023 do
        local s = rm:GetSpellById(id)
        local en = s and s.Name[1]
        if en and en ~= '' then
            -- { [job_id] = level }; -1 = unlearnable, >99 = job point unlock.
            local lv = {}
            for job = 1, 22 do
                local l = s.LevelRequired[job + 1]
                if l > 0 then lv[job] = l end
            end
            out[id] = { en = en, jp = s.Name[2], type = s.Type, skill = s.Skill, element = s.Element,
                targets = s.Targets, mp = s.ManaCost, cast = s.CastTime, recast = s.RecastDelay,
                range = s.Range, area = s.AreaRange, req = s.Requirements, lv = lv }
        end
    end
    return out
end

function resources.abilities(rm)
    local out = {}
    for id = 1, 2047 do
        local a = rm:GetAbilityById(id)
        local en = a and a.Name[1]
        if en and en ~= '' then
            out[id] = { en = en, jp = a.Name[2], type = a.Type, element = a.Element, mp = a.ManaCost,
                tp = a.TPCost, recast_id = a.RecastTimerId, targets = a.Targets, range = a.Range, area = a.AreaRange }
        end
    end
    return out
end

function resources.statuses(rm)
    local out = {}
    for id = 0, 1023 do
        local en = rm:GetString('buffs.names', id, 2)  -- langId: 1 Japanese, 2 English
        if en and en ~= '' then
            out[id] = { en = en, jp = rm:GetString('buffs.names', id, 1) }
        end
    end
    return out
end

-- Items, each read the first time it's asked for: only the few the knowledge table names are.
function resources.items(rm)
    return setmetatable({}, { __index = function (t, id)
        local i = rm:GetItemById(id)
        local en = i and i.Name[1]
        t[id] = en and en ~= '' and { en = en, jp = i.Name[2] } or false
        return t[id]
    end })
end

-- All of them, read once: the DATs don't change while the client runs.
local cache
function resources.load()
    if not cache then
        local rm = AshitaCore:GetResourceManager()
        cache = { spells = resources.spells(rm), abilities = resources.abilities(rm), statuses = resources.statuses(rm),
                  items = resources.items(rm) }
    end
    return cache
end

return resources
