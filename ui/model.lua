--[[
    The UI interface: what any UI file is given each frame. Pure: no imgui, no
    AshitaCore, so tests can build it from a fake snapshot and the real catalog.
    ui/README.md documents both halves for UI authors; keep it in step.

    model.build(g, cat, cfg, status, names) -> view     everything a UI shows
        g       snapshot (core/game.lua)        cat     catalog list
        cfg     settings (core/settings.lua)    status  Sidekick3.lua's status table
        names   { job = function (id) -> 'WHM', statuses = { [id] = { en, jp } },
                  spells, abilities = { [id] = { en, jp } } or nil: names to find by their English one }
        On a Japanese client (cfg.ui.japanese) what it writes for a UI to show is Japanese (core/lang.lua): names
        of spells, abilities, items, statuses and jobs from the DATs, its own words from core/ja.lua. What a UI
        passes back to `act` or compares (keys, names, slots, state, flags, halted, section ids and titles) stays
        English.
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
local can = require('core.can')
local heal = require('behaviors.heal')
local job_modules = require('core.jobs')
local lang = require('core.lang')
local profiles = require('core.profiles')
local settings = require('core.settings')
local util = require('core.util')

local model = {}

-- Settings sections in order, each under its `header` (headers in the order their first section comes). 'profile',
-- 'track' and 'ui' have no switch; every other is switched by cfg[id].on, and one with roles has rows. Wake and the
-- job sections (Rolls, Songs, Geomancy, Runes, Maneuvers) show only when there's something for them (model.build's
-- `has`, and a job module's `view`); a section with roles, only while it has rows. A job module's section goes
-- in before the one it names (core/jobs.lua).
model.SECTIONS = {
    { id = 'profile', title = 'Profiles', header = 'Profiles', switch = false },
    { id = 'follow', title = 'Follow', header = 'Follow' },
    { id = 'heal', title = 'Healing', roles = { 'heal', 'emergency' }, header = 'Heal' },
    { id = 'revive', title = 'Revive', roles = { 'revive' }, header = 'Heal' },
    { id = 'wake', title = 'Wake sleepers', header = 'Remove' },
    { id = 'remove', title = 'Debuff removal', roles = { 'remove' }, header = 'Remove' },
    { id = 'buff', title = 'Buffs', roles = { 'buff' }, header = 'Buff' },
    { id = 'pet', title = 'Pet', roles = { 'pet_heal', 'pet_remove', 'pet_send' }, header = 'Pet' },
    { id = 'recover', title = 'Recovery', roles = { 'recover' }, header = 'Recover' },
    { id = 'rest', title = 'Resting', header = 'Recover' },
    { id = 'track', title = 'Tracked players', header = 'Tracked', switch = false },
    { id = 'afk', title = 'AFK sleep', header = 'AFK' },
    { id = 'ui', title = 'UI / Log', header = 'UI / Log', switch = false },
}
for _, spec in job_modules.each('ui') do
    local s, at = spec.section, nil
    for i, x in ipairs(model.SECTIONS) do
        assert(x.id ~= s.id, 'a job module repeats a section: ' .. tostring(s.id))
        if x.id == s.before then at = i end
    end
    assert(at, 'a job section goes before an unknown one: ' .. tostring(s.before))
    local e = util.shallow_copy(s)
    e.before = nil
    table.insert(model.SECTIONS, at, e)
end
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

-- Each distinct value of `field` over `acts`, in order.
local function distinct(acts, field)
    local out, seen = {}, {}
    for _, a in ipairs(acts) do
        local v = a[field]
        if v ~= nil and not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
    return out
end

-- `a`'s family as shown: in Japanese its Japanese name, a tier's numeral cut off ('ケアルIV' -> 'ケアル',
-- '空蝉の術:壱' -> '空蝉の術').
local function family_of(a)
    local s = lang.name(a.name, a.jp)
    if s == a.name then return a.family end  -- English, or no Japanese name
    if a.name == a.family then return s end
    return s:match('^(.-)%s*[IVX]+$') or s:match('^(.-)%s*:') or s:match('^(.-)%s*：') or s
end

-- `a`'s label ('Regen (keep up)') or family as shown: in Japanese the name in it is the DAT's.
local function label_of(a)
    if not a.label then return family_of(a) end
    local base, note = a.label:match('^(.-) %((.+)%)$')
    if not lang.on or not (base == a.name or base == a.family) then return lang.on and lang.t(a.label) or a.label end
    return lang.f('%s (%s)', base == a.name and lang.name(a.name, a.jp) or family_of(a), lang.t(note))
end

-- Each distinct family of `acts`, as shown.
local function families_of(acts)
    local out, seen = {}, {}
    for _, a in ipairs(acts) do
        if not seen[a.family] then seen[a.family] = true; out[#out + 1] = family_of(a) end
    end
    return out
end

-- "Valor Minuet (+ATK)": the family, or a pick-one group's families (its key
-- when there are many), with the note every action shares.
local function row_label(key, acts, note)
    local a = acts[1]
    local label = label_of(a)
    if a.pick_one then
        local families = families_of(acts)
        label = #families <= LABEL_FAMILIES and table.concat(families, ' / ')
            or lang.t(util.capitalize((key:gsub('_', ' '))))
    end
    return note and lang.f('%s (%s)', label, lang.t(note)) or label
end

-- A buff row's choices { label, name }: tiers after "Auto (best)" (name nil), or
-- a pick-one group's actions, each with its own note when the row has none.
local function choices(acts, note)
    local names = distinct(acts, 'name')
    if not acts[1].pick_one and #names < 2 then return nil end
    local out = acts[1].pick_one and {} or { { label = lang.t('Auto (best)') } }
    for _, name in ipairs(names) do
        local a
        for _, x in ipairs(acts) do if x.name == name then a = x; break end end
        local label = a.label and label_of(a) or lang.name(a.name, a.jp)
        if a.note and not note then label = lang.f('%s (%s)', label, lang.t(a.note)) end
        out[#out + 1] = { label = label, name = name }
    end
    return out
end

-- Whether the action this row would use can go now, and if not why; when it can, the action as shown.
local function availability(acts, r, g)
    if acts[1].pick_one and not r.pick then return false, lang.t('pick one') end
    local sorted = util.shallow_copy(acts)
    table.sort(sorted, util.by_level)
    local wait, reason
    for _, a in ipairs(sorted) do
        if not r.pick or r.pick == a.name then
            local ok, why, w = can.use(a, g)
            -- Radial Arcana with no luopan out puts one down to spend (jobs/geo.lua).
            if a.luopan == 'spend' and why == 'no pet' and g.recast(a) == 0 then ok = true end
            if ok then return true, lang.t('ready'), lang.name(a.name, a.jp) end
            -- Ammo you hold but don't wear is equipped for it (core/ammo.lua).
            local it = why == 'no ammo' and ammo.wearable(a, g)
            if it then
                ok, why, w = can.use(a, util.overlay(g, { ammo = it.id }))
                if ok then return true, lang.f('equips %s', lang.name(it.en, it.jp)), lang.name(a.name, a.jp) end
            end
            if w then wait = math.min(wait or w, w) else reason = reason or why end
        end
    end
    if wait then return false, lang.f('recast %ds', math.ceil(wait)) end
    return false, reason and lang.why(reason) or lang.t('not available')
end

-- Slot chips in rows: your party (ME, P1-P5), then, when `outside` is not false,
-- the alliance's other parties (B0-B5 group 'a', C0-C5 group 'b', empty slots
-- included) and one chip per tracked player (group 'tracked', slot their name).
-- `wrap` is set on the first chip of each of those rows. `on(slot, unit)` says
-- whether the chip is on. A member with no name yet has `name` nil, as an empty slot.
local function player_chips(units, outsiders, outside, on)
    local out = {}
    local function add(slot, group, u, label, wrap)
        out[#out + 1] = {
            slot = slot, label = label, group = group, present = u ~= nil,
            name = u and u.name ~= '' and u.name or nil, on = on(slot, u) == true, wrap = wrap,
        }
    end
    for slot = 0, 5 do add(slot, 'party', units[slot], TAGS[slot]) end
    if outside == false then return out end
    for slot = 6, 11 do add(slot, 'a', units[slot], TAGS[slot], slot == 6 or nil) end
    for slot = 12, 17 do add(slot, 'b', units[slot], TAGS[slot], slot == 12 or nil) end
    for i, u in ipairs(outsiders) do
        add(u.name, 'tracked', u, 'T' .. i, i == 1 or nil)
    end
    return out
end

-- Target chips for a buff that can go on others. Party only when every tier stays
-- in the party (Regen). A spell that can go outside always lists both alliance
-- parties, empty slots included, then the tracked players.
local function chips(acts, r, units, outsiders)
    local reaches, outside = false, false
    for _, a in ipairs(acts) do
        reaches = reaches or not (can.self_only(a) or can.at_enemy(a))
        outside = outside or can.outside(a)
    end
    if not reaches then return nil end
    local chosen = r.targets or { [0] = true }
    return player_chips(units, outsiders, outside, function (slot) return chosen[slot] == true end)
end

-- A modifier's chip as shown: its abbreviation ('Pen'); in Japanese its name's first two characters ('簡素' of
-- 簡素清貧の章), three when it starts with kana ('エンボ' of エンボルド).
local function chip_of(m)
    local s = lang.name(m.name, m.jp)
    if s == m.name then return m.chip or m.name end
    local kanji = s:byte(1) >= 0xE4 and s:byte(1) <= 0xE9  -- U+4E00 to U+9FFF
    return s:match(kanji and '^[\224-\239][\128-\191][\128-\191][\224-\239][\128-\191][\128-\191]'
        or '^[\224-\239][\128-\191][\128-\191][\224-\239][\128-\191][\128-\191][\224-\239][\128-\191][\128-\191]') or s
end

-- Modifier chips (SCH's stratagems, RUN's Embolden): each one in the catalog that fits one of
-- the row's spells.
local function mod_chips(acts, r, modifiers)
    local on, out = r.mods or {}, {}
    for _, m in ipairs(modifiers) do
        local fits = false
        for _, a in ipairs(acts) do fits = fits or m.applies(a) end
        if fits then
            out[#out + 1] = { name = m.name, label = chip_of(m), note = m.note and lang.t(m.note), on = on[m.name] == true }
        end
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
        row.choice = lang.t(acts[1].pick_one and 'Pick one' or 'Auto (best)')
        if r.pick then row.choice = lang.f('%s (not available)', lang.name(r.pick)) end
        for _, c in ipairs(row.choices) do
            if c.name == r.pick then row.choice = c.label end
        end
    end
    -- Only the heals left ticked under Heal (heal.never) can go.
    local live = {}
    for _, a in ipairs(acts) do
        if not settings.never_heal(cfg, a) then live[#live + 1] = a end
    end
    if live[1] then
        row.ready, row.avail, row.action = availability(live, r, g)
    else
        row.ready, row.avail = false, lang.t('unticked above')
    end
    -- Held: a modifier on for it that can't go says why it waits.
    for _, m in ipairs(row.hold and modifiers or {}) do
        if row.ready and (r.mods or {})[m.name] and not can.any(g.me.buffs, m.status) then
            local ok, why = can.use(m, g)
            if not ok then row.ready, row.avail = false, lang.f('waits for %s: %s', chip_of(m), lang.why(why)) end
        end
    end
    if acts[1].kind == 'item' then row.count = g.items and g.items[acts[1].id] or 0 end
    if acts[1].tool then row.tools = can.tools(acts[1], g) end
    return row
end

-- Debuff removal's debuff rows: one per status name your removers clear, in status
-- id order (Poison, Paralysis, Blindness...). `key` is the name, for
-- act.debuff; ready or why not by the removers that are on that clear it, `usable`
-- false while none is; `action` names every one that can.
-- Each is labelled by its status (`statuses`, by id: its Japanese name in Japanese).
-- `on` is everyone's (cfg.remove.skip). `own[name]` is that player's chip when they have
-- their own set (false stored: a status they leave on). Players without a set use `on`.
local function debuff_rows(g, cat, cfg, statuses)
    local of, order, skip, own = {}, {}, cfg.remove.skip or {}, cfg.remove.own or {}
    for _, a in ipairs(cat) do
        if a.role == 'remove' then
            local usable = settings.row(cfg, a).on
            for _, id in ipairs(a.removes) do
                local name = a.debuffs[id]
                local d = of[name]
                if not d then d = { id = id, all = {}, acts = {} }; of[name] = d; order[#order + 1] = name end
                d.id = math.min(d.id, id)
                if d.all[#d.all] ~= a then
                    d.all[#d.all + 1] = a
                    if usable then d.acts[#d.acts + 1] = a end
                end
            end
        end
    end
    table.sort(order, function (x, y) return of[x].id < of[y].id end)
    local rows = {}
    for _, name in ipairs(order) do
        local d = of[name]
        local status = statuses and statuses[d.id]
        -- (by its status alone: by name, 'Poison' would find the spell)
        local label = lang.name((name:gsub('%f[%a]%l', string.upper)), status and status.en == name and status.jp or false)
        local row = { key = name, label = label, on = not skip[name], debuff = true,
                      usable = d.acts[1] ~= nil, ready = false, avail = lang.t('nothing on removes it') }
        for who, mine in pairs(own) do
            if type(who) == 'string' and type(mine) == 'table' and mine.set then
                row.own = row.own or {}
                row.own[who] = not (type(mine.skip) == 'table' and mine.skip[name] == true)
            end
        end
        if row.usable then row.ready, row.avail = availability(d.acts, {}, g) end
        row.action = lang.list(families_of(d.all))
        rows[#rows + 1] = row
    end
    return rows
end

-- One section's rows, one per settings key, roles in the section's order. Debuff
-- removal's are its spells and abilities (`remover`), then its debuffs, then its items.
local function build_rows(s, g, cat, cfg, units, outsiders, statuses)
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
        local row = build_row(key, acts_of[key], cfg, g, units, chipped and modifiers, outsiders)
        if s.id == 'remove' and not row.count then
            row.remover = true
            for _, a in ipairs(cat) do  -- a family with another role (Chakra heals too) shares its row
                if settings.key(a) == key and a.role ~= 'remove' then row.shared = true end
            end
        end
        rows[#rows + 1] = row
    end
    if s.id == 'remove' then
        local at = 1
        while rows[at] and rows[at].remover do at = at + 1 end
        for i, d in ipairs(debuff_rows(g, cat, cfg, statuses)) do table.insert(rows, at + i - 1, d) end
    end
    return rows
end

-- Status and party -----------------------------------------------------------

local function reason(why) return REASONS[why] or why or '' end

-- An action sent or about to be (`e`: a status entry, or another session's), as shown: a spell's, ability's or item's
-- name (its `jp` the Japanese one, else found by its English one); resting's Rest and Stand and following's Follow,
-- words (core/engine.lua's commands).
local function action_of(e)
    if e.behavior == 'rest' or e.behavior == 'follow' then return lang.t(e.action) end
    return lang.name(e.action, e.jp)
end

-- "Cure IV -> Kupipi (heal: Kupipi at 62%)" for a status entry, as shown.
function model.action_text(e, with_why)
    local action = action_of(e)
    local text = e.target and lang.f('%s -> %s', action, lang.text(e.target)) or action
    if with_why then text = lang.f('%s (%s: %s)', text, lang.t(e.behavior), lang.why(e.why)) end
    return text
end

local function status_line(status)
    if status.running then
        local last = status.sent[1]
        return { state = 'Running', running = true,
                 text = last and model.action_text(last, true) or lang.t('nothing sent yet'),
                 dim = not status.intent and lang.why(reason(status.why)) or nil }
    end
    return { state = 'Stopped', running = false,
             text = status.intent and lang.f('would: %s', model.action_text(status.intent, true)) or lang.why(reason(status.why)) }
end

local function buff_names(buffs, statuses)
    local list = {}
    for id in pairs(buffs) do
        local s = statuses[id]
        list[#list + 1] = s and lang.name(s.en, s.jp or false) or tostring(id)
    end
    table.sort(list)
    local shown = {}
    for i = 1, math.min(#list, BUFFS_SHOWN) do shown[i] = list[i] end
    local text = lang.list(shown)
    if #list > BUFFS_SHOWN then text = ('%s +%d'):format(text, #list - BUFFS_SHOWN) end
    return text, table.concat(list, '\n')
end

-- HP 'ok' | 'low' (under the danger line) | 'critical', on the focus member's lines for them.
local function hp_state(u, h)
    local focus = h.focus ~= '' and u.name:lower() == h.focus:lower()
    if u.hpp < (focus and h.focus_critical or h.critical) then return 'critical' end
    return u.hpp < (focus and h.focus_danger or h.danger) and 'low' or 'ok'
end

-- 'WHM 75 / BLM 37', or 'WAR 75' with no subjob; in Japanese '白75/黒37'.
local function jobs(job, main, main_lv, sub, sub_lv)
    if (sub_lv or 0) > 0 then return lang.f('%s %d / %s %d', lang.job(job(main)), main_lv, lang.job(job(sub)), sub_lv) end
    return lang.f('%s %d', lang.job(job(main)), main_lv)
end

local function entity(e)
    return e and { name = e.name, hpp = e.hpp, dist = ('%.1fy'):format(e.dist or 0) }
end

-- Your pet: as the battle target, with its MP % and TP (`pools`: known, as the client reads them for yours) and
-- whether it has MP.
local function pet_line(e)
    local p = entity(e)
    if p then p.mpp, p.tp, p.pools, p.uses_mp = e.mpp or 0, e.tp or 0, true, e.uses_mp == true end
    return p
end

-- Another session's pet as the client draws it (`e`: an HP % alone), with its MP % and TP from that session's file
-- (`s`) while the file names this pet, by id and name (a new pet may reuse the id), and whether it has MP. Until then
-- (just called, or swapped for another until the next write) `pools` is false and they're 0, as a tracked player's:
-- another pet's MP would be worse than none.
local function their_pet(e, s)
    local p, f = entity(e), s.pet
    p.pools = f ~= nil and f.sid == e.sid and f.name == e.name
    p.mpp, p.tp, p.uses_mp = p.pools and f.mpp or 0, p.pools and f.tp or 0, p.pools and f.uses_mp == true
    return p
end

-- Everyone: party slots ME, P1-P5 and tracked players T1... with their jobs once
-- a /check answers; then the alliance's other parties, B0-B5 and C0-C5, apart.
-- A player who is another Sidekick session (`sessions`, by server id) says so, and has
-- its pet while the client draws one (`files`: their session files, by the same).
local function party(g, cfg, names, sessions, files)
    local out, alliance, n = {}, {}, 0
    for _, u in ipairs(g.units) do
        local buffs, all = buff_names(u.buffs, names.statuses)
        local tag = TAGS[u.slot]
        if u.kind == 'tracked' then n = n + 1; tag = 'T' .. n end
        local list = u.kind == 'alliance' and alliance or out
        local session = u.kind ~= 'self' and u.kind ~= 'trust' and sessions[u.sid] or nil
        list[#list + 1] = {
            tag = tag, kind = u.kind, name = u.name, alive = u.alive, away = not u.in_zone,
            tracked = u.kind == 'tracked' or u.tracked == true, shared = u.auto,
            job = u.main_lv and jobs(names.job, u.main, u.main_lv, u.sub, u.sub_lv) or nil,
            hpp = u.hpp, hp = hp_state(u, cfg.heal), mpp = u.mpp, uses_mp = u.uses_mp == true, tp = u.tp or 0,
            mp = u.uses_mp and u.mpp < cfg.recover.mp and 'low' or 'ok',
            dist = not u.in_zone and 'away' or u.kind == 'self' and '' or ('%.1fy'):format(u.dist or 0),
            buffs = buffs, buffs_all = all,
            session = session, pet = session and u.pet and their_pet(u.pet, files[u.sid]) or nil,
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

-- Other Sidekick sessions on this PC (status.sessions, by owner name) by their server id, and their files by the same.
local function by_sid(status)
    local out, files, watching = {}, {}, status.watching or {}
    for name, s in pairs(status.sessions or {}) do
        local sid = s.members[1].sid
        out[sid], files[sid] = session_of(name, s, watching), s
    end
    return out, files
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
    local text = ('%s:%s'):format(lang.t(util.capitalize((e.behavior:gsub('_.*', '')))), action_of(e))
    local line = ally and allies[ally] or members[member]
    if e.target and not (line and line.name == e.target) then text = lang.f('%s -> %s', text, lang.text(e.target)) end
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
-- pet or the enemy; `pet` for its pet's own while that line has its pet); none when
-- neither has a line here.
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
            local pet = FOR_PET[s.act.behavior] and not s.act.target and member and members[member].pet ~= nil or nil
            if member or ally then
                out[#out + 1] = { session = name, text = text, member = member, ally = ally, pet = pet }
            end
        end
    end
    table.sort(out, function (a, b) return a.session < b.session end)
    return out
end

-- The view ---------------------------------------------------------------------

-- Where a heal sorts: MP heals by HP per MP, then TP heals by HP per 100 TP (a free one,
-- under Trance, first), then those with no estimate.
local function heal_rank(sp)
    if sp.per then return sp.unit == 'MP' and 1 or 2, sp.per end
    if sp.hp and sp.cost == 0 then return 2, math.huge end
    return 3, 0
end

-- Healing's spells and abilities that share their row with another tier, each tickable on its own (heal.never): what
-- each heals now and for what (behaviors/heal.lua's estimates), in heal_rank's order. One per name (Wild Carrot is
-- blue magic and a Ready move). One alone on its row has the row's switch, and a Ready move (spent only in danger)
-- its row's: neither is listed but once unticked, so it can be ticked again.
local function heal_spells(g, cat, cfg)
    local list, tiers, counted = heal.estimates(g, cat, cfg), {}, {}
    for _, e in ipairs(list) do
        local a, key = e.a, settings.key(e.a)
        local id = key .. '/' .. a.name
        if not (a.charges or counted[id]) then counted[id], tiers[key] = true, (tiers[key] or 0) + 1 end
    end
    local out, seen = {}, {}
    for _, e in ipairs(list) do
        local a = e.a
        local never = settings.never_heal(cfg, a)
        if not seen[a.name] and (never or not a.charges and (tiers[settings.key(a)] or 0) > 1) then
            seen[a.name] = true
            out[#out + 1] = {
                name = a.name, label = lang.name(a.name, a.jp), on = not never,
                row_on = settings.row(cfg, a).on == true, hp = e.hp and math.floor(e.hp + 0.5), learned = e.learned,
                cost = e.cost, unit = e.unit, per = e.per and math.floor(e.per * 10 + 0.5) / 10,
                regen = a.tick ~= nil or nil, seconds = a.tick and a.duration or nil, area = (a.area or 0) > 0 or nil,
            }
        end
    end
    table.sort(out, function (x, y)
        local gx, px = heal_rank(x)
        local gy, py = heal_rank(y)
        if gx ~= gy then return gx < gy end
        if px ~= py then return px > py end
        return x.name < y.name
    end)
    return out
end

-- Whether `a` spends what heal.reserve keeps for healing (core/jobs.lua: `reserves`).
local function reserved(a)
    for _, f in job_modules.each('reserves') do
        if f(a) then return true end
    end
    return false
end

function model.build(g, cat, cfg, status, names)
    lang.use(cfg.ui.japanese)
    lang.learn(cat, names.spells, names.abilities, names.statuses)  -- the catalog's first: its items are in no other
    local units, outsiders, known = {}, {}, {}
    for _, u in ipairs(g.units) do
        if u.slot then units[u.slot] = u end
        if u.kind == 'tracked' then outsiders[#outsiders + 1] = u end
        known[u.sid] = true
    end

    -- Who can be the focus, you excluded. Healing's chips are every slot, you
    -- included: on while that person is not skipped by name. Empty slots stay off.
    local h = cfg.heal
    local focus_names = {}
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' then focus_names[#focus_names + 1] = u.name end
    end
    local heal_targets = player_chips(units, outsiders, true, function (_, u)
        return u ~= nil and h.skip[u.name] ~= true
    end)

    local spends_tp, wakes = false, false  -- Chivalry: its TP line is worth showing; a heal can wake
    local stratagems = false               -- what heal.reserve keeps (SCH's charges): the reserve is worth showing
    local shadows = false                  -- NIN: Utsusemi, so recasting at one shadow is worth showing
    for _, a in ipairs(cat) do
        stratagems = stratagems or reserved(a)
        shadows = shadows or a.last_shadow ~= nil
        spends_tp = spends_tp or a.role == 'recover' and a.spends_tp == true
        wakes = wakes or a.role == 'heal' and a.wakes == true and not a.pet
    end

    local party_names = {}  -- your party but you: who a job module's section may pick (Entrust)
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and can.in_party(u) then party_names[#party_names + 1] = u.name end
    end

    local view = {
        job = jobs(names.job, g.main, g.main_lv, g.sub, g.sub_lv),
        status = status_line(status),
        bt = entity(g.bt), pet = pet_line(g.pet),
        flags = {}, recent = {}, sections = {},
        heal = { threshold = h.threshold, danger = h.danger, critical = h.critical, focus = h.focus,
                 focus_threshold = h.focus_threshold, focus_danger = h.focus_danger, focus_critical = h.focus_critical,
                 cure_potency = h.cure_potency, waltz_potency = h.waltz_potency, regen_potency = h.regen_potency,
                 reserve = h.reserve, stratagems = stratagems,
                 focus_names = focus_names, targets = heal_targets, spells = heal_spells(g, cat, cfg) },
        recover = { mp = cfg.recover.mp, tp = cfg.recover.tp, min_tp = cfg.recover.min_tp, spends_tp = spends_tp },
        pet_heal = cfg.pet.heal,
        follow = { on = cfg.follow.on, target = cfg.follow.target, distance = cfg.follow.distance, names = focus_names },
        rest = { on = cfg.rest.on, delay = cfg.rest.delay, distance = cfg.rest.distance },
        afk = { minutes = cfg.afk.minutes, asleep = g.afk == true, left = g.afk_in },
        buff = { hold_aoe = cfg.buff.hold_aoe, gather = cfg.buff.gather, one_shadow = cfg.buff.one_shadow, shadows = shadows },
        -- Your target, by name, when it's a player who could be tracked: not in the party, not tracked yet.
        track = { target = g.target and not known[g.target.sid] and g.target.name or nil },
        japanese = cfg.ui.japanese, log = status.log, ui = {},
        profiles = { active = profiles.active(cfg), names = profiles.names(cfg) },
    }
    local job_shown = {}  -- [section id] = whether a job module's section is shown
    local help = { party = party_names, units = units, ready = availability }
    for _, spec in job_modules.each('ui') do
        local id = spec.section.id
        view[id], job_shown[id] = spec.view(cat, cfg, g, help)
    end
    local sessions, files = by_sid(status)
    view.party, view.alliance = party(g, cfg, names, sessions, files)
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
                                          why = lang.f('%s: %s', lang.t(e.behavior), lang.why(e.why)) }
    end
    -- Sections shown only for a job that has what they keep up; any other with rows only while it has some.
    local has = { wake = wakes }
    for id, shown in pairs(job_shown) do has[id] = shown end
    for _, s in ipairs(model.SECTIONS) do
        local section = { id = s.id, title = s.title, header = s.header }
        if s.switch ~= false then section.on = cfg[s.id].on end  -- cfg.ui.on would be a UI's own
        if s.roles then
            section.rows = build_rows(s, g, cat, cfg, units, outsiders, names.statuses)
            for _, r in ipairs(section.rows) do
                section.has_choices = section.has_choices or r.choices ~= nil
                section.has_targets = section.has_targets or r.targets ~= nil
                section.has_mods = section.has_mods or r.mods ~= nil
            end
        end
        if s.id == 'remove' then
            local off = cfg.remove.off or {}
            section.who = player_chips(units, outsiders, true, function (_, u)
                return u ~= nil and off[u.name] ~= true
            end)
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
model.VIEW = 8
function model.published(view)
    local out = util.shallow_copy(view)
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
    who = { 'string', 'boolean' }, debuff = { 'string', 'boolean', 'string|nil' },
    debuffs = { 'table', 'boolean', 'string|nil' },
    pick = { 'string', 'string|nil' }, target = { 'string', 'number|string', 'boolean' },
    mod = { 'string', 'string', 'boolean' }, hold = { 'string', 'boolean' }, profile = { 'string|nil' }, save_profile = { 'string', 'boolean|nil' },
    new_profile = {}, delete_profile = { 'string' }, track = { 'string' }, untrack = { 'string' },
    skip = { 'string', 'boolean' }, heal_spell = { 'string', 'boolean' }, set = { 'string', 'boolean|number|string' },
}

-- The settings act.set may change from another session: a number's range (the
-- one source of it: the standard window's sliders take theirs from here), 'bool', 'name' (a member, a spell, a roll or ''),
-- 'maneuver' (a maneuver's name or ''), or a list of the values it takes. The job modules' sections
-- add theirs (core/jobs.lua: `ui.set`).
model.REMOTE_SET = {
    ['heal.threshold'] = { 1, 99 }, ['heal.danger'] = { 1, 99 }, ['heal.critical'] = { 1, 99 },
    ['heal.focus_threshold'] = { 1, 99 }, ['heal.focus_danger'] = { 1, 99 }, ['heal.focus_critical'] = { 1, 99 }, ['heal.cure_potency'] = { 0, 50 }, ['heal.waltz_potency'] = { 0, 50 },
    ['heal.regen_potency'] = { 0, 30 }, ['heal.focus'] = 'name', ['heal.reserve'] = 'bool',
    ['recover.mp'] = { 1, 99 }, ['recover.tp'] = { 0, 3000 }, ['recover.min_tp'] = { 0, 3000 }, ['pet.heal'] = { 1, 99 },
    ['follow.on'] = 'bool', ['follow.target'] = 'name', ['follow.distance'] = { 1, 15 },
    ['rest.on'] = 'bool', ['rest.delay'] = { 1, 20 }, ['rest.distance'] = { 1, 15 },
    ['afk.on'] = 'bool', ['afk.minutes'] = { afk.MIN, afk.MAX },
    ['buff.hold_aoe'] = 'bool', ['buff.gather'] = 'bool', ['buff.one_shadow'] = 'bool',
}
for _, spec in job_modules.each('ui') do
    for path, want in pairs(spec.set or {}) do
        assert(model.REMOTE_SET[path] == nil, 'a job module repeats a remote setting: ' .. path)
        model.REMOTE_SET[path] = want
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
    if want.list then return util.contains(want.list, value) and value or nil end
    if type(value) ~= 'number' then return nil end
    return util.clamp(math.floor(value), want[1], want[2])
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
    -- A target's slot is an integer 0-17, or a tracked player's name.
    if fn == 'target' and type(b) == 'number' and (b % 1 ~= 0 or b < 0 or b > 17) then return false end
    -- A player is named, never ''; debuff's and debuffs' name is the third argument.
    if fn == 'who' and a == '' or (fn == 'debuff' or fn == 'debuffs') and call[4] == '' then return false end
    if fn == 'debuffs' then
        for _, name in ipairs(a) do
            if type(name) ~= 'string' then return false end
        end
    end
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

-- `set[key]` true when `on`, cleared when not; without `on`, toggled.
local function flag(set, key, on)
    if on == nil then on = not set[key] end
    set[key] = on or nil
end

function model.actions(cfg, status, changed, tracking, send)
    local act = {}
    -- `f`, then changed(): for the calls that write the settings.
    local function saving(f) return function (...) f(...); changed() end end

    -- This session only: automation always starts stopped, and a start wakes AFK sleep and starts its wait over
    -- (Sidekick3.lua); the log as set (/sk3 log; the standard UI has no switch for it, a custom one may).
    function act.run(on)
        status.running = on
        if on then status.restart = true end
    end
    function act.log(on) status.log = on end
    act.close = saving(function () status.open, cfg.ui.open = false, false end)
    -- id: a section with a switch: 'follow' | 'heal' | 'revive' | 'wake' | 'remove' | 'buff' | 'roll' | 'song' | 'geo'
    -- | 'rune' | 'pet' | 'maneuver' | 'recover' | 'rest' | 'afk'
    act.section = saving(function (id, on) cfg[id].on = on end)
    act.row = saving(function (key, on) saved_row(cfg, key, on).on = on end)
    -- The debuffs left on for `name`: that player's own set, made from everyone's the
    -- first time; without a name, everyone's (cfg.remove.skip). Nil for '' or a non-name.
    local function skip_set(name)
        local rm = cfg.remove
        if name == nil then
            rm.skip = rm.skip or {}
            return rm.skip
        end
        if type(name) ~= 'string' or name == '' then return nil end
        rm.own = rm.own or {}
        local mine = rm.own[name]
        if type(mine) ~= 'table' or not mine.set then
            mine = { set = true, skip = {} }
            for k, v in pairs(rm.skip or {}) do
                if type(k) == 'string' and v == true then mine.skip[k] = true end
            end
            rm.own[name] = mine
        end
        mine.skip = mine.skip or {}
        return mine.skip
    end
    -- Removal runs on this player (`on` true), or leaves them alone, Doom too. By name,
    -- as healing's skips. Nil toggles.
    function act.who(name, on)
        if type(name) ~= 'string' or name == '' then return end
        cfg.remove.off = cfg.remove.off or {}
        if on == nil then on = cfg.remove.off[name] == true end
        cfg.remove.off[name] = not on or nil
        changed()
    end
    -- A debuff (a status name, a Debuff removal row's key) removed or left on: for
    -- `name`'s own set when named (its first change copies everyone's), else everyone's.
    -- Nil `on` toggles.
    function act.debuff(key, on, name)
        local skip = type(key) == 'string' and skip_set(name)
        if not skip then return end
        if on == nil then on = skip[key] == true end
        skip[key] = not on or nil
        changed()
    end
    -- Every debuff in `names` removed (`on` true) or left on (false), for `name` or everyone.
    function act.debuffs(names, on, name)
        local skip = type(names) == 'table' and type(on) == 'boolean' and skip_set(name)
        if not skip then return end
        for _, key in ipairs(names) do
            if type(key) == 'string' then skip[key] = not on or nil end
        end
        changed()
    end
    -- name nil = best tier.
    act.pick = saving(function (key, name) saved_row(cfg, key, false).pick = name end)
    -- A buff row's chips, on or off by `on` (toggled without it): a target (a party slot 0-5, an alliance slot
    -- 6-17, or a tracked player's name), or a modifier fired before its spell (a stratagem: 'Penury', 'Accession'...).
    act.target = saving(function (key, slot, on)
        local r = saved_row(cfg, key, false)
        r.targets = r.targets or { [0] = true }
        flag(r.targets, slot, on)
    end)
    act.mod = saving(function (key, name, on)
        local r = saved_row(cfg, key, false)
        r.mods = r.mods or {}
        flag(r.mods, name, on)
    end)
    -- Whether a row's spell waits while one of its modifiers can't go with it (Hold), or goes without (the default).
    act.hold = saving(function (key, on) saved_row(cfg, key, false).hold = on or nil end)
    -- Profiles (core/profiles.lua): load one by name, nil for Default; save (renames the loaded one when the name
    -- differs), save as, new, delete.
    act.profile = saving(function (name)
        if name then profiles.load(cfg, name) else profiles.load_default(cfg) end
    end)
    function act.save_profile(name, as_new)
        if (as_new and profiles.save_as or profiles.save)(cfg, name) then changed() end
    end
    act.new_profile = saving(function () profiles.new(cfg) end)
    function act.delete_profile(name)
        if profiles.delete(cfg, name) then changed() end
    end
    -- Track a player: by name, or your target when nil. This session only, as untracking.
    function act.track(name) tracking.add(name) end
    function act.untrack(name) tracking.remove(name) end
    -- A member skipped by healing is never healed for their own sake; `skip` sets it, toggled without it.
    act.skip = saving(function (name, skip) flag(cfg.heal.skip, name, skip) end)
    -- One heal (a `view.heal.spells` name: 'Cure II', 'Regen') used by healing (`on` true) or never (false), its row's
    -- other tiers as they were; waking uses it either way. Nil toggles.
    act.heal_spell = saving(function (name, on)
        cfg.heal.never = cfg.heal.never or {}
        if on == nil then on = cfg.heal.never[name] == true end
        cfg.heal.never[name] = not on or nil
    end)
    -- path: 'heal.danger', 'heal.reserve', 'buff.hold_aoe', 'roll.first', 'roll.risk', 'geo.distance',
    -- 'geo.entrust', 'geo.entrust_spell', 'rune.idle_1', 'maneuver.slot_1', 'song.area_1', 'song.p1_2', 'follow.target',
    -- 'japanese', 'ui.hp_width', or 'ui.<anything>' for a UI's own.
    act.set = saving(function (path, value)
        if path == 'japanese' then path = 'ui.japanese' end  -- shared by every job pair, as the HUD
        local t = cfg
        local parent, key = path:match('^(.-)%.?([^.]+)$')
        for part in parent:gmatch('[^.]+') do t = t[part] end
        t[key] = value
    end)
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
