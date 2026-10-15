--[[
    Client resources as plain tables: { [id] = row }. The runtime catalog and
    /sk3 dump both read through here, so the offline tests (tests/data/*.lua)
    see exactly the shape the game produces.
]]--

local resources = {}

-- Field order for each table; /sk3 dump writes rows in this order.
resources.FIELDS = {
    spells    = { 'en', 'jp', 'type', 'skill', 'element', 'targets', 'mp', 'cast', 'recast', 'range', 'area', 'req', 'lv' },
    abilities = { 'en', 'jp', 'type', 'element', 'mp', 'tp', 'recast_id', 'targets', 'range', 'area' },
    statuses  = { 'en', 'jp' },
}

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

-- All three, read once: the DATs don't change while the client runs.
local cache
function resources.load()
    if not cache then
        local rm = AshitaCore:GetResourceManager()
        cache = { spells = resources.spells(rm), abilities = resources.abilities(rm), statuses = resources.statuses(rm) }
    end
    return cache
end

return resources
