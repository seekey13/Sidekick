--[[
    Your pet: heal it under the pet HP line and clear what ails it (care), and
    send it at your battle target when it isn't fighting (send, opt-in per row:
    Assault, Fight, Deploy). Both go out as /ja or /pet on <me> or <bt>, never
    while you're Invisible.
]]--

local can = require('core.can')
local settings = require('core.settings')

local INVISIBLE = 69
local ENGAGED = 1  -- entity status

local pet = {}

local function by_priority(list)
    table.sort(list, function (a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return (a.level or 0) > (b.level or 0)
    end)
    return list
end

local function clears(a, p)
    for _, id in ipairs(a.removes) do if p.buffs[id] then return true end end
    return false
end

function pet.care(g, cat, cfg)
    local p = g.pet
    if not p or p.hpp == 0 or g.me.buffs[INVISIBLE] then return nil end
    if p.hpp < cfg.pet.heal then
        for _, a in ipairs(by_priority(settings.enabled(cat, cfg, 'pet_heal'))) do
            if can.use(a, g) and can.spare_hp(a, g, cfg) then
                return { action = a, why = ('%s %d%%'):format(p.name, p.hpp) }
            end
        end
    end
    for _, a in ipairs(by_priority(settings.enabled(cat, cfg, 'pet_remove'))) do
        if clears(a, p) and can.use(a, g) then return { action = a, why = p.name } end
    end
end

function pet.send(g, cat, cfg)
    local p, bt = g.pet, g.bt
    if not p or p.status == ENGAGED or not (bt and bt.mob and bt.hpp > 0) or g.me.buffs[INVISIBLE] then return nil end
    for _, a in ipairs(settings.enabled(cat, cfg, 'pet_send')) do
        if can.use(a, g) then return { action = a, why = ('%s at %s'):format(p.name, bt.name) } end
    end
end

return pet
