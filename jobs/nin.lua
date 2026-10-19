--[[
    Ninja (v2's ninja.lua): the tools ninjutsu spend, and recasting Utsusemi at
    its last shadow. Utsusemi, Tonko and Monomi each take one of their own tool
    (knowledge's `tool`: Shihei, Shinobi-tabi, Sanjaku-tenugui) from your
    inventory, never a wardrobe; on a NIN main job a Shikanofuda stands in for
    any of them (LSB's battleutils::HasNinjaTool). With neither the server
    refuses the cast, so the row waits ('no tools') and shows how many you hold.
    Sange's shuriken is ammo, equipped like a pet's oil (core/ammo.lua).
    With buff.one_shadow (v2's Cast with 1 Shadow, off by default) Utsusemi is
    recast while its last shadow is up, not only once it's gone. For Ichi that
    shadow is cancelled engine.CANCEL_AFTER seconds into the cast, while it's still
    casting (one cut short before then keeps it), so the new ones land: LSB
    replaces shadows by tier, so Ichi is refused over Ni's while Ni always lands,
    and needs no cancel (none is sent for it, so it's never left without one).
]]--

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

return nin
