--[[
    Healing, by how urgent it is. Every usable heal aimed at every unit it can
    reach is a candidate, covering the units in its area; a band picks who counts
    and how candidates rank. Bands run worst first, and one with nothing usable
    falls through, so a unit out of reach never stalls the rest.
      critical   under heal.critical: a boost first (Divine Seal...), then an aimed
                 save (Martyr), then the danger score over critical units
      danger     under heal.danger: HP% restored per second locked out; holds for
                 a heal nearly off recast
      efficient  from the danger line to full HP: HP that lands where it's needed, per
                 share of the MP or TP you have; Regen allowed, and counted while it ticks;
                 never a Ready move, whose charges are kept for the pet's attacks
    The focus member has its own two lines; skipped members count for nothing,
    and so do the alliance's other parties unless heal.alliance is on.
    An area heal lands on the target's party alone, so each party is scored on
    its own: one centred on you or a member covers your party, a Cure aimed at
    someone in another party and spread by Majesty or Accession covers theirs.
    A tracked player is healed like a member, by a heal aimed at them; their
    party is unknown, so a spread Cure counts them alone, and Accession is
    never fired for them.
]]--

local can = require('core.can')
local dnc = require('jobs.dnc')
local observed = require('core.observed')
local settings = require('core.settings')

local heal = {}

local BANDS = { 'critical', 'danger', 'efficient' }
local HOLD_MAX = 15        -- seconds: a heal this close to ready is worth waiting for
local CURE_POWER = 1.25    -- CatsEyeXI's bonus on healing magic, blue magic and waltzes
local GEAR_CAP = 50        -- the server caps cure and waltz potency from gear at +50%
local HEALING, BLUE = 33, 43  -- spell skills
local LIGHT = 6            -- element: the day and weather bonus is on light heals only
local TP_CAP = 3000        -- TP past this is lost, so a heal spending it is free
local AURORASTORM = { 184, 595 }
local REGENS = { 42, 539 } -- Regen, and the GEO aura
local THEIRS = 125         -- HP taken as still to come from a Regen not yours: a whole Regen I
local AURAS, STELLAR, GLOOM, DARKNESS = 16, 17, 18, 19
local LIGHTSDAY, DARKSDAY = 6, 7
local EPS = 1e-9
local any = can.any

local function healing(a) return a.kind == 'ma' and a.skill == HEALING end  -- Cure, Curaga
local function cure(a) return healing(a) or a.kind == 'ma' and a.skill == BLUE end  -- what Cure Potency boosts
local function waltz(a) return (a.tp or 0) > 0 end

-- Whether boost `b` raises heal `a`: 'healing' Cure and Curaga, 'cure' those and
-- blue magic cures (the server's getCureFinal: Divine Seal, Majesty), 'waltz'.
local function boosts(b, a)
    return b.kind == 'healing' and healing(a) or b.kind == 'cure' and cure(a) or b.kind == 'waltz' and waltz(a)
end

-- The day and weather bonus on a light cure, as expected: the server applies
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
    return math.min(waltz(a) and s.waltz_potency or cure(a) and s.cure_potency or 0, GEAR_CAP)
end

-- What's up on you multiplies a heal: boosts of its kind (Divine Seal x2,
-- Majesty's potency beside gear's) and, for a light cure, the sky.
local function mult(a, ctx)
    local m = 1
    for _, b in ipairs(ctx.up) do
        if boosts(b, a) then
            local p = gear(a, ctx.s)
            m = m * b.factor * (1 + (p + (b.potency or 0)) / 100) / (1 + p / 100)
        end
    end
    return cure(a) and a.element == LIGHT and m * (1 + ctx.sky) or m
end

-- HP one cast restores on each unit it covers, and the multiplier in it; nil
-- when nothing says (no prior, never seen).
local function amount(a, ctx)
    if a.tick then return (a.tick + ctx.s.regen_potency) * math.floor(a.duration / observed.TICK), 1 end
    local m, base = mult(a, ctx), ctx.g.learned[observed.key(a)]
    if not base and a.potency then
        local power = (cure(a) or waltz(a)) and CURE_POWER or 1
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

-- A pet's area move (Healing Ruby II, Wild Carrot, Mending Halation) goes off around the pet.
local function around_pet(a) return a.pet and a.area > 0 end

local function centres(a, g)
    if around_pet(a) then return { g.pet } end
    if can.self_only(a) or can.at_enemy(a) then return { g.me } end  -- Drain heals you
    local out = {}
    for _, u in ipairs(g.units) do if can.reach(a, u) then out[#out + 1] = u end end
    return out
end

-- HP on its way from a Regen: yours as tracked (u.hot, nil when not yours), anyone else's as THEIRS.
-- ponytail: their Regen's time left is unknown; note when the status appeared if THEIRS misjudges
local function pending(u)
    return u.hot or any(u.buffs, REGENS) and THEIRS or 0
end

local function need(u, efficient)
    return math.max(0, (u.max_hp or u.hp) - u.hp - (efficient and pending(u) or 0))
end

local function share(a, f, g)
    if f.mp > 0 then return f.mp / g.me.mp end
    if waltz(a) then
        local tp = dnc.tp(a, g)
        return (tp == 0 or g.me.tp >= TP_CAP) and 0 or tp / g.me.tp
    end
    return 0
end

-- Never healed for their own sake: a member skipped by name, and the alliance's
-- other parties while heal.alliance is off (the focus member is still healed).
local function skipped(u, ctx)
    return ctx.s.skip[u.name] or u.kind == 'alliance' and not ctx.s.alliance and u ~= ctx.focus
end

-- One candidate: `a` in form `f` aimed at `centre`. Nil unless it reaches a band member.
-- An area form covers the centre's party near them; a tracked player's is unknown.
local function rate(band, a, f, centre, amt, ctx, members)
    if f.via and not can.party(centre) then return nil end
    local spread = f.radius > 0
    local c = { band = band, a = a, f = f, centre = centre, cover = {}, sum = 0, points = 0, count = 0 }
    for _, u in ipairs(ctx.g.units) do
        if u == centre or spread and can.together(centre, u) and u.alive and u.in_zone and can.dist(centre, u) <= f.radius then
            c.cover[#c.cover + 1] = u
            local useful = amt and not skipped(u, ctx) and math.min(amt, need(u, band == 'efficient')) or 0
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
    -- ponytail: each member helped weighs in by sqrt, a guess: enough that one Curaga beats
    -- healing three one at a time, not so much it spends 180 MP to save one cast; tune in play
    c.score = band == 'efficient' and c.sum / math.max(c.share, 1e-6) * math.sqrt(c.count)
        or c.points / f.lockout
    return c
end

-- The biggest of your Regens whose whole total lands on `u`, if any. Per MP the
-- smallest always wins, so tiers can't just compete: Regen I would go on everyone,
-- and its status would keep a bigger one off for 75s.
local function regen_for(u, ctx)
    local pick
    for _, r in ipairs(ctx.regens) do
        if amount(r, ctx) <= need(u, true) and (not pick or r.tier > pick.tier) then pick = r end
    end
    return pick
end

-- Higher score; on a tie the cheaper, then the one covering the focus member.
local function better(c, best)
    if not best then return true end
    if math.abs(c.score - best.score) > EPS * math.max(1, best.score) then return c.score > best.score end
    if math.abs(c.share - best.share) > EPS then return c.share < best.share end
    return c.focus and not best.focus
end

-- The best candidate for the band. A heal with no amount (Vivacious Pulse) goes
-- only when nothing else can, and never in efficient. Efficient sends nothing
-- while every heal would overheal: chip damage waits. A Ready move (Wild Carrot)
-- keeps its charges for the pet's attacks unless someone is in danger.
local function best_of(band, ctx, ready, members)
    local best, fallback, fits = nil, nil, band ~= 'efficient'
    for _, a in ipairs(ready) do
        if (not a.tick or band == 'efficient') and not (a.charges and band == 'efficient') then
            local amt, m = amount(a, ctx)
            for _, f in ipairs(forms(a, ctx, band)) do
                for _, centre in ipairs(centres(a, ctx.g)) do
                    local c = not (a.tick and (any(centre.buffs, a.status) or ctx.regen_for[centre] ~= a))
                        and rate(band, a, f, centre, amt, ctx, members)
                    if c then c.mult = m end
                    if c and amt then
                        -- ponytail: judged on the worst member covered; an area heal's other members may still overheal
                        fits = fits or amt <= need(c.worst, true)
                        if better(c, best) then best = c end
                    elseif c then
                        fallback = fallback or c
                    end
                end
            end
        end
    end
    if not fits then return nil end
    return best or (band ~= 'efficient' and fallback or nil)
end

local function why(c)
    local w = c.worst
    return ('%s: %s %d%%%s'):format(c.band, w.name, w.hpp, c.count > 1 and (' +%d'):format(c.count - 1) or '')
end

-- The candidate as an intent. Sending it tells core/observed.lua what to expect,
-- so the real HP restored can be learned and a Regen counted while it ticks. A
-- tracked player's max HP is a guess, so a heal capped by it could pass for a
-- weak one: what lands on them teaches nothing. The alliance's HP is read as a member's.
local function intent(c, ctx)
    if c.f.via then return { action = c.f.via, expect = c.f.via.status, why = ('%s, for %s'):format(why(c), c.a.name) } end
    local a, s, need_at = c.a, ctx.s, {}
    for _, u in ipairs(c.cover) do
        if u.kind ~= 'tracked' then need_at[u.sid] = need(u, false) end
    end
    return { action = a, target = around_pet(a) and ctx.g.me or c.centre, why = why(c), sent = function (now)
        observed.sent(observed.key(a), { need = need_at, mult = c.mult, at = now,
            per_tick = a.tick and a.tick + s.regen_potency, seconds = a.duration })
    end }
end

local function lines(u, ctx)
    local s = ctx.s
    if u == ctx.focus then return s.focus_critical, s.focus_danger end
    return s.critical, s.danger
end

-- The band's members as a set and worst first. Danger includes critical; efficient
-- starts at the danger line and leaves out whoever your ticking Regen will fill.
local function members_of(band, ctx)
    local set, list = {}, {}
    for _, u in ipairs(ctx.g.units) do
        if u.alive and u.in_zone and u.max_hp and not skipped(u, ctx) then
            local critical, danger = lines(u, ctx)
            local inside
            if band == 'critical' then inside = u.hpp < critical
            elseif band == 'danger' then inside = u.hpp < danger
            else inside = u.hpp >= danger and u.hp + pending(u) < u.max_hp end
            if inside then set[u] = true; list[#list + 1] = u end
        end
    end
    table.sort(list, function (a, b) return a.hpp < b.hpp end)
    return set, list
end

-- Whether the best critical heal, with boost `b` up, is one `b` boosts.
local function boosts_best(b, ctx, ready, members)
    ctx.up[#ctx.up + 1] = b
    local c = best_of('critical', ctx, ready, members)
    ctx.up[#ctx.up] = nil
    return c ~= nil and boosts(b, c.a)
end

-- Critical, before the heal: a boost for the heal that will land with it up, an
-- aimed save on the worst member, then the other emergencies when a heal will follow.
local function emergency(ctx, list, best, emergencies, ready, members)
    local g = ctx.g
    for _, e in ipairs(emergencies) do
        if e.boost and e.boost.factor > 1 and can.use(e, g) and boosts_best(e.boost, ctx, ready, members) then
            return { action = e, expect = e.status, why = ('critical: %s %d%%'):format(list[1].name, list[1].hpp) }
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
local function context(g, cat, cfg, emergencies)
    local ctx = { g = g, s = cfg.heal, up = {}, sky = heal.sky(g), focus = focus_of(g, cfg.heal) }
    for _, a in ipairs(cat) do
        if a.boost and any(g.me.buffs, a.status) then
            ctx.up[#ctx.up + 1] = a.boost
            ctx.factor_up = ctx.factor_up or a.boost.factor > 1
            ctx.area = ctx.area or a.boost.area and a.boost
        end
    end
    for _, e in ipairs(emergencies) do
        if e.boost and e.boost.area and not any(g.me.buffs, e.status) and can.use(e, g) then ctx.accession = e end
    end
    return ctx
end

function heal.want(g, cat, cfg)
    local emergencies = settings.enabled(cat, cfg, 'emergency')
    local ctx = context(g, cat, cfg, emergencies)
    local ready, waiting = {}, {}
    ctx.regens, ctx.regen_for = {}, {}
    for _, a in ipairs(settings.enabled(cat, cfg, 'heal')) do
        local ok, _, wait = can.use(a, g)
        if a.tick then
            if ok and a.tick > 0 then ready[#ready + 1] = a; ctx.regens[#ctx.regens + 1] = a end
        elseif ok then ready[#ready + 1] = a
        elseif wait and wait <= HOLD_MAX then waiting[#waiting + 1] = a end
    end
    for _, u in ipairs(g.units) do ctx.regen_for[u] = regen_for(u, ctx) end

    for _, band in ipairs(BANDS) do
        local members, list = members_of(band, ctx)
        if list[1] then
            local best = best_of(band, ctx, ready, members)
            local e = band == 'critical' and not ctx.factor_up and emergency(ctx, list, best, emergencies, ready, members)
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
