--[[
    Your pet: heal it under the pet HP line and clear what ails it (care), and
    send it at your battle target when it isn't fighting (send, opt-in per row:
    Assault, Fight, Deploy). With pet.at_t, sending goes at your own target (<t>)
    instead, and only while you're engaged, so a cursor passing over a mob nobody
    is fighting never sends it. Both go out as /ja or /pet on <me>, <bt> or <t>,
    never while you're Invisible (core/engine.lua).
    A care row that needs ammo worn (Repair's and Maintenance's oil, Reward's pet
    food) and would go with it first equips it (core/ammo.lua), and the next row
    waits while it goes on.
]]--

local ammo = require('core.ammo')
local can = require('core.can')
local settings = require('core.settings')
local util = require('core.util')

local ENGAGED = 1  -- entity status, yours and your pet's

local pet = {}

-- The rows of `role` that are on, highest priority first.
local function rows(cat, cfg, role)
    local list = settings.enabled(cat, cfg, role)
    table.sort(list, util.by_priority)
    return list
end

-- `a` now, or the equip of its ammo when that alone stops it (core/ammo.lua); nil
-- when neither can go, and true too while an equip just sent for it has yet to show.
local function use(a, g, cfg, mem, why)
    if can.use(a, g) then return { action = a, why = why } end
    return ammo.equip(a, g, cfg, mem, why)
end

function pet.care(g, cat, cfg, mem)
    local p = g.pet
    if not p or p.hpp == 0 then return nil end
    if p.hpp < cfg.pet.heal then
        for _, a in ipairs(rows(cat, cfg, 'pet_heal')) do
            if can.spare_hp(a, g, cfg) then
                local intent, equipping = use(a, g, cfg, mem, ('%s %d%%'):format(p.name, p.hpp))
                if intent or equipping then return intent end  -- not the next row while its ammo goes on
            end
        end
    end
    for _, a in ipairs(rows(cat, cfg, 'pet_remove')) do
        if can.any(p.buffs, a.removes) then
            local intent, equipping = use(a, g, cfg, mem, p.name)
            if intent or equipping then return intent end
        end
    end
end

function pet.send(g, cat, cfg)
    local p = g.pet
    if not p or p.hpp == 0 or p.status == ENGAGED then return nil end
    local at_t = cfg.pet.at_t == true
    local mob = at_t and g.me.status == ENGAGED and g.t or not at_t and g.bt
    if not (mob and mob.mob and mob.hpp > 0) then return nil end
    -- can.use measures an enemy action's range from g.bt, and holds it to combat:
    -- at <t>, that's your target, and being engaged is combat.
    local seen = at_t and util.overlay(g, { bt = mob, combat = true }) or g
    for _, a in ipairs(settings.enabled(cat, cfg, 'pet_send')) do
        if can.use(a, seen) then return { action = a, at = at_t and '<t>' or nil, why = ('%s at %s'):format(p.name, mob.name) } end
    end
end

return pet
