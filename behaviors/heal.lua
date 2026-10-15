--[[
    Healing, by how urgent it is. Every usable heal aimed at every unit it can
    reach is a candidate, covering the units in its area; a band picks who counts
    and how candidates rank. Bands run worst first, and one with nothing usable
    falls through, so a unit out of reach never stalls the rest.
      critical   under heal.critical: a boost first (Divine Seal...), then an aimed
                 save (Martyr), then the danger score over critical units
      danger     under heal.danger: HP% restored per second locked out; holds for
                 a heal nearly off recast
      efficient  under heal.threshold: HP that lands where it's needed, per share of
                 the MP or TP you have; Regen allowed, and counted while it ticks
    The focus member has its own three lines; skipped members count for nothing.
    Design: docs/superpowers/specs/2026-10-15-healing-design.md
]]--

local can = require('core.can')
local observed = require('core.observed')
local settings = require('core.settings')

local heal = {}

local BANDS = { 'critical', 'danger', 'efficient' }
local HOLD_MAX = 15        -- seconds: a heal this close to ready is worth waiting for
local CURE_POWER = 1.25    -- CatsEyeXI's bonus on healing magic, blue magic and waltzes
local GEAR_CAP = 50        -- the server caps cure and waltz potency from gear at +50%
local HEALING, BLUE = 33, 43  -- spell skills
local TICK = 3             -- seconds between Regen ticks
local TP_CAP = 3000        -- TP past this is lost, so a heal spending it is free
local AURORASTORM = { 184, 595 }
local AURAS, STELLAR, GLOOM, DARKNESS = 16, 17, 18, 19
local LIGHTSDAY, DARKSDAY = 6, 7
local EPS = 1e-9

local function any(set, ids)
    for _, id in ipairs(ids or {}) do if set[id] then return true end end
    return false
end

local function healing(a) return a.kind == 'ma' and a.skill == HEALING end  -- Cure, Curaga
local function waltz(a) return (a.tp or 0) > 0 end
local function kind_of(a) return healing(a) and 'healing' or waltz(a) and 'waltz' or nil end

-- The day and weather bonus on healing magic, as expected: the server applies
-- both to one cast in three. Aurorastorm makes your weather Auras, or Stellar
-- Glare over Auras.
function heal.sky(g)
    local w = g.weather
    if any(g.me.buffs, AURORASTORM) then w = (w == AURAS or w == STELLAR) and STELLAR or AURAS end
    return ((w == STELLAR and 0.25 or w == AURAS and 0.1 or 0)
        - (w == DARKNESS and 0.25 or w == GLOOM and 0.1 or 0)
        + (g.day == LIGHTSDAY and 0.1 or g.day == DARKSDAY and -0.1 or 0)) / 3
end

local function gear(a, s)
    return math.min(waltz(a) and s.waltz_potency or s.cure_potency, GEAR_CAP)
end

-- What's up on you multiplies a heal: boosts of its kind (Divine Seal x2,
-- Majesty's potency beside gear's) and, for healing magic, the sky.
local function mult(a, ctx)
    local kind, m = kind_of(a), 1
    for _, b in ipairs(ctx.up) do
        if b.kind == kind then
            local p = gear(a, ctx.s)
            m = m * b.factor * (1 + (p + (b.potency or 0)) / 100) / (1 + p / 100)
        end
    end
    return kind == 'healing' and m * (1 + ctx.sky) or m
end

-- HP one cast restores on each unit it covers, and the multiplier in it; nil
-- when nothing says (no prior, never seen).
local function amount(a, ctx)
    if a.tick then return (a.tick + ctx.s.regen_potency) * math.floor(a.duration / TICK), 1 end
    local m, base = mult(a, ctx), ctx.g.learned[a.kind .. a.id]
    if not base and a.potency then
        local power = (a.kind == 'ma' and (a.skill == HEALING or a.skill == BLUE) or waltz(a)) and CURE_POWER or 1
        base = a.potency * (1 + gear(a, ctx.s) / 100) * power
    end
    return base and base * m, m
end

local function lockout(a)
    return a.kind == 'ma' and (a.cast or 0) + can.SPELL_THROTTLE or can.THROTTLE
end

-- How `a` can go out now: { radius, mp, lockout, via }, via being a JA to fire
-- first. An area boost on you spreads a Cure; in danger, Accession may be worth it.
local function forms(a, ctx, band)
    local g, out = ctx.g, {}
    local f = { radius = a.area > 0 and can.yalms(a.area) or 0, mp = a.mp or 0, lockout = lockout(a) }
    local spreads = healing(a) and a.area == 0
    local b = ctx.area
    if spreads and b and a.tier <= (b.tiers or a.tier) then f.radius, f.mp = b.area, f.mp * b.mp end
    if f.mp <= g.me.mp then out[1] = f end
    b = ctx.accession and ctx.accession.boost
    if b and band ~= 'efficient' and spreads and not ctx.area and a.tier <= b.tiers and a.mp * b.mp <= g.me.mp then
        out[#out + 1] = { radius = b.area, mp = a.mp * b.mp, lockout = f.lockout + can.THROTTLE, via = ctx.accession }
    end
    return out
end

local function centres(a, g)
    if can.self_only(a) or can.at_enemy(a) then return { g.me } end  -- Drain heals you
    local out = {}
    for _, u in ipairs(g.units) do if can.reach(a, u) then out[#out + 1] = u end end
    return out
end

local function dist(a, b)
    if a == b then return 0 end
    if not (a.pos and b.pos) then return math.huge end
    local dx, dy, dz = a.pos[1] - b.pos[1], a.pos[2] - b.pos[2], a.pos[3] - b.pos[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function need(u, efficient)
    return math.max(0, (u.max_hp or u.hp) - u.hp - (efficient and u.hot or 0))
end

local function share(a, f, g)
    if f.mp > 0 then return f.mp / g.me.mp end
    if waltz(a) then return g.me.tp >= TP_CAP and 0 or a.tp / g.me.tp end
    return 0
end

-- One candidate: `a` in form `f` aimed at `centre`. Nil unless it reaches a band member.
local function rate(band, a, f, centre, amt, ctx, members)
    local c = { band = band, a = a, f = f, centre = centre, cover = {}, sum = 0, points = 0, count = 0 }
    for _, u in ipairs(ctx.g.units) do
        if u == centre or f.radius > 0 and u.alive and u.in_zone and dist(centre, u) <= f.radius then
            c.cover[#c.cover + 1] = u
            local useful = amt and not ctx.s.skip[u.name] and math.min(amt, need(u, band == 'efficient')) or 0
            c.sum = c.sum + useful
            if members[u] and (useful > 0 or not amt) then
                c.points = c.points + useful / u.max_hp * 100
                c.count = c.count + 1
                if not c.worst or u.hpp < c.worst.hpp then c.worst = u end
                c.focus = c.focus or u == ctx.focus
            end
        end
    end
    if not c.worst then return nil end
    c.share = share(a, f, ctx.g)
    c.score = band == 'efficient' and c.sum / math.max(c.share, 1e-6) or c.points / f.lockout
    return c
end

-- Higher score; on a tie the cheaper, then the one covering the focus member.
local function better(c, best)
    if not best then return true end
    if math.abs(c.score - best.score) > EPS * math.max(1, best.score) then return c.score > best.score end
    if math.abs(c.share - best.share) > EPS then return c.share < best.share end
    return c.focus and not best.focus
end

-- The best candidate for the band, and the heal kinds that had one. A heal with
-- no amount (Vivacious Pulse) goes only when nothing else can, and never in efficient.
local function best_of(band, ctx, ready, members)
    local best, fallback, kinds = nil, nil, {}
    for _, a in ipairs(ready) do
        if not a.tick or band == 'efficient' then
            local amt, m = amount(a, ctx)
            for _, f in ipairs(forms(a, ctx, band)) do
                for _, centre in ipairs(centres(a, ctx.g)) do
                    local c = not (a.tick and any(centre.buffs, a.status)) and rate(band, a, f, centre, amt, ctx, members)
                    if c then c.mult = m end
                    if c and amt then
                        kinds[kind_of(a) or ''] = true
                        if better(c, best) then best = c end
                    elseif c then
                        fallback = fallback or c
                    end
                end
            end
        end
    end
    return best or (band ~= 'efficient' and fallback or nil), kinds
end

local function why(c)
    local w = c.worst
    return ('%s: %s %d%%%s'):format(c.band, w.name, w.hpp, c.count > 1 and (' +%d'):format(c.count - 1) or '')
end

-- The candidate as an intent. Sending it tells core/observed.lua what to expect,
-- so the real HP restored can be learned and a Regen counted while it ticks.
local function intent(c, ctx)
    if c.f.via then return { action = c.f.via, why = ('%s, for %s'):format(why(c), c.a.name) } end
    local a, s, need_at = c.a, ctx.s, {}
    for _, u in ipairs(c.cover) do need_at[u.sid] = need(u, false) end
    return { action = a, target = c.centre, why = why(c), sent = function ()
        observed.sent(a.kind .. a.id, { need = need_at, mult = c.mult,
            per_tick = a.tick and a.tick + s.regen_potency, seconds = a.duration })
    end }
end

local function lines(u, ctx)
    local s = ctx.s
    if u == ctx.focus then return s.focus_critical, s.focus_danger, s.focus_threshold end
    return s.critical, s.danger, s.threshold
end

-- The band's members as a set and worst first. Danger includes critical; efficient
-- starts at the danger line and leaves out whoever your ticking Regen will cover.
local function members_of(band, ctx)
    local set, list = {}, {}
    for _, u in ipairs(ctx.g.units) do
        if u.alive and u.in_zone and u.max_hp and not ctx.s.skip[u.name] then
            local critical, danger, start = lines(u, ctx)
            local inside
            if band == 'critical' then inside = u.hpp < critical
            elseif band == 'danger' then inside = u.hpp < danger
            else inside = u.hpp >= danger and u.hpp < start and (u.hp + u.hot) * 100 < start * u.max_hp end
            if inside then set[u] = true; list[#list + 1] = u end
        end
    end
    table.sort(list, function (a, b) return a.hpp < b.hpp end)
    return set, list
end

-- Critical, before the heal: a boost for the kind of heal about to land, an aimed
-- save on the worst member, then the other emergencies when a heal will follow.
local function emergency(ctx, list, best, kinds, emergencies)
    local g = ctx.g
    for _, e in ipairs(emergencies) do
        if e.boost and e.boost.factor > 1 and kinds[e.boost.kind] and can.use(e, g) then
            return { action = e, why = ('critical: %s %d%%'):format(list[1].name, list[1].hpp) }
        end
    end
    for _, u in ipairs(list) do
        for _, e in ipairs(emergencies) do
            if not e.boost and not can.self_only(e) and u.kind ~= 'self' and can.reach(e, u) and can.use(e, g) then
                return { action = e, target = u, why = ('critical: %s %d%%'):format(u.name, u.hpp) }
            end
        end
    end
    if not best then return nil end
    for _, e in ipairs(emergencies) do
        if not e.boost and can.self_only(e) and can.use(e, g) then
            return { action = e, why = ('critical: %s %d%%'):format(list[1].name, list[1].hpp) }
        end
    end
end

local function focus_of(g, s)
    if s.focus == '' then return nil end
    for _, u in ipairs(g.units) do if u.name:lower() == s.focus:lower() then return u end end
end

-- What's up on you (boosts by status) and what healing may fire (Accession).
local function context(g, cat, cfg)
    local ctx = { g = g, s = cfg.heal, up = {}, sky = heal.sky(g), focus = focus_of(g, cfg.heal) }
    for _, a in ipairs(cat) do
        if a.boost and any(g.me.buffs, a.status) then
            ctx.up[#ctx.up + 1] = a.boost
            ctx.factor_up = ctx.factor_up or a.boost.factor > 1
            ctx.area = ctx.area or a.boost.area and a.boost
        end
    end
    for _, e in ipairs(settings.enabled(cat, cfg, 'emergency')) do
        if e.boost and e.boost.area and not any(g.me.buffs, e.status) and can.use(e, g) then ctx.accession = e end
    end
    return ctx
end

function heal.want(g, cat, cfg)
    local ctx = context(g, cat, cfg)
    local ready, waiting, regen = {}, {}, nil
    for _, a in ipairs(settings.enabled(cat, cfg, 'heal')) do
        if a.tick then  -- only the best Regen you know: per MP, Regen I would trickle out first
            if a.tick > 0 and (not regen or a.tier > regen.tier) then regen = a end
        else
            local ok, _, wait = can.use(a, g)
            if ok then ready[#ready + 1] = a elseif wait and wait <= HOLD_MAX then waiting[#waiting + 1] = a end
        end
    end
    if regen and can.use(regen, g) then ready[#ready + 1] = regen end
    local emergencies = settings.enabled(cat, cfg, 'emergency')

    for _, band in ipairs(BANDS) do
        local members, list = members_of(band, ctx)
        if list[1] then
            local best, kinds = best_of(band, ctx, ready, members)
            local e = band == 'critical' and not ctx.factor_up and emergency(ctx, list, best, kinds, emergencies)
            if e then return e end
            if best then return intent(best, ctx) end
            if band == 'danger' then
                for _, u in ipairs(list) do
                    for _, a in ipairs(waiting) do if can.reach(a, u) then return { hold = true } end end
                end
            end
        end
    end
end

return heal
