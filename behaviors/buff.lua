--[[
    Keep the buffs you turned on up on the targets you picked. A row's action is its
    picked tier, else the best tier you can cast now; a pick_one group (bar-elements,
    enspells...) needs a pick. A row's targets are party and alliance slots (0-17)
    and tracked players' names; a self-only buff goes on you, and an area self-cast
    (Protectra) is recast when anyone in your party near you lacks it. A status that
    can't be read (Boost) is recast whenever it's off recast.

    With buff.hold_aoe on, an area spell waits while a player in your party who
    lacks it is out of its reach (trusts follow, so never hold it), and mem.gather
    says what waits on whom: the engine asks the party to gather when someone near
    lacks it too.

    A row's modifiers (stratagems, Embolden) go with its spell, fired first by the
    engine. Accession instead spreads the spell from you to the row's targets in
    your party near you, at twice the MP, and is held for the group like an area
    spell; Diffusion likewise, but only while someone but you lacks it. With Hold on
    (rows[key].hold) a row waits while any of its modifiers can't go with it. With
    heal.reserve on, buff rows never spend the last stratagem charge.

    Stages: buff.first runs the rows whose action goes `first` (Light Arts,
    Addendum: White) ahead of healing, unless a member is under their critical line;
    buff.want every row, but never one that would make you Invisible (it may still
    go on others); buff.last just those, on you, after every other behavior, since
    any action breaks it. Your own Invisible also waits while other work is
    pending, OTHERS_FIRST seconds at most.
]]--

local ammo = require('core.ammo')
local can = require('core.can')
local heal = require('behaviors.heal')
local nin = require('jobs.nin')
local sch = require('jobs.sch')
local settings = require('core.settings')
local status = require('core.status')
local util = require('core.util')

local buff = {}

local AREA_RADIUS = 10  -- yalms around you
local OTHERS_FIRST = 15  -- seconds your own Invisible waits at most for other work pending
local lacks = can.lacks

-- Each row's action, best tier first, highest priority rows first.
local function chosen(cat, cfg, g)
    local by_key, keys = {}, {}
    for _, a in ipairs(settings.enabled(cat, cfg, 'buff')) do
        local key = settings.key(a)
        if not by_key[key] then by_key[key] = {}; keys[#keys + 1] = key end
        table.insert(by_key[key], a)
    end
    local out = {}
    for _, key in ipairs(keys) do
        local list = by_key[key]
        local row = settings.row(cfg, list[1])
        table.sort(list, util.by_level)
        local pick
        for _, a in ipairs(list) do
            if row.pick == a.name or (not row.pick and not a.pick_one and can.use(a, g)) then pick = a; break end
        end
        -- None can go now: the best, when it needs ammo, so that can be equipped for it.
        if not (pick or row.pick or list[1].pick_one) and list[1].ammo then pick = list[1] end
        if pick then
            out[#out + 1] = { action = pick, targets = row.targets or { [0] = true }, mods = settings.mods(cat, cfg, pick),
                              hold = row.hold == true }
        end
    end
    table.sort(out, function (x, y) return x.action.priority > y.action.priority end)
    return out
end

-- For an area self-cast: who near you lacks it (the first, and how many), and,
-- holding for the group, the first player in your party who lacks it out of its
-- reach (`radius` yalms, AREA_RADIUS when nil). `wanted` (a row's targets)
-- narrows who counts. Corsair's rolls are held with it too (jobs/cor.lua).
function buff.area(a, g, hold, wanted, radius)
    local near, count, away = nil, 0, nil
    for _, u in ipairs(g.units) do
        local here = can.near(u, radius or AREA_RADIUS)
        if (u.kind == 'self' or can.in_party(u) and u.alive and u.in_zone) and lacks(a, u)
            and (not wanted or wanted[u.slot]) then
            if here then near, count = near or u, count + 1
            elseif hold and u.kind == 'party' and not away then away = u end
        end
    end
    return near, away, count
end

-- Holding `a` for `away` to gather: ask the party only when someone near needs
-- it too; one who stays away (a puller) is waited for silently.
function buff.wait_for(mem, a, near, away)
    if not mem.gather or (near and not mem.gather.ask) then
        mem.gather = { action = a, who = away, ask = near ~= nil }
    end
end

-- A row's Accession (or Diffusion), split from its other modifiers (those it
-- may spend), when it can spread `a` now: up on you already, or spare and
-- usable with the MP for the spell at its spread cost.
local function spreading(c, g, cfg)
    local others, acc = {}, nil
    for _, m in ipairs(c.mods) do
        if m.spreads then acc = m elseif sch.spare(m, g, cfg) then others[#others + 1] = m end
    end
    local a = c.action
    if acc and not can.reach(a, g.me) then acc = nil end
    if acc and not can.any(g.me.buffs, acc.status) and not (sch.spare(acc, g, cfg) and can.use(acc, g)
        and (a.mp or 0) * acc.spreads.mp <= g.me.mp) then acc = nil end
    return acc, others
end

-- With its Hold on, the modifier a row waits for, or nil: one not on you that
-- isn't spare and usable, or more stratagems to fire than charges to spend
-- (as v2). Accession counts only when the spell would spread (`spreads`); `acc`
-- is it when it can.
local function held(c, acc, spreads, g, cfg)
    if not c.hold then return nil end
    local charges, first = 0, nil
    for _, m in ipairs(c.mods) do
        local up = can.any(g.me.buffs, m.status)
        if m.spreads then
            if spreads and not acc then return m end
        elseif not up and not (sch.spare(m, g, cfg) and can.use(m, g)) then
            return m
        end
        if not up and sch.POOL:spends(m) and (spreads or not m.spreads) then
            charges, first = charges + 1, first or m
        end
    end
    local spare = g.stratagems and g.stratagems - (cfg.heal.reserve and 1 or 0)
    if spare and charges > spare then return first end
end

-- Whether `a` makes whoever it lands on Invisible.
local function veils(a) return util.contains(a.status or {}, status.INVISIBLE) end

-- Whether a buff that makes you Invisible and is due on you gives all of `a`'s
-- statuses too (Spectral Jig gives Sneak): `a` then needn't go on you first.
local function covered(a, list, g)
    if veils(a) or not a.status then return false end
    for _, c in ipairs(list) do
        local v = c.action
        if veils(v) and can.self_only(v) and lacks(v, g.me) then
            local all = true
            for _, id in ipairs(a.status) do all = all and util.contains(v.status, id) end
            if all then return true end
        end
    end
    return false
end

-- The first row's intent that is due, at `stage`: 'first', the rows that go
-- first; 'want', every row, but never what makes you Invisible; 'last', just that.
local function due(g, cat, cfg, mem, stage)
    local invisible = g.me.buffs[status.INVISIBLE]
    local hold = cfg.buff.hold_aoe
    local rows = {}
    local list = chosen(cat, cfg, g)
    for _, c in ipairs(list) do
        local veil = veils(c.action)
        if stage == 'first' and c.action.first or stage == 'want' or stage == 'last' and veil then
            c.on_me = (not veil or stage == 'last') and not covered(c.action, list, g)  -- may go on you
            c.on_others = stage ~= 'last'
            rows[#rows + 1] = c
        end
    end
    for _, c in ipairs(rows) do
        local a = c.action
        -- One only its ammo stops (Sange's shuriken) has it equipped first (core/ammo.lua).
        if (a.travel or not invisible) and c.on_me and a.ammo and can.self_only(a) and lacks(a, g.me) and not can.use(a, g) then
            local intent = ammo.equip(a, g, cfg, mem, ('%s lacks it'):format(g.me.name))
            if intent then return intent end
        end
        if (a.travel or not invisible) and can.use(a, g) and sch.spare(a, g, cfg) then
            local acc, mods = spreading(c, g, cfg)
            if not c.on_me then acc = nil end  -- a spread lands on you too
            -- Accession on, and someone near you it would reach lacks it (for a
            -- self-only spell, someone but you: on you alone it needs no spread).
            local spreads = false
            for _, m in ipairs(c.hold and c.mods or {}) do
                if m.spreads and can.reach(a, g.me) then
                    local self_only = can.self_only(a)
                    local _, _, n = buff.area(a, g, false, not self_only and c.targets or nil)
                    spreads = n - (self_only and lacks(a, g.me) and 1 or 0) >= 1
                end
            end
            local wait = held(c, acc, spreads, g, cfg)
            if wait then
                mem.waiting = mem.waiting or { action = a, mod = wait }
            else
                local near, away, count
                if acc then near, away, count = buff.area(a, g, hold, not can.self_only(a) and c.targets or nil) end
                -- Diffusion only for someone but you: on you alone the spell goes as it is.
                if acc and acc.spreads.others and not away and count - (lacks(a, g.me) and 1 or 0) < 1 then acc = nil end
                if away then
                    buff.wait_for(mem, a, near, away)
                elseif acc and count >= 1 then
                    table.insert(mods, acc)
                    local why = count > 1 and ('%s +%d lack it'):format(near.name, count - 1) or ('%s lacks it'):format(near.name)
                    return { action = a, mods = mods, why = why }
                elseif can.self_only(a) and a.area > 0 then
                    near, away = buff.area(a, g, hold and a.kind == 'ma')
                    if away then
                        buff.wait_for(mem, a, near, away)
                    elseif near then
                        return { action = a, mods = mods, why = ('%s lacks it'):format(near.name) }
                    end
                elseif can.self_only(a) then
                    local shadows = nin.shadows(a, cfg)
                    if c.on_me and lacks(a, g.me, shadows) then
                        local up = shadows and g.me.buffs[a.last_shadow]
                        local last = up and a.tier == 1 and a.last_shadow or nil  -- Ichi alone needs it gone
                        local why = up and '%s: one shadow left' or '%s lacks it'
                        return { action = a, mods = mods, why = why:format(g.me.name), cancel = last }
                    end
                else
                    for _, u in ipairs(g.units) do
                        local mine = u.kind == 'self'
                        if (mine and c.on_me or not mine and c.on_others) and c.targets[u.slot or u.name]
                            and can.reach(a, u) and lacks(a, u) then
                            return { action = a, target = u, mods = mods, why = u.name }
                        end
                    end
                end
            end
        end
    end
end

function buff.first(g, cat, cfg, mem)
    if cfg.heal.on and heal.critical(g, cfg) then return nil end
    return due(g, cat, cfg, mem, 'first')
end
function buff.want(g, cat, cfg, mem) return due(g, cat, cfg, mem, 'want') end

-- Whether other work is pending that your own Invisible would shut out or be
-- broken by: a buff held this decision (for the group, for its modifier), a step
-- due soon (mem.busy_until: a Corsair's Double-Up), or a buff row's spell someone
-- it is for lacks, off recast within OTHERS_FIRST seconds.
local function pending(g, cat, cfg, mem)
    if mem.gather or mem.waiting or g.now < (mem.busy_until or -math.huge) then return true end
    for _, a in ipairs(settings.enabled(cat, cfg, 'buff')) do
        local row = settings.row(cfg, a)
        local _, _, wait = can.use(a, g)
        if wait and wait <= OTHERS_FIRST and (row.pick or a.name) == a.name and not (a.pick_one and not row.pick) then
            local targets, self_only = row.targets or { [0] = true }, can.self_only(a)
            for _, u in ipairs(g.units) do
                local mine = u.kind == 'self'
                local wanted
                if self_only then
                    wanted = mine or a.area > 0 and can.in_party(u) and u.alive and u.in_zone and can.near(u, AREA_RADIUS)
                else
                    wanted = targets[u.slot or u.name] and can.reach(a, u)
                end
                if wanted and not (mine and veils(a)) and lacks(a, u) then return true end
            end
        end
    end
    return false
end

function buff.last(g, cat, cfg, mem)
    local intent = due(g, cat, cfg, mem, 'last')
    if intent and pending(g, cat, cfg, mem) then
        mem.veil_held = mem.veil_held or g.now
        if g.now - mem.veil_held < OTHERS_FIRST then return nil end
    elseif not intent then
        mem.veil_held = nil
    end
    return intent
end

return buff
