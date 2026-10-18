--[[
    Your pet: heal it under the pet HP line and clear what ails it (care), and
    send it at your battle target when it isn't fighting (send, opt-in per row:
    Assault, Fight, Deploy). Both go out as /ja or /pet on <me> or <bt>, never
    while you're Invisible.
    A care row that needs ammo worn (Repair's and Maintenance's oil, Reward's pet
    food) and would go with it first equips it (core/ammo.lua), and the next row
    waits while it goes on.
]]--

local ammo = require('core.ammo')
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

-- `a` now, or the equip of its ammo when that alone stops it (core/ammo.lua); nil
-- when neither can go, and true too while an equip just sent for it has yet to show.
local function use(a, g, cfg, mem, why)
    if can.use(a, g) then return { action = a, why = why } end
    return ammo.equip(a, g, cfg, mem, why)
end

function pet.care(g, cat, cfg, mem)
    local p = g.pet
    if not p or p.hpp == 0 or g.me.buffs[INVISIBLE] then return nil end
    if p.hpp < cfg.pet.heal then
        for _, a in ipairs(by_priority(settings.enabled(cat, cfg, 'pet_heal'))) do
            if can.spare_hp(a, g, cfg) then
                local intent, equipping = use(a, g, cfg, mem, ('%s %d%%'):format(p.name, p.hpp))
                if intent or equipping then return intent end  -- not the next row while its ammo goes on
            end
        end
    end
    for _, a in ipairs(by_priority(settings.enabled(cat, cfg, 'pet_remove'))) do
        if clears(a, p) then
            local intent, equipping = use(a, g, cfg, mem, p.name)
            if intent or equipping then return intent end
        end
    end
end

function pet.send(g, cat, cfg)
    local p, bt = g.pet, g.bt
    if not p or p.hpp == 0 or p.status == ENGAGED or not (bt and bt.mob and bt.hpp > 0) or g.me.buffs[INVISIBLE] then
        return nil
    end
    for _, a in ipairs(settings.enabled(cat, cfg, 'pet_send')) do
        if can.use(a, g) then return { action = a, why = ('%s at %s'):format(p.name, bt.name) } end
    end
end

return pet
