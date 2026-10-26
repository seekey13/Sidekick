--[[
    The UI interface: what any UI file is given each frame. Pure: no imgui, no
    AshitaCore, so tests can build it from a fake snapshot and the real catalog.
    ui/README.md documents both halves for UI authors; keep it in step.

    model.build(g, cat, cfg, status, names) -> view     everything a UI shows
        g       snapshot (core/game.lua)        cat     catalog list
        cfg     settings (core/settings.lua)    status  Sidekick3.lua's status table
        names   { job = function (id) -> 'WHM', statuses = { [id] = { en = } } }
    model.actions(cfg, status, changed, tracking, send) -> act    every change a UI makes
        changed() is called after each settings write; the caller saves.
        tracking = { add = function (name or nil: your target), remove = function (name) }
        send(name, call): an `act` call for another session (core/share.lua's share.send)
    model.published(view) -> what a session shows of its view to another (remote control)
    model.apply(act, cfg, call, cat) -> whether a call another session sent was one it may make, and made

    Building only reads. Settings change only through `act`, and only on user
    input: a frame read mid-zone must never write anything back.
]]--

local afk = require('core.afk')
local ammo = require('core.ammo')
local brd = require('jobs.brd')
local can = require('core.can')
local cor = require('jobs.cor')
local nin = require('jobs.nin')
local profiles = require('core.profiles')
local pup = require('jobs.pup')
local run = require('jobs.run')
local sch = require('jobs.sch')
local settings = require('core.settings')
local slots = require('core.slots')
local util = require('core.util')

local model = {}

-- Settings sections in order, each under its `header` (headers in the order
-- their first section comes). 'profile', 'track' and 'ui' have no switch; every
-- other section is switched by cfg[id].on, and all but 'afk' are behaviors; one with roles also has rows. Wake shows only when a heal can wake,
-- Rolls only for a job with rolls, Songs only with a song (BRD, main or sub), Geomancy only
-- with a Geo- spell (a GEO main job), Runes only with a rune (RUN, main or sub), Maneuvers
-- for a PUP, main or sub, automaton out or not (none goes until one is).
model.SECTIONS = {
    { id = 'profile', title = 'Profiles', header = 'Profiles', switch = false },
    { id = 'follow', title = 'Follow', header = 'Follow' },
    { id = 'heal', title = 'Healing', roles = { 'heal', 'emergency' }, header = 'Heal' },
    { id = 'revive', title = 'Revive', roles = { 'revive' }, header = 'Heal' },
    { id = 'wake', title = 'Wake sleepers', header = 'Remove' },
    { id = 'remove', title = 'Debuff removal', roles = { 'remove' }, header = 'Remove' },
    { id = 'buff', title = 'Buffs', roles = { 'buff' }, header = 'Buff' },
    { id = 'roll', title = 'Rolls', header = 'Buff' },
    { id = 'song', title = 'Songs', header = 'Buff' },
    { id = 'geo', title = 'Geomancy', roles = { 'geo' }, header = 'Buff' },
    { id = 'rune', title = 'Runes', header = 'Buff' },
    { id = 'pet', title = 'Pet', roles = { 'pet_heal', 'pet_remove', 'pet_send' }, header = 'Pet' },
    { id = 'maneuver', title = 'Maneuvers', header = 'Pet' },
    { id = 'recover', title = 'Recovery', roles = { 'recover' }, header = 'Recover' },
    { id = 'rest', title = 'Resting', header = 'Recover' },
    { id = 'track', title = 'Tracked players', header = 'Tracked', switch = false },
    { id = 'afk', title = 'AFK sleep', header = 'AFK' },
    { id = 'ui', title = 'UI / Log', header = 'UI / Log', switch = false },
}
model.FLAGS = { 'casting', 'moving', 'combat', 'safe', 'afk', 'mounted', 'dead', 'resting', 'incapacitated', 'silenced', 'amnesia' }

-- Party slots' tags: ME, P1-P5, then the alliance's other parties, B0-B5 and C0-C5 (as v2).
model.TAGS = { [0] = 'ME', 'P1', 'P2', 'P3', 'P4', 'P5' }
for i = 0, 5 do model.TAGS[6 + i], model.TAGS[12 + i] = 'B' .. i, 'C' .. i end
local TAGS = model.TAGS
local REASONS = { safe = 'safe zone', afk = 'AFK asleep' }  -- engine gate -> words
local LABEL_FAMILIES = 3                -- a pick-one group named by more families is named by its key
local BUFFS_SHOWN = 6                   -- status names on a party line; the rest in its tooltip
local POINTED = 2                       -- seconds the pointer stays on what was just sent...
local POINTED_CAST = 15                 -- ...or while it is still being cast, up to this
local CAST_REPLY = 2                    -- a cast that began this soon after a spell or item went out is that one
local CASTS = { ma = true, item = true }
local FOR_PET = { pet = true, pet_send = true }  -- behaviors whose actions are your pet's: care, and sending it in

-- Rows -----------------------------------------------------------------------

local function by_level(a, b) return (a.level or 0) > (b.level or 0) end

-- Each distinct value of `field` over `acts`, in order.
local function distinct(acts, field)
    local out, seen = {}, {}
    for _, a in ipairs(acts) do
        local v = a[field]
        if v ~= nil and not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
    return out
end

-- "Valor Minuet (+ATK)": the family, or a pick-one group's families (its key
-- when there are many), with the note every action shares.
local function row_label(key, acts, note)
    local a = acts[1]
    local label = a.label or a.family
    if a.pick_one then
        local families = distinct(acts, 'family')
        label = #families <= LABEL_FAMILIES and table.concat(families, ' / ')
            or (key:gsub('_', ' '):gsub('^%l', string.upper))
    end
    return note and ('%s (%s)'):format(label, note) or label
end

-- A buff row's choices { label, name }: tiers after "Auto (best)" (name nil), or
-- a pick-one group's actions, each with its own note when the row has none.
local function choices(acts, note)
    local names = distinct(acts, 'name')
    if not acts[1].pick_one and #names < 2 then return nil end
    local out = acts[1].pick_one and {} or { { label = 'Auto (best)' } }
    for _, name in ipairs(names) do
        local a
        for _, x in ipairs(acts) do if x.name == name then a = x; break end end
        local label = a.label or a.name
        if a.note and not note then label = ('%s (%s)'):format(label, a.note) end
        out[#out + 1] = { label = label, name = name }
    end
    return out
end

-- Whether the action this row would use can go now, and if not why.
local function availability(acts, r, g)
    if acts[1].pick_one and not r.pick then return false, 'pick one' end
    local sorted = {}
    for i, a in ipairs(acts) do sorted[i] = a end
    table.sort(sorted, by_level)
    local wait, reason
    for _, a in ipairs(sorted) do
        if not r.pick or r.pick == a.name then
            local ok, why, w = can.use(a, g)
            -- Radial Arcana with no luopan out puts one down to spend (jobs/geo.lua).
            if a.luopan == 'spend' and why == 'no pet' and g.recast(a) == 0 then ok = true end
            if ok then return true, 'ready', a.name end
            -- Ammo you hold but don't wear is equipped for it (core/ammo.lua).
            local it = why == 'no ammo' and ammo.wearable(a, g)
            if it then
                ok, why, w = can.use(a, setmetatable({ ammo = it.id }, { __index = g }))
                if ok then return true, 'equips ' .. it.en, a.name end
            end
            if w then wait = math.min(wait or w, w) else reason = reason or why end
        end
    end
    if wait then return false, ('recast %ds'):format(math.ceil(wait)) end
    return false, reason or 'not available'
end

-- Target chips ME, P1-P5 for a buff that can go on others. When it can go
-- outside the party: T1... for each tracked player (their slot is their name),
-- then B0-B5 and C0-C5 on lines of their own (`wrap`), for each of the
-- alliance's other parties that is there or has a chip on.
local function chips(acts, r, units, outsiders)
    local reaches, outside = false, false
    for _, a in ipairs(acts) do
        reaches = reaches or not (can.self_only(a) or can.at_enemy(a))
        outside = outside or can.outside(a)
    end
    if not reaches then return nil end
    local on = r.targets or { [0] = true }
    local out = {}
    local function add(slot, wrap)
        local u = units[slot]
        out[#out + 1] = { slot = slot, label = TAGS[slot], present = u ~= nil, name = u and u.name, on = on[slot] == true,
                          wrap = wrap }
    end
    for slot = 0, 5 do add(slot) end
    if not outside then return out end
    for i, u in ipairs(outsiders) do
        out[#out + 1] = { slot = u.name, label = 'T' .. i, present = true, name = u.name, on = on[u.name] == true }
    end
    for _, first in ipairs({ 6, 12 }) do
        local shown = false
        for slot = first, first + 5 do shown = shown or units[slot] ~= nil or on[slot] == true end
        if shown then
            for slot = first, first + 5 do add(slot, slot == first or nil) end
        end
    end
    return out
end

-- Modifier chips (SCH's stratagems, RUN's Embolden): each one in the catalog that fits one of
-- the row's spells.
local function mod_chips(acts, r, modifiers)
    local on, out = r.mods or {}, {}
    for _, m in ipairs(modifiers) do
        local fits = false
        for _, a in ipairs(acts) do fits = fits or m.applies(a) end
        if fits then out[#out + 1] = { name = m.name, label = m.chip or m.name, note = m.note, on = on[m.name] == true } end
    end
    return out[1] and out or nil
end

-- `modifiers` (a list, maybe empty) only for buff and luopan rows.
local function build_row(key, acts, cfg, g, units, modifiers, outsiders)
    local r = settings.row(cfg, acts[1])
    local notes = distinct(acts, 'note')
    local note = #notes == 1 and notes[1] or nil
    local row = { key = key, label = row_label(key, acts, note), on = r.on == true }
    if modifiers then
        row.choices = choices(acts, note)
        row.targets = chips(acts, r, units, outsiders)
        row.mods = mod_chips(acts, r, modifiers)
        if row.mods then row.hold = r.hold == true end  -- wait for them, or go without
    end
    if row.choices then
        row.pick = r.pick
        row.choice = acts[1].pick_one and 'Pick one' or 'Auto (best)'
        if r.pick then row.choice = r.pick .. ' (not available)' end
        for _, c in ipairs(row.choices) do
            if c.name == r.pick then row.choice = c.label end
        end
    end
    row.ready, row.avail, row.action = availability(acts, r, g)
    -- Held: a modifier on for it that can't go says why it waits.
    for _, m in ipairs(row.hold and modifiers or {}) do
        if row.ready and (r.mods or {})[m.name] and not can.any(g.me.buffs, m.status) then
            local ok, why = can.use(m, g)
            if not ok then row.ready, row.avail = false, ('waits for %s: %s'):format(m.chip or m.name, why) end
        end
    end
    if acts[1].kind == 'item' then row.count = g.items and g.items[acts[1].id] or 0 end
    if acts[1].tool then row.tools = nin.tools(acts[1], g) end
    return row
end

-- One section's rows, one per settings key, roles in the section's order.
local function build_rows(s, g, cat, cfg, units, outsiders)
    local rows, acts_of, order = {}, {}, {}
    for _, role in ipairs(s.roles) do
        for _, a in ipairs(cat) do
            if a.role == role then
                local key = settings.key(a)
                if not acts_of[key] then acts_of[key] = {}; order[#order + 1] = key end
                table.insert(acts_of[key], a)
            end
        end
    end
    local modifiers = {}
    for _, a in ipairs(cat) do
        if a.role == 'modifier' and a.applies then modifiers[#modifiers + 1] = a end
    end
    for _, key in ipairs(order) do
        local chipped = s.id == 'buff' or s.id == 'geo'
        rows[#rows + 1] = build_row(key, acts_of[key], cfg, g, units, chipped and modifiers, outsiders)
    end
    return rows
end

-- RUN: the runes to pick from, and each set's picks (jobs/run.lua): Idle, then
-- each ward you have, with its switch (its row) and whether it's ready.
local function runes(g, cat, cfg)
    local mine, wards = run.actions(cat)
    local lv = util.level(g, run.JOB)
    local out = { slots = lv > 0 and run.slots(lv) or 0, runes = {}, sets = {} }
    for _, r in ipairs(run.RUNES) do
        local a = mine[r[1]]
        if a then
            out.runes[#out.runes + 1] = { name = a.name, element = a.rune.element, resist = a.rune.resist,
                                          ailments = a.rune.ailments }
        end
    end
    if not out.runes[1] then return out end
    local ward = {}
    for _, w in ipairs(wards) do ward[w.name] = w end
    for _, set in ipairs(run.SETS) do
        local w = set.ward and ward[set.ward]
        if not set.ward or w then
            local e = { key = set.key, label = set.label or set.ward, shows = set.shows, ward = w and w.name,
                        picks = slots.names(cfg.rune, set.key, run.SLOTS) }
            if w then
                local r = settings.row(cfg, w)
                e.on = r.on == true
                e.ready, e.avail = availability({ w }, r, g)
            end
            out.sets[#out.sets + 1] = e
        end
    end
    return out
end

-- PUP: the maneuvers to pick from, by element, and each slot's pick (jobs/pup.lua).
local function maneuvers(g, cat, cfg)
    local out, first = { choices = {}, picks = slots.names(cfg.maneuver, 'slot', pup.SLOTS) }, nil
    for _, a in ipairs(cat) do  -- in id order: the game's element order
        if a.role == 'maneuver' then
            out.choices[#out.choices + 1] = { name = a.name, label = (a.name:gsub(' Maneuver$', '')) }
            first = first or a
        end
    end
    -- They share one recast and every gate, so one says whether they can go.
    if first then out.ready, out.avail = availability({ first }, {}, g) end
    return out
end

-- BRD: the songs to pick from, and each target's picks (jobs/brd.lua): Area, then
-- each party slot with who is in it; `pianissimo` false when you have none (under
-- BRD 20), so the songs on one member can't go.
local function songs(g, cat, cfg, units)
    local mine, pianissimo = brd.actions(cat)
    local out = { slots = brd.slots(g), choices = {}, sets = {}, pianissimo = pianissimo ~= nil,
                  timed = brd.timer_job(g), duration = cfg.song.duration, fast = cfg.song.fast }
    for _, a in ipairs(cat) do  -- in id order: each kind's tiers together
        if mine[a.name] == a then
            out.choices[#out.choices + 1] = { name = a.name, label = ('%s (%s)'):format(a.name, a.note) }
        end
    end
    if not out.choices[1] then return out end
    for _, set in ipairs(brd.SETS) do
        local e = { key = set.key, label = set.label, picks = slots.names(cfg.song, set.key, brd.SLOTS) }
        if set.slot then
            local u = units[set.slot]
            e.name, e.present = u and u.name, u ~= nil
        end
        out.sets[#out.sets + 1] = e
    end
    if pianissimo then out.ready, out.avail = availability({ pianissimo }, {}, g) end
    return out
end

-- Status and party -----------------------------------------------------------

local function reason(why) return REASONS[why] or why or '' end

-- "Cure IV -> Kupipi (heal: Kupipi at 62%)" for a status entry.
function model.action_text(e, with_why)
    local text = e.target and ('%s -> %s'):format(e.action, e.target) or e.action
    if with_why then text = ('%s (%s: %s)'):format(text, e.behavior, e.why) end
    return text
end

local function status_line(status)
    if status.running then
        local last = status.sent[1]
        return { state = 'Running', running = true,
                 text = last and model.action_text(last, true) or 'nothing sent yet',
                 dim = not status.intent and reason(status.why) or nil }
    end
    return { state = 'Stopped', running = false,
             text = status.intent and ('would: ' .. model.action_text(status.intent, true)) or reason(status.why) }
end

local function buff_names(buffs, statuses)
    local list = {}
    for id in pairs(buffs) do list[#list + 1] = statuses[id] and statuses[id].en or tostring(id) end
    table.sort(list)
    local shown = {}
    for i = 1, math.min(#list, BUFFS_SHOWN) do shown[i] = list[i] end
    local text = table.concat(shown, ', ')
    if #list > BUFFS_SHOWN then text = ('%s +%d'):format(text, #list - BUFFS_SHOWN) end
    return text, table.concat(list, '\n')
end

-- HP 'ok' | 'low' (under the danger line) | 'critical', on the focus member's lines for them.
local function hp_state(u, h)
    local focus = h.focus ~= '' and u.name:lower() == h.focus:lower()
    if u.hpp < (focus and h.focus_critical or h.critical) then return 'critical' end
    return u.hpp < (focus and h.focus_danger or h.danger) and 'low' or 'ok'
end

-- 'WHM 75 / BLM 37', or 'WAR 75' with no subjob.
local function jobs(job, main, main_lv, sub, sub_lv)
    if (sub_lv or 0) > 0 then return ('%s %d / %s %d'):format(job(main), main_lv, job(sub), sub_lv) end
    return ('%s %d'):format(job(main), main_lv)
end

-- Everyone: party slots ME, P1-P5 and tracked players T1... with their jobs once
-- a /check answers; then the alliance's other parties, B0-B5 and C0-C5, apart.
-- A player who is another Sidekick session (`sessions`, by server id) says so.
local function party(g, cfg, names, sessions)
    local out, alliance, n = {}, {}, 0
    for _, u in ipairs(g.units) do
        local buffs, all = buff_names(u.buffs, names.statuses)
        local tag = TAGS[u.slot]
        if u.kind == 'tracked' then n = n + 1; tag = 'T' .. n end
        local list = u.kind == 'alliance' and alliance or out
        list[#list + 1] = {
            tag = tag, kind = u.kind, name = u.name, alive = u.alive, away = not u.in_zone,
            tracked = u.kind == 'tracked' or u.tracked == true, shared = u.auto,
            job = u.main_lv and jobs(names.job, u.main, u.main_lv, u.sub, u.sub_lv) or nil,
            hpp = u.hpp, hp = hp_state(u, cfg.heal), mpp = u.mpp, uses_mp = u.uses_mp == true, tp = u.tp or 0,
            mp = u.uses_mp and u.mpp < cfg.recover.mp and 'low' or 'ok',
            dist = not u.in_zone and 'away' or u.kind == 'self' and '' or ('%.1fy'):format(u.dist or 0),
            buffs = buffs, buffs_all = all,
            session = u.kind ~= 'self' and u.kind ~= 'trust' and sessions[u.sid] or nil,
        }
    end
    return out, alliance
end

-- What halts automation while it runs, in the engine's order (its gates, core/engine.lua), as words: zoning, dead,
-- mounted, in a safe zone, AFK asleep, incapacitated. Not casting or moving, which hold it only a moment.
local HALTS = { { 'loading', 'zoning' }, { 'dead', 'dead' }, { 'mounted', 'mounted' }, { 'safe', 'safe zone' },
                { 'afk', 'AFK asleep' }, { 'incapacitated', 'incapacitated' } }

-- The first of HALTS on snapshot `g`, or nil.
function model.halted(g)
    for _, h in ipairs(HALTS) do
        if g[h[1]] then return h[2] end
    end
end

-- Another session: { name, running, halted (running, but held by what model.halted names), open (its Sidekick
-- Settings shown here), profiles = { active, names } or nil (unknown) }.
local function session_of(name, s, watching)
    return { name = name, running = s.running, halted = s.running and s.halted or nil, open = watching[name] == true,
             profiles = s.profiles }
end

-- Other Sidekick sessions on this PC (status.sessions, by owner name) by their server id.
local function by_sid(status)
    local out, watching = {}, status.watching or {}
    for name, s in pairs(status.sessions or {}) do out[s.members[1].sid] = session_of(name, s, watching) end
    return out
end

-- Every other Sidekick session on this PC, by name: from their files alone, so a zone (yours or theirs) leaves them
-- as they last were (core/share.lua keeps a loading session's file up).
function model.sessions(status)
    local out, watching = {}, status.watching or {}
    for name, s in pairs(status.sessions or {}) do out[#out + 1] = session_of(name, s, watching) end
    table.sort(out, function (a, b) return a.name < b.name end)
    return out
end

-- The Sidekick Settings shown here for other sessions, by name: { name, view, other },
-- the view their session last published (nil until one comes), marked with its
-- `session`; `other` instead when it's another version's (model.VIEW).
local function remote_views(status)
    local out = {}
    for name in pairs(status.watching or {}) do
        if (status.sessions or {})[name] then
            local v = (status.views or {})[name]
            local other = v ~= nil and v.version ~= model.VIEW or nil
            if v and not other then v.session = name end
            out[#out + 1] = { name = name, view = not other and v or nil, other = other }
        end
    end
    table.sort(out, function (a, b) return a.name < b.name end)
    return out
end

local function entity(e)
    return e and { name = e.name, hpp = e.hpp, dist = ('%.1fy'):format(e.dist or 0) }
end

-- Your pet: as the battle target, with its MP % and TP.
local function pet_line(e)
    local p = entity(e)
    if p then p.mpp, p.tp = e.mpp or 0, e.tp or 0 end
    return p
end

-- Your cast now is the one `e` sent: it is a spell or item, and the cast began
-- as the server answered it, not later (one you started yourself).
local function casting(g, e)
    return g.casting and CASTS[e.kind] and g.cast_at ~= nil and g.cast_at >= e.at and g.cast_at - e.at < CAST_REPLY
end

-- What was just sent, while it lands: for POINTED seconds, or while it is still
-- being cast up to POINTED_CAST; nil when stopped. The HUD points at it once the
-- decision is gone, and the session file lists it for the others' (core/share.lua).
function model.landing(status, g)
    local last = status.running and status.sent[1]
    local age = last and g.now - last.at
    if age and (age < POINTED or age < POINTED_CAST and casting(g, last)) then return last end
end

-- Where action `e` goes: its target's line, else the line given (`member` in
-- `members`, or `ally` in `allies`: whoever acts); a line of the alliance's is
-- `ally` with `member` nil. Returns member, ally and the label, 'Heal:Cure IV',
-- with the target named when the line isn't theirs.
local function aim(e, members, allies, member, ally)
    for i, p in ipairs(members) do
        if p.name == e.target then member, ally = i, nil end
    end
    for j, p in ipairs(allies) do
        if p.name == e.target then member, ally = nil, j end
    end
    local text = ('%s:%s'):format((e.behavior:gsub('_.*', ''):gsub('^%l', string.upper)), e.action)
    local line = ally and allies[ally] or members[member]
    if e.target and not (line and line.name == e.target) then text = ('%s -> %s'):format(text, e.target) end
    return member, ally, text
end

-- What the HUD points at: running, the decision about to go, else what was just
-- sent while it lands; stopped, what it would do. `member` is the party line it
-- is for: the target's, else yours (an action on you, your pet or the enemy);
-- for an alliance member, `ally` is their line instead. A target with no line
-- of its own is named. `pet`: it is your pet's (care, or sending it in), so the
-- HUD points at its card, under yours.
local function pointer(status, g, members, allies)
    local e = status.intent or model.landing(status, g)
    if not e or not members[1] then return nil end
    local member, ally, text = aim(e, members, allies, 1, nil)
    local pet = FOR_PET[e.behavior] and not e.target and g.pet ~= nil or nil
    return { text = text, member = member, ally = ally, live = status.running, pet = pet }
end

-- What the other Sidekick sessions on this PC are doing as it goes (each one's
-- `act`, from its file), by name: a label each, as the pointer's, at its target's
-- line, else at the line of the session's own player (its action on itself, its
-- pet or the enemy); none when neither has a line here.
local function others(status, members, allies)
    local out = {}
    for name, s in pairs(status.sessions or {}) do
        if s.act then
            local own, own_ally
            for i, p in ipairs(members) do
                if p.session and p.session.name == name then own = i end
            end
            for j, p in ipairs(allies) do
                if p.session and p.session.name == name then own_ally = j end
            end
            local member, ally, text = aim(s.act, members, allies, own, own_ally)
            if member or ally then out[#out + 1] = { session = name, text = text, member = member, ally = ally } end
        end
    end
    table.sort(out, function (a, b) return a.session < b.session end)
    return out
end

-- The view ---------------------------------------------------------------------

function model.build(g, cat, cfg, status, names)
    local units, outsiders, known = {}, {}, {}
    for _, u in ipairs(g.units) do
        if u.slot then units[u.slot] = u end
        if u.kind == 'tracked' then outsiders[#outsiders + 1] = u end
        known[u.sid] = true
    end

    -- The alliance can be the focus or followed, and is listed to skip while
    -- heal.alliance is on, each of their parties on a line of its own (`wrap`).
    local h = cfg.heal
    local focus_names, members, begun = {}, {}, {}
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' then
            focus_names[#focus_names + 1] = u.name
            if u.kind ~= 'alliance' or h.alliance then
                local wrap
                if u.kind == 'alliance' then
                    local p = can.party(u)
                    wrap, begun[p] = not begun[p] or nil, true
                end
                members[#members + 1] = { name = u.name, healed = not h.skip[u.name], wrap = wrap }
            end
        end
    end

    local spends_tp, wakes = false, false  -- Chivalry: its TP line is worth showing; a heal can wake
    local stratagems = false               -- SCH: the charge reserve is worth showing
    local shadows = false                  -- NIN: Utsusemi, so recasting at one shadow is worth showing
    local indi, luopans = {}, false        -- GEO: the Indi- spells Entrust can put on a member; a Geo- spell
    local rolls, last = {}, nil            -- COR: the rolls to pick from, and the last one's total
    for _, a in ipairs(cat) do
        if a.lucky then
            rolls[#rolls + 1] = { name = a.name, label = ('%s (%s)'):format(a.name, a.note), lucky = a.lucky, unlucky = a.unlucky }
            -- While it's on you, or just busted (it's gone then).
            if g.roll and g.roll.id == a.id and (g.roll.bust or can.any(g.me.buffs, a.status)) then
                last = { name = a.name, total = g.roll.total, lucky = a.lucky, unlucky = a.unlucky, bust = g.roll.bust == true }
            end
        end
        stratagems = stratagems or sch.POOL:spends(a)
        shadows = shadows or a.last_shadow ~= nil
        if a.pick_one == 'indi' then indi[#indi + 1] = a.name end
        luopans = luopans or a.luopan == 'buff' or a.luopan == 'debuff'
        spends_tp = spends_tp or a.role == 'recover' and a.spends_tp == true
        wakes = wakes or a.role == 'heal' and a.wakes == true and not a.pet
    end

    table.sort(rolls, function (x, y) return x.name < y.name end)
    table.sort(indi)
    local party_names = {}  -- your party but you: who Entrust can go on
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and can.in_party(u) then party_names[#party_names + 1] = u.name end
    end

    local view = {
        job = jobs(names.job, g.main, g.main_lv, g.sub, g.sub_lv),
        status = status_line(status),
        bt = entity(g.bt), pet = pet_line(g.pet),
        flags = {}, recent = {}, sections = {},
        heal = { threshold = h.threshold, danger = h.danger, critical = h.critical, focus = h.focus, alliance = h.alliance,
                 focus_threshold = h.focus_threshold, focus_danger = h.focus_danger, focus_critical = h.focus_critical,
                 cure_potency = h.cure_potency, waltz_potency = h.waltz_potency, regen_potency = h.regen_potency,
                 reserve = h.reserve, stratagems = stratagems,
                 focus_names = focus_names, members = members },
        recover = { mp = cfg.recover.mp, tp = cfg.recover.tp, min_tp = cfg.recover.min_tp, spends_tp = spends_tp },
        pet_heal = cfg.pet.heal,
        follow = { on = cfg.follow.on, target = cfg.follow.target, distance = cfg.follow.distance, names = focus_names },
        rest = { on = cfg.rest.on, delay = cfg.rest.delay, distance = cfg.rest.distance },
        afk = { minutes = cfg.afk.minutes, asleep = g.afk == true, left = g.afk_in },
        buff = { hold_aoe = cfg.buff.hold_aoe, gather = cfg.buff.gather, one_shadow = cfg.buff.one_shadow, shadows = shadows },
        roll = { first = cfg.roll.first, second = cfg.roll.second, risk = cfg.roll.risk, risks = cor.RISKS,
                 two = g.main == cor.JOB, choices = rolls, last = last, max_at_11 = cfg.roll.max_at_11,
                 eleven = (cor.maxed(g, cat, cfg) or {}).name },
        geo = { distance = cfg.geo.distance, linger = cfg.geo.linger, entrust = cfg.geo.entrust,
                entrust_spell = cfg.geo.entrust_spell, indi = indi, names = party_names },
        song = songs(g, cat, cfg, units),
        rune = runes(g, cat, cfg),
        maneuver = maneuvers(g, cat, cfg),
        -- Your target, by name, when it's a player who could be tracked: not in the party, not tracked yet.
        track = { target = g.target and not known[g.target.sid] and g.target.name or nil },
        japanese = cfg.ui.japanese, log = status.log, ui = {},
        profiles = { active = profiles.active(cfg), names = profiles.names(cfg) },
    }
    view.party, view.alliance = party(g, cfg, names, by_sid(status))
    view.remote = remote_views(status)
    view.sessions = model.sessions(status)
    view.status.halted = status.running and model.halted(g) or nil
    for k, v in pairs(cfg.ui) do view.ui[k] = v end
    view.ui.open = status.open == true  -- shown now: an error closes it for the session alone
    view.pointer = pointer(status, g, view.party, view.alliance)
    view.others = others(status, view.party, view.alliance)
    for _, f in ipairs(model.FLAGS) do
        if g[f] then view.flags[#view.flags + 1] = REASONS[f] or f end
    end
    for _, e in ipairs(status.sent) do
        view.recent[#view.recent + 1] = { age = math.floor(g.now - e.at), text = model.action_text(e),
                                          why = ('%s: %s'):format(e.behavior, e.why) }
    end
    -- Sections shown only for a job that has what they keep up; any other with rows only while it has some.
    local has = { wake = wakes, roll = rolls[1] ~= nil, song = view.song.choices[1] ~= nil, geo = luopans,
                  rune = view.rune.runes[1] ~= nil, maneuver = view.maneuver.choices[1] ~= nil }
    for _, s in ipairs(model.SECTIONS) do
        local section = { id = s.id, title = s.title, header = s.header }
        if s.switch ~= false then section.on = cfg[s.id].on end  -- cfg.ui.on would be a UI's own
        if s.roles then
            section.rows = build_rows(s, g, cat, cfg, units, outsiders)
            for _, r in ipairs(section.rows) do
                section.has_choices = section.has_choices or r.choices ~= nil
                section.has_targets = section.has_targets or r.targets ~= nil
                section.has_mods = section.has_mods or r.mods ~= nil
            end
        end
        local shown = has[s.id]
        if shown == nil then shown = not section.rows or #section.rows > 0 end
        if shown then view.sections[#view.sections + 1] = section end
    end
    return view
end

-- What a session publishes of its view for another's Sidekick Settings: all but the
-- HUD's (its labels and sizes) and the views it shows of others itself,
-- with the view's `version`, VIEW: raise it when a field the window draws changes,
-- so a session still running older code isn't drawn from a view it can't read.
model.VIEW = 5
function model.published(view)
    local out = {}
    for k, v in pairs(view) do out[k] = v end
    out.pointer, out.others, out.ui, out.remote, out.sessions = nil, nil, nil, nil, nil
    out.version = model.VIEW
    return out
end

-- Actions: everything a UI can change. The caller saves after changed(). -------

-- The act calls another session may make here: all but act.close, act.log,
-- the HUD's settings (`ui.*`, the Japanese client) and tracking your target.
-- Each one's arguments, by the types each may be ('|' between them), checked as it
-- arrives. Chips come with the state they're set to: a toggle sent from a view a
-- moment old could undo a click.
local REMOTE = {
    run = { 'boolean' }, section = { 'string', 'boolean' }, row = { 'string', 'boolean' },
    pick = { 'string', 'string|nil' }, target = { 'string', 'number|string', 'boolean' },
    mod = { 'string', 'string', 'boolean' }, hold = { 'string', 'boolean' }, profile = { 'string|nil' }, save_profile = { 'string', 'boolean|nil' },
    new_profile = {}, delete_profile = { 'string' }, track = { 'string' }, untrack = { 'string' },
    skip = { 'string', 'boolean' }, set = { 'string', 'boolean|number|string' },
}

-- The settings act.set may change from another session: a number's range (the
-- one source of it: the standard window's sliders take theirs from here), 'bool', 'name' (a member, a spell, a roll or ''),
-- 'maneuver' (a maneuver's name or ''), or a list of the values it takes. A song
-- slot takes a 'name': one the job lacks is skipped, as a rune's.
model.REMOTE_SET = {
    ['heal.threshold'] = { 1, 99 }, ['heal.danger'] = { 1, 99 }, ['heal.critical'] = { 1, 99 },
    ['heal.focus_threshold'] = { 1, 99 }, ['heal.focus_danger'] = { 1, 99 }, ['heal.focus_critical'] = { 1, 99 }, ['heal.cure_potency'] = { 0, 50 }, ['heal.waltz_potency'] = { 0, 50 },
    ['heal.regen_potency'] = { 0, 30 }, ['heal.focus'] = 'name', ['heal.alliance'] = 'bool', ['heal.reserve'] = 'bool',
    ['recover.mp'] = { 1, 99 }, ['recover.tp'] = { 0, 3000 }, ['recover.min_tp'] = { 0, 3000 }, ['pet.heal'] = { 1, 99 },
    ['follow.on'] = 'bool', ['follow.target'] = 'name', ['follow.distance'] = { 1, 15 },
    ['rest.on'] = 'bool', ['rest.delay'] = { 1, 20 }, ['rest.distance'] = { 1, 15 },
    ['afk.on'] = 'bool', ['afk.minutes'] = { afk.MIN, afk.MAX },
    ['buff.hold_aoe'] = 'bool', ['buff.gather'] = 'bool', ['buff.one_shadow'] = 'bool',
    ['roll.first'] = 'name', ['roll.second'] = 'name', ['roll.risk'] = { list = cor.RISKS }, ['roll.max_at_11'] = 'bool',
    ['geo.distance'] = { 3, 30 }, ['geo.linger'] = { 1, 20 }, ['geo.entrust'] = 'name', ['geo.entrust_spell'] = 'name',
    ['song.duration'] = { 0, 300 }, ['song.fast'] = 'bool',
}
for _, s in ipairs({ { 'rune', run.SETS, run.SLOTS, 'name' }, { 'song', brd.SETS, brd.SLOTS, 'name' },
                    { 'maneuver', { { key = 'slot' } }, pup.SLOTS, 'maneuver' } }) do
    for _, set in ipairs(s[2]) do
        for i = 1, s[3] do model.REMOTE_SET[slots.path(s[1], set.key, i)] = s[4] end
    end
end

-- `value` for act.set's `path` from another session, held to its range; nil when
-- it's not one REMOTE_SET lists or not a value it takes.
local function settable(path, value)
    local want = model.REMOTE_SET[path]
    if want == 'bool' then
        if type(value) == 'boolean' then return value end  -- false too: `and value or nil` would drop it
        return nil
    end
    if want == 'maneuver' then
        return type(value) == 'string' and (value == '' or value:find(' Maneuver$') ~= nil) and value or nil
    end
    if want == 'name' then return type(value) == 'string' and value or nil end
    if type(want) ~= 'table' then return nil end
    if want.list then
        for _, v in ipairs(want.list) do if v == value then return value end end
        return nil
    end
    if type(value) ~= 'number' then return nil end
    return math.min(math.max(math.floor(value), want[1]), want[2])
end

local function fits(v, types)
    if type(v) == 'number' and (v ~= v or v == math.huge or v == -math.huge) then return false end
    return ('|' .. types .. '|'):find('|' .. type(v) .. '|', 1, true) ~= nil
end

-- The calls that set a chip on a row: only for a buff or luopan row this job has,
-- since one never saved is made off (a default-on row like Cure would be turned off).
local CHIPS = { hold = true, mod = true, target = true }

local function chipped(cat, key)
    for _, a in ipairs(cat or {}) do
        if (a.role == 'buff' or a.role == 'geo') and settings.key(a) == key then return true end
    end
    return false
end

-- Make `call` ({ fn, n = #args, args... }), sent by another session, through `act`,
-- when it's one REMOTE lists with arguments of the right types (`n` of them, no
-- more than it takes); whether it was. Only those arguments are passed on.
-- `cat` is this session's catalog: chips only on its rows that have them.
function model.apply(act, cfg, call, cat)
    local fn = call[1]
    local types = type(fn) == 'string' and REMOTE[fn]
    if not types or type(call.n) ~= 'number' or call.n > #types then return false end
    for i, t in ipairs(types) do
        if not fits(call[i + 1], t) or i > call.n and call[i + 1] ~= nil then return false end
    end
    local a, b = call[2], call[3]
    if fn == 'section' and (a == 'ui' or type(cfg[a]) ~= 'table' or type(cfg[a].on) ~= 'boolean') then return false end
    if CHIPS[fn] and not chipped(cat, a) then return false end
    if fn == 'target' and type(b) == 'number' and (b % 1 ~= 0 or b < 0 or b > 17) then return false end
    if fn == 'set' then
        local v = settable(a, b)
        if v == nil then return false end
        act.set(a, v)
        return true
    end
    act[fn](unpack(call, 2, #types + 1))
    return true
end

-- A row as saved, created on first touch. Picks, targets and modifiers exist
-- only on buff rows, which default off.
local function saved_row(cfg, key, default_on)
    local r = cfg.rows[key]
    if not r then r = { on = default_on }; cfg.rows[key] = r end
    return r
end

function model.actions(cfg, status, changed, tracking, send)
    local act = {}
    -- This session only: automation always starts stopped, the log as set (/sk3 log; the
    -- standard UI has no switch for it, a custom one may).
    -- A start also wakes AFK sleep and starts its wait over (Sidekick3.lua), as v2.
    function act.run(on)
        status.running = on
        if on then status.restart = true end
    end
    function act.log(on) status.log = on end
    function act.close()
        status.open, cfg.ui.open = false, false
        changed()
    end
    -- id: a section with a switch: 'follow' | 'heal' | 'revive' | 'wake' | 'remove' | 'buff' | 'roll' | 'song' | 'geo' | 'rune' | 'pet' | 'maneuver'
    -- | 'recover' | 'rest' | 'afk'
    function act.section(id, on)
        cfg[id].on = on
        changed()
    end
    function act.row(key, on)
        saved_row(cfg, key, on).on = on
        changed()
    end
    -- name nil = best tier.
    function act.pick(key, name)
        saved_row(cfg, key, false).pick = name
        changed()
    end
    -- slot: a party slot 0-5, an alliance slot 6-17, or a tracked player's name.
    -- `on` sets it; without it the chip toggles.
    function act.target(key, slot, on)
        local r = saved_row(cfg, key, false)
        r.targets = r.targets or { [0] = true }
        if on == nil then on = not r.targets[slot] end
        r.targets[slot] = on or nil
        changed()
    end
    -- A modifier (a stratagem: 'Penury', 'Accession'...) fired before the row's spell,
    -- on or off (`on`; without it, toggled).
    function act.mod(key, name, on)
        local r = saved_row(cfg, key, false)
        r.mods = r.mods or {}
        if on == nil then on = not r.mods[name] end
        r.mods[name] = on or nil
        changed()
    end
    -- Whether a row's spell waits while one of its modifiers can't go with it
    -- (Hold), or goes without (the default).
    function act.hold(key, on)
        saved_row(cfg, key, false).hold = on or nil
        changed()
    end
    -- Profiles (core/profiles.lua): load one by name, nil for Default; save
    -- (renames the loaded one when the name differs), save as, new, delete.
    function act.profile(name)
        if name then profiles.load(cfg, name) else profiles.load_default(cfg) end
        changed()
    end
    function act.save_profile(name, as_new)
        if (as_new and profiles.save_as or profiles.save)(cfg, name) then changed() end
    end
    function act.new_profile()
        profiles.new(cfg)
        changed()
    end
    function act.delete_profile(name)
        if profiles.delete(cfg, name) then changed() end
    end
    -- Track a player: by name, or your target when nil. This session only, as untracking.
    function act.track(name) tracking.add(name) end
    function act.untrack(name) tracking.remove(name) end
    -- A member skipped by healing is never healed for their own sake.
    -- `skip` sets it; without it, toggled.
    function act.skip(name, skip)
        if skip == nil then skip = not cfg.heal.skip[name] end
        cfg.heal.skip[name] = skip or nil
        changed()
    end
    -- path: 'heal.danger', 'heal.alliance', 'heal.reserve', 'buff.hold_aoe', 'roll.first', 'roll.risk', 'geo.distance',
    -- 'geo.entrust', 'geo.entrust_spell', 'rune.idle_1', 'maneuver.slot_1', 'song.area_1', 'song.p1_2', 'follow.target',
    -- 'japanese', 'ui.hp_width', or 'ui.<anything>' for a UI's own.
    function act.set(path, value)
        if path == 'japanese' then path = 'ui.japanese' end  -- shared by every job pair, as the HUD
        local t = cfg
        local parent, key = path:match('^(.-)%.?([^.]+)$')
        for part in parent:gmatch('[^.]+') do t = t[part] end
        t[key] = value
        changed()
    end
    -- Another session's Sidekick Settings shown here, or not: this session only.
    function act.watch(name, on)
        status.watching = status.watching or {}
        status.watching[name] = on or nil
    end
    -- The act of another session, `name`: the REMOTE calls, sent to it to make.
    function act.remote(name)
        local r = {}
        for fn in pairs(REMOTE) do
            r[fn] = function (...) if send then send(name, { fn, n = select('#', ...), ... }) end end
        end
        return r
    end
    return act
end

return model
