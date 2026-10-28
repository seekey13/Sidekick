--[[
    Ninja: the tools ninjutsu spend, and recasting Utsusemi at its last shadow.
    Utsusemi, Tonko and Monomi each take one of their own tool (knowledge's `tool`)
    from your inventory, never a wardrobe; on a NIN main job a Shikanofuda stands in
    for any of them (LSB's battleutils::HasNinjaTool). With neither the server
    refuses the cast, so the row waits ('no tools': nin.tools, for can.tools). With
    buff.one_shadow Utsusemi is recast while its last shadow is up (nin.renew, for
    behaviors/buff.lua); for Ichi that shadow is cancelled engine.CANCEL_AFTER
    seconds into the cast so the new ones land, since LSB replaces shadows by tier:
    it refuses Ichi over Ni's, while Ni always lands.
]]--

local can = require('core.can')

local nin = {}

nin.JOB = 13
nin.SHIKANOFUDA = 2972

-- How many casts of `a` the tools in your inventory pay for.
function nin.tools(a, g)
    local items = g.items or {}
    return (items[a.tool] or 0) + (g.main == nin.JOB and items[nin.SHIKANOFUDA] or 0)
end

-- `a`'s statuses without its last shadow (Copy Image, one left) when it's to be
-- recast at one shadow, else nil.
function nin.shadows(a, cfg)
    if not (a.last_shadow and cfg.buff.one_shadow) then return nil end
    local out = {}
    for _, id in ipairs(a.status) do
        if id ~= a.last_shadow then out[#out + 1] = id end
    end
    return out
end

-- With buff.one_shadow, Utsusemi `a` at its last shadow alone is due again: why,
-- and that shadow to cancel into the cast for Ichi.
function nin.renew(a, g, cfg)
    local shadows = nin.shadows(a, cfg)
    if not (shadows and g.me.buffs[a.last_shadow] and can.lacks(a, g.me, shadows)) then return nil end
    return '%s: one shadow left', a.tier == 1 and a.last_shadow or nil  -- Ichi alone needs it gone
end

return nin
