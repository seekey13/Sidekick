--[[
    What the window shows, and every change it can make. Pure: no imgui, no
    AshitaCore, so tests can build it from a fake snapshot and the real catalog.

    model.build(g, cat, cfg, status, names) -> view
        g       snapshot (core/game.lua)        cat     catalog list
        cfg     settings (core/settings.lua)    status  Sidekick3.lua's status table
        names   { job = function (id) -> 'WHM', statuses = { [id] = { en = } } }

    Building only reads. Settings change only through the mutators below, and
    only on user input: a frame read mid-zone must never write anything back.
]]--

local can = require('core.can')
local settings = require('core.settings')

local model = {}

-- Window sections in order. A section with roles is a behavior, switched by
-- cfg[id].on; `group` is the page each lives on in the 'groups' layout.
model.SECTIONS = {
    { id = 'heal', title = 'Healing', roles = { 'heal', 'emergency' }, group = 'Healing' },
    { id = 'remove', title = 'Debuffs', roles = { 'remove' }, group = 'Support' },
    { id = 'buff', title = 'Buffs', roles = { 'buff' }, group = 'Support' },
    { id = 'revive', title = 'Raise', roles = { 'revive' }, group = 'Support' },
    { id = 'options', title = 'Options', group = 'Utility' },
}
model.GROUPS = { 'Healing', 'Support', 'Utility' }
model.FLAGS = { 'casting', 'moving', 'combat', 'safe', 'mounted', 'dead', 'resting', 'incapacitated', 'silenced', 'amnesia' }

local SLOT_LABELS = { [0] = 'ME', 'P1', 'P2', 'P3', 'P4', 'P5' }
local REASONS = { safe = 'safe zone' }  -- engine gate -> words
local LABEL_FAMILIES = 3                -- a pick-one group named by more families is named by its key
local BUFFS_SHOWN = 6                   -- status names on a party line; the rest in its tooltip

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
            if ok then return true, 'ready', a.name end
            if w then wait = math.min(wait or w, w) else reason = reason or why end
        end
    end
    if wait then return false, ('recast %ds'):format(math.ceil(wait)) end
    return false, reason or 'not available'
end

-- Target chips ME, P1-P5 for a buff that can go on others.
local function chips(acts, r, units)
    local reaches = false
    for _, a in ipairs(acts) do reaches = reaches or not (can.self_only(a) or can.at_enemy(a)) end
    if not reaches then return nil end
    local on = r.targets or { [0] = true }
    local out = {}
    for slot = 0, 5 do
        local u = units[slot]
        out[#out + 1] = { slot = slot, label = SLOT_LABELS[slot], present = u ~= nil, name = u and u.name, on = on[slot] == true }
    end
    return out
end

local function build_row(key, acts, cfg, g, units, buffs)
    local r = settings.row(cfg, acts[1])
    local notes = distinct(acts, 'note')
    local note = #notes == 1 and notes[1] or nil
    local row = { key = key, label = row_label(key, acts, note), on = r.on == true }
    if buffs then
        row.choices = choices(acts, note)
        row.targets = chips(acts, r, units)
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
    return row
end

-- One section's rows, one per settings key, roles in the section's order.
local function build_rows(s, g, cat, cfg, units)
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
    for _, key in ipairs(order) do
        rows[#rows + 1] = build_row(key, acts_of[key], cfg, g, units, s.id == 'buff')
    end
    return rows
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

local function party(g, cfg, statuses)
    local out = {}
    for _, u in ipairs(g.units) do
        local buffs, all = buff_names(u.buffs, statuses)
        out[#out + 1] = {
            tag = SLOT_LABELS[u.slot], kind = u.kind, name = u.name, alive = u.alive, away = not u.in_zone,
            hpp = u.hpp, hp = hp_state(u, cfg.heal), mpp = u.mpp,
            dist = not u.in_zone and 'away' or u.kind == 'self' and '' or ('%.1fy'):format(u.dist or 0),
            buffs = buffs, buffs_all = all,
        }
    end
    return out
end

local function entity(e)
    return e and { name = e.name, hpp = e.hpp, dist = ('%.1fy'):format(e.dist or 0) }
end

-- The view ---------------------------------------------------------------------

function model.build(g, cat, cfg, status, names)
    local units = {}
    for _, u in ipairs(g.units) do units[u.slot] = u end

    local h = cfg.heal
    local focus_names, members = {}, {}
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' then
            focus_names[#focus_names + 1] = u.name
            members[#members + 1] = { name = u.name, healed = not h.skip[u.name] }
        end
    end

    local view = {
        job = g.sub_lv > 0 and ('%s %d / %s %d'):format(names.job(g.main), g.main_lv, names.job(g.sub), g.sub_lv)
            or ('%s %d'):format(names.job(g.main), g.main_lv),
        status = status_line(status),
        party = party(g, cfg, names.statuses),
        bt = entity(g.bt), pet = entity(g.pet),
        flags = {}, recent = {}, sections = {},
        heal = { danger = h.danger, critical = h.critical, focus = h.focus,
                 focus_danger = h.focus_danger, focus_critical = h.focus_critical,
                 cure_potency = h.cure_potency, waltz_potency = h.waltz_potency, regen_potency = h.regen_potency,
                 focus_names = focus_names, members = members },
        japanese = cfg.japanese, log = status.log, display = cfg.ui.display, size = cfg.ui.size,
    }
    for _, f in ipairs(model.FLAGS) do
        if g[f] then view.flags[#view.flags + 1] = REASONS[f] or f end
    end
    for _, e in ipairs(status.sent) do
        view.recent[#view.recent + 1] = { age = math.floor(g.now - e.at), text = model.action_text(e),
                                          why = ('%s: %s'):format(e.behavior, e.why) }
    end
    for _, s in ipairs(model.SECTIONS) do
        local section = { id = s.id, title = s.title, group = s.group }
        if s.roles then
            section.on = cfg[s.id].on
            section.rows = build_rows(s, g, cat, cfg, units)
            for _, r in ipairs(section.rows) do
                section.has_choices = section.has_choices or r.choices ~= nil
                section.has_targets = section.has_targets or r.targets ~= nil
            end
        end
        if not section.rows or #section.rows > 0 then view.sections[#view.sections + 1] = section end
    end
    return view
end

-- Mutators: the only writers of cfg. The caller saves. ---------------------------

-- A row as saved, created on first touch. Picks and targets exist only on buff
-- rows, which default off.
local function saved_row(cfg, key, default_on)
    local r = cfg.rows[key]
    if not r then r = { on = default_on }; cfg.rows[key] = r end
    return r
end

function model.set_row_on(cfg, key, on)
    saved_row(cfg, key, on).on = on
end

-- name nil = best tier.
function model.set_pick(cfg, key, name)
    saved_row(cfg, key, false).pick = name
end

function model.toggle_target(cfg, key, slot)
    local r = saved_row(cfg, key, false)
    r.targets = r.targets or { [0] = true }
    r.targets[slot] = not r.targets[slot] or nil
end

-- A member skipped by healing is never healed for their own sake.
function model.toggle_skip(cfg, name)
    cfg.heal.skip[name] = not cfg.heal.skip[name] or nil
end

-- name: 'heal' | 'remove' | 'buff' | 'revive'
function model.set_section(cfg, name, on)
    cfg[name].on = on
end

-- path: 'heal.danger', 'japanese', 'ui.display'...
function model.set_value(cfg, path, value)
    local t = cfg
    local parent, key = path:match('^(.-)%.?([^.]+)$')
    for part in parent:gmatch('[^.]+') do t = t[part] end
    t[key] = value
end

return model
