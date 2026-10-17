--[[
    Geomancer: the luopan. There is one at a time, from a GEO main job only, and
    the snapshot's pet is it (core/game.lua). Under Geomancy:
      - the Geo row's luopan goes on the first of its targets (in slot order) in
        reach who lacks its aura, while the slot is free. It stays where it lands,
        so it waits while they move. Who it went on is remembered: once they're
        further than geo.distance from it (or gone), Full Circle recalls it, and
        it goes down again on the first of the row's targets who lacks it (as v2).
      - the Geo debuff row's luopan goes on your battle target in combat (waiting
        while it moves), taking the slot from any other luopan with Full Circle.
        Only while the debuff could follow (in range, off recast, not
        silenced). Once combat is over it's recalled after geo.linger seconds, so a new
        battle target in that time keeps it (as v2).
      - Blaze of Glory goes just before either, as a modifier (core/engine.lua).
      - Entrust, with a member and an Indi- spell picked, puts that Indi- on them
        whenever they lack its aura within ENTRUST_RANGE (Entrust first, as a modifier).
    Radial Arcana spends the luopan for MP under your Recover MP line (geo.arcana,
    for behaviors/recover.lua): one that's cheap, nearly spent or put down for
    it, once you're within RADIUS of it. A dear one is recalled first (Full Circle
    gives MP back) and a Geo-Voidance put down on you to spend instead, as v2;
    begun, that sequence keeps the slot for SEQUENCE seconds, whatever your MP does.
    Nothing goes while you're Invisible.
]]--

local can = require('core.can')
local settings = require('core.settings')

local geo = {}

geo.JOB = 21
-- The aura statuses an Indi- or Geo- spell shows (core/knowledge.lua), by the name after the dash.
geo.AURAS = { Regen = 539, Refresh = 541, STR = 542, DEX = 543, VIT = 544, AGI = 545, INT = 546, MND = 547,
              CHR = 548, Fury = 549, Barrier = 550, Acumen = 551, Fend = 552, Precision = 553, Voidance = 554,
              Focus = 555, Attunement = 556, Haste = 580 }
geo.DEBUFFS = { 'Poison', 'Frailty', 'Slow', 'Torpor', 'Slip', 'Languor', 'Paralysis', 'Vex' }
geo.COLURE = 612  -- "Colure Active": what an offensive Indi- shows on you

local INVISIBLE = 69
local LAND = 8             -- seconds a luopan sent may take to appear
local ENTRUST_RANGE = 20   -- yalms (v2)
local RADIUS = 10          -- yalms from the luopan Radial Arcana reaches (v2; Widened Compass ignored)
local KEEP_MP = 75         -- a luopan dearer than this is recalled rather than spent...
local SPENT_HP = 5         -- ...unless it's down to this HP %
local SEQUENCE = 20        -- seconds a Radial Arcana sequence keeps the slot once begun
local SPENT = 10           -- seconds after Radial Arcana before another begins (its recast shows late)

-- mem.geo: { luopan = { action, sid = who it went on, debuff, spare, at, up, since,
-- spent = Radial Arcana sent on it } or nil, arcana = when the sequence lets the slot
-- go, spent = when Radial Arcana went }. A luopan out that wasn't sent here (a
-- reload, or one put down while nothing decided: the pet's `since` is newer) is
-- known only as up.
local function state(g, mem)
    local st = mem.geo or {}
    mem.geo = st
    local l, p = st.luopan, g.pet
    if p and p.hpp > 0 then
        if not l or l.up and l.since ~= p.since then l = { at = g.now }; st.luopan = l end
        if not l.up then l.up, l.since = true, p.since end
    elseif l and (l.up or g.now - l.at > LAND) then
        st.luopan = nil
    end
    if st.arcana and g.now >= st.arcana then st.arcana = nil end
    return st
end

-- Whether Geo-Voidance `v` could go down once the slot is free (MP and recast may come back).
local function spare_ok(v, g)
    local ok, why = can.use(v, g)
    return ok or why == 'MP' or why:match('^recast') ~= nil
end

local function lacks(a, u) return not can.any(u.buffs, a.status) end

-- The luopan ability named `name` when its row is on.
local function on(cat, cfg, name)
    for _, a in ipairs(cat) do
        if a.name == name and a.role == 'geo' and settings.row(cfg, a).on then return a end
    end
end

-- A luopan row's picked spell and the row, when it's on.
local function picked(cat, cfg, key)
    for _, a in ipairs(cat) do
        if a.pick_one == key and a.role == 'geo' then
            local row = settings.row(cfg, a)
            if row.on and row.pick == a.name then return a, row end
        end
    end
end

-- Remember a luopan once it's sent: what, on whom (nil: the battle target), and why.
local function put(st, a, u, kind)
    return function (now)
        st.luopan = { action = a, sid = u and u.sid, debuff = kind == 'debuff' or nil, spare = kind == 'spare' or nil, at = now }
    end
end

-- Who the luopan is for: who it went on (nil once they're gone), else (not sent here)
-- the first of the row's targets.
local function holder(l, g, targets)
    for _, u in ipairs(g.units) do
        if l.sid then
            if u.sid == l.sid then return u end
        elseif targets and targets[u.slot] and u.in_zone then
            return u
        end
    end
end

-- The Geo row's luopan on the first of its targets who lacks it.
local function place(g, cat, cfg, st, mods)
    local a, row = picked(cat, cfg, 'geo')
    if not (a and can.use(a, g)) then return nil end
    local targets = row.targets or { [0] = true }
    for _, u in ipairs(g.units) do
        if targets[u.slot] and can.reach(a, u) and lacks(a, u) then
            if u.moving then return nil end
            return { action = a, target = u, mods = mods, why = u.name, sent = put(st, a, u) }
        end
    end
end

-- Whether the Radial Arcana row is on.
local function arcana_on(cat, cfg)
    for _, a in ipairs(cat) do
        if a.luopan == 'spend' and settings.row(cfg, a).on then return true end
    end
    return false
end

local function entrust(g, cat, cfg)
    local e, name = on(cat, cfg, 'Entrust'), cfg.geo.entrust:lower()
    if not e or name == '' or not (can.any(g.me.buffs, e.status) or can.use(e, g)) then return nil end
    local indi
    for _, a in ipairs(cat) do
        if a.pick_one == 'indi' and a.name == cfg.geo.entrust_spell then indi = a end
    end
    if not (indi and can.use(indi, g)) then return nil end
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and can.in_party(u) and u.name:lower() == name then
            if u.alive and u.in_zone and (u.dist or math.huge) <= ENTRUST_RANGE and lacks(indi, u) then
                return { action = indi, target = u, mods = { e }, why = ('%s (Entrust)'):format(u.name) }
            end
            return nil
        end
    end
end

function geo.want(g, cat, cfg, mem)
    if g.main ~= geo.JOB or g.me.buffs[INVISIBLE] then return nil end
    local st = state(g, mem)
    if st.arcana and not (cfg.recover.on and arcana_on(cat, cfg)) then st.arcana = nil end
    if st.arcana then return nil end  -- the slot is Radial Arcana's (geo.arcana)
    local l, p, bt = st.luopan, g.pet, g.bt
    if l and l.spent then return entrust(g, cat, cfg) end  -- going: Radial Arcana took it
    local fc, blaze = on(cat, cfg, 'Full Circle'), on(cat, cfg, 'Blaze of Glory')
    local function recall(why)
        if fc and can.use(fc, g) then return { action = fc, why = why } end
    end
    local mods = blaze and { blaze } or nil
    local up = l and l.up
    local fighting = bt and bt.mob and bt.hpp > 0
    local debuff = picked(cat, cfg, 'geo_debuff')
    local intent
    if up and l.debuff and not fighting then
        if g.now - (g.combat_at or -math.huge) >= cfg.geo.linger then intent = recall('combat over') end
    elseif debuff and fighting then
        local ok, why = can.use(debuff, g)
        local could = not bt.moving and (ok or why == 'MP')  -- it could go once the slot is free
        if up and not l.debuff then
            if could then intent = recall('for ' .. debuff.name) end
        elseif not l and not bt.moving and can.use(debuff, g) then
            intent = { action = debuff, mods = mods, why = bt.name, sent = put(st, debuff, nil, 'debuff') }
        end
    elseif up and not l.debuff then
        local a, row = picked(cat, cfg, 'geo')
        local h = holder(l, g, row and (row.targets or { [0] = true }))
        local d = h and can.dist(h, p)
        if l.spare and a then
            intent = recall('Radial Arcana passed it up')  -- the sequence ran out: free the slot for the Geo row
        elseif l.sid and not h then
            intent = recall('who it went on is gone')
        elseif d and d > cfg.geo.distance then
            intent = recall(d < math.huge and ('%s %.1fy from it'):format(h.name, d) or (h.name .. ' out of sight'))
        end
    elseif not l then
        intent = place(g, cat, cfg, st, mods)
    end
    return intent or entrust(g, cat, cfg)
end

-- Radial Arcana `a` (a recover row) for behaviors/recover.lua: what to send for it now, or nil.
function geo.arcana(a, g, cat, cfg, mem)
    if g.me.buffs[INVISIBLE] then return nil end
    local st = state(g, mem)
    local ok, why = can.use(a, g)
    if not st.arcana then
        local ready = ok or why == 'no pet' and g.recast(a) == 0
        if not ready or g.me.mpp >= cfg.recover.mp or g.now - (st.spent or -math.huge) < SPENT then return nil end
    end
    local l, p = st.luopan, g.pet
    local function arm(now) st.arcana = now + SEQUENCE end
    local voidance
    for _, v in ipairs(cat) do if v.name == 'Geo-Voidance' then voidance = v end end
    if l and l.spent then return nil end
    if l and l.up then
        local spendable = l.spare or l.action and (l.action.mp or 0) <= KEEP_MP or p.hpp <= SPENT_HP
        if spendable and can.dist(g.me, p) <= RADIUS then
            if not ok then return nil end
            return { action = a, why = ('MP %d%%'):format(g.me.mpp),
                     sent = function (now) st.spent, st.arcana, l.spent = now, nil, true end }
        end
        -- Recalled only when a spare can follow it.
        local fc = cfg.geo.on and voidance and spare_ok(voidance, g) and on(cat, cfg, 'Full Circle')
        if fc and can.use(fc, g) then return { action = fc, why = 'to put down one for Radial Arcana', sent = arm } end
    elseif not l and cfg.geo.on and voidance and can.use(voidance, g) then
        local spare = put(st, voidance, g.me, 'spare')
        return { action = voidance, why = 'for Radial Arcana', sent = function (now) arm(now); spare(now) end }
    end
end

return geo
