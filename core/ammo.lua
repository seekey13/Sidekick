--[[
    Ammo an action needs worn: a pet's oil or food (Repair, Maintenance, Reward),
    a Ninja's shuriken (Sange). When that alone stops the action, the best you
    hold in your bag or wardrobes that your main job can wear (the highest level
    up to yours; of equals, the later the knowledge table lists) is equipped
    first. One that doesn't show after TRIES sends is given up on, so what comes
    next can go, until your ammo slot or how many you hold of it changes. Pet care
    and buff rows share one ammo slot, so they share the wait (mem.ammo_at); tries
    count per action.
]]--

local can = require('core.can')
local util = require('core.util')

local ammo = {}

ammo.WAIT = 3   -- seconds an equip sent is given to show in the ammo slot
ammo.TRIES = 3  -- sends of one item with nothing changed before it's given up on

-- The ammo to wear for `a`: the best of what you hold that your main job wears, or nil.
function ammo.wearable(a, g)
    local best
    for _, it in ipairs(g.owned and g.owned(a.ammo) or {}) do  -- in a.ammo's order: worst first
        if bit.band(it.jobs, bit.lshift(1, g.main)) ~= 0 and it.level <= g.main_lv
            and not (best and best.level > it.level) then
            best = it
        end
    end
    return best
end

-- The equip of `a`'s ammo when that alone stops it, as an intent (`why` its
-- reason); nil when it can't help, and true too while an equip just sent has
-- yet to show.
function ammo.equip(a, g, cfg, mem, why)
    if not a.ammo or util.contains(a.ammo, g.ammo) or not can.use(a, util.overlay(g, { ammo = a.ammo[1] })) then
        return nil
    end
    if g.now - (mem.ammo_at or -math.huge) < ammo.WAIT then return nil, true end  -- before walking the bags
    local it = ammo.wearable(a, g)
    if not it then return nil end
    -- What an equip of it was sent into: the same again means it didn't take.
    local into = ('%d %d %d'):format(it.id, g.ammo or 0, it.count or 0)
    mem.ammo_tried = mem.ammo_tried or {}
    local tried = mem.ammo_tried[a.name]
    if tried and tried.into == into and tried.n >= ammo.TRIES then return nil end
    local name, english = util.spelled(it.en, it.jp, cfg.ui.japanese)
    return { command = ('/equip ammo "%s" %d'):format(name, it.bag), english = english or nil, action = { name = it.en },
             why = ('for %s: %s'):format(a.name, why),
             sent = function (now)
                 mem.ammo_at = now
                 mem.ammo_tried[a.name] = { into = into, n = tried and tried.into == into and tried.n + 1 or 1 }
             end }
end

return ammo
