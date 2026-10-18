--[[
    Your pet: heal it under the pet HP line and clear what ails it (care), and
    send it at your battle target when it isn't fighting (send, opt-in per row:
    Assault, Fight, Deploy). Both go out as /ja or /pet on <me> or <bt>, never
    while you're Invisible.
    A care row that needs ammo worn (Repair's and Maintenance's oil, Reward's pet
    food) and would go with it first equips it, as v2: the best of what you hold
    in your bag or wardrobes that your main job can wear (the highest level up to
    yours; of equals, the later one the knowledge table lists, its better).
    One that doesn't show after EQUIP_TRIES sends is given up on, so the next row
    can go, until your ammo slot or how many you hold of it changes.
]]--

local can = require('core.can')
local settings = require('core.settings')

local INVISIBLE = 69
local ENGAGED = 1  -- entity status
local EQUIP_WAIT = 3  -- seconds an equip sent is given to show in the ammo slot
local EQUIP_TRIES = 3  -- sends of one item with nothing changed before it's given up on

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

-- The ammo to wear for `a`: the best of what you hold that your main job wears, or nil.
function pet.wearable(a, g)
    local best
    for _, it in ipairs(g.owned and g.owned(a.ammo) or {}) do  -- in a.ammo's order: worst first
        if bit.band(it.jobs, bit.lshift(1, g.main)) ~= 0 and it.level <= g.main_lv
            and not (best and best.level > it.level) then
            best = it
        end
    end
    return best
end

-- `a` now, or the equip of its ammo when that alone stops it; nil when neither
-- can go, and true too while an equip just sent for it has yet to show.
local function use(a, g, cfg, mem, why)
    if can.use(a, g) then return { action = a, why = why } end
    if not a.ammo or can.holds(a.ammo, g.ammo) or not can.use(a, setmetatable({ ammo = a.ammo[1] }, { __index = g })) then
        return nil
    end
    if g.now - (mem.ammo_at or -math.huge) < EQUIP_WAIT then return nil, true end  -- before walking the bags
    local it = pet.wearable(a, g)
    if not it then return nil end
    -- What an equip of it was sent into: the same again means it didn't take.
    local into = ('%d %d %d'):format(it.id, g.ammo or 0, it.count or 0)
    local tried = mem.ammo_tried
    if tried and tried.into == into and tried.n >= EQUIP_TRIES then return nil end
    local english = cfg.ui.japanese and (it.jp or '') == ''
    local name = cfg.ui.japanese and not english and it.jp or it.en
    return { command = ('/equip ammo "%s" %d'):format(name, it.bag), english = english or nil, action = { name = it.en },
             why = ('for %s: %s'):format(a.name, why),
             sent = function (now)
                 mem.ammo_at = now
                 mem.ammo_tried = { into = into, n = tried and tried.into == into and tried.n + 1 or 1 }
             end }
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
