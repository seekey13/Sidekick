--[[
    The catalog: every action the player can use right now, built from the
    client DATs (core/resources.lua) plus what each family is for
    (core/knowledge.lua). Replaces v2's hand-written lib/jobs/*.lua.

    Pure: takes plain tables and two "has" predicates, so tests can build one
    from tests/data without a game client.
]]--

local catalog = {}

local TIERS = { II = 2, III = 3, IV = 4, V = 5, VI = 6, Ichi = 1, Ni = 2, San = 3 }

-- Ability types: 2 pet command, 6/10 blood pact, 18 ready move go through /pet;
-- 3 weapon skill, 4 trait, 20 monstrosity are not actions here.
local PET_TYPES  = { [2] = true, [6] = true, [10] = true, [18] = true }
local SKIP_TYPES = { [3] = true, [4] = true, [20] = true }
-- Ability types the DAT gives a cost of 1 MP they don't have: charges (Quick Draw,
-- stratagems) and runes, each 0 MP in game.
local CHARGES = { [9] = true, [15] = true, [21] = true }
local READY_MOVE = 18  -- a jug pet's move: the DAT's MP is the Ready charges it costs (jobs/bst.lua)
local TRUST = 8  -- spell type; calling trusts is not support automation
local BLUE_MAGIC = 6  -- spell type: castable only while set, or through Unbridled Learning (jobs/blu.lua)
local UNBRIDLED = 'Unbridled Learning'
local SELF = 1   -- valid-target flag: items are used on you

local SCH = 20
local ADDENDUM = { [1] = { 401, 416 }, [2] = { 402, 416 } }  -- by spell type: white, black; or Enlightenment

-- "Cure IV" -> "Cure", 4; "Utsusemi: Ni" -> "Utsusemi", 2; "Haste" -> "Haste", 1
function catalog.split(name)
    local fam, t = name:match('^(.-) (%u+)$')
    if TIERS[t] then return fam, TIERS[t] end
    fam, t = name:match('^(.-): (%a+)$')
    if TIERS[t] then return fam, TIERS[t] end
    return name, 1
end

-- Lower-case status name -> lowest id carrying it (later duplicates are GEO auras etc.).
local function status_index(statuses)
    local idx = {}
    for id, s in pairs(statuses) do
        local k = s.en:lower()
        if not idx[k] or id < idx[k] then idx[k] = id end
    end
    return idx
end

-- name | id | { name|id, ... } -> sorted id list, or nil.
local function ids(v, idx, what)
    if v == nil or v == false then return nil end
    if type(v) ~= 'table' then v = { v } end
    local out = {}
    for _, x in ipairs(v) do
        local id = type(x) == 'number' and x or idx[x:lower()]
        out[#out + 1] = assert(id, ('unknown status "%s" in %s'):format(tostring(x), what))
    end
    table.sort(out)
    return out
end

-- Status id -> its name, for the ids in these lists: what can.use names as blocking or needed.
local function names(statuses, ...)
    local out
    for _, list in pairs({ ... }) do
        for _, id in ipairs(list) do
            out = out or {}
            out[id] = statuses[id] and statuses[id].en
        end
    end
    return out
end

-- Knowledge uses for one action: exact name beats family; a use may be kind-specific.
local function uses(K, name, family, kind)
    local row = K[name] or K[family]
    if not row then return { {} } end            -- unknown: listed, never automated
    if row.role then row = { row } end
    local out = {}
    for _, use in ipairs(row) do
        if not use.kind or use.kind == kind then out[#out + 1] = use end
    end
    return out
end

-- Which job lets the player cast this spell now: 'main', 'sub', or nil.
-- Also whether it hangs on SCH's Addendum (only castable through SCH).
local function spell_source(s, p)
    local main_ok = s.lv[p.main] and s.lv[p.main] <= p.main_lv
    local sub_ok = p.sub and s.lv[p.sub] and s.lv[p.sub] <= p.sub_lv
    if not (main_ok or sub_ok) then return nil end
    local addendum = bit.band(s.req, 4) ~= 0
        and not ((main_ok and p.main ~= SCH) or (sub_ok and p.sub ~= SCH))
    if main_ok then return 'main', s.lv[p.main], addendum end
    return 'sub', s.lv[p.sub], addendum
end

-- The first action in `cat` named `name`, in `role` when given.
function catalog.find(cat, name, role)
    for _, a in ipairs(cat) do
        if a.name == name and (not role or a.role == role) then return a end
    end
end

-- The actions of `role` in `cat`, by name.
function catalog.by_name(cat, role)
    local out = {}
    for _, a in ipairs(cat) do
        if a.role == role then out[a.name] = a end
    end
    return out
end

-- Sort orders: the higher level first; higher priority first, then the higher level.
function catalog.by_level(a, b) return (a.level or 0) > (b.level or 0) end
function catalog.by_priority(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return catalog.by_level(a, b)
end

-- Build the catalog.
--   res    { spells, abilities, statuses, items = { [id] = { en, jp } } or nil }
--          from core/resources.lua or tests/data
--   player { main, main_lv, sub, sub_lv, has_spell(id), has_ability(id),
--            set_spells = { [id] = true } or nil: the blue magic set; nil takes every one learned }
--   K      core/knowledge.lua
-- Returns a list of actions, one per use, sorted by kind then id; items last.
function catalog.build(res, player, K)
    local idx = status_index(res.statuses)
    local out = {}

    local function add(kind, id, row, from, level, addendum)
        local family, tier = catalog.split(row.en)
        for _, use in ipairs(uses(K, row.en, family, kind)) do
            -- `requires` is "any of": an Addendum's own list can't take another's.
            assert(not (addendum and use.requires), row.en .. ': an Addendum spell with requires of its own')
            if not (use.main_only and from == 'sub') then
                local status = use.status
                if status == nil and (use.role == 'buff' or use.role == 'modifier' or use.lucky or use.boost) then
                    status = idx[row.en:lower()] or idx[family:lower()]
                end
                out[#out + 1] = {
                    kind = kind, id = id, name = row.en, jp = row.jp, family = family, tier = tier,
                    role = use.role, label = use.label, note = use.note,
                    status = ids(status, idx, row.en),
                    removes = ids(use.removes, idx, row.en),
                    blocked_by = ids(use.blocked_by, idx, row.en),
                    requires = addendum and ADDENDUM[row.type] or ids(use.unbridled and UNBRIDLED or use.requires, idx, row.en),
                    unbridled = use.unbridled,
                    potency = use.potency and use.potency[tier],
                    tick = use.tick and (use.tick[tier] or 0),  -- 0: a tier with no known value
                    boost = use.boost and { kind = use.boost[1], factor = use.boost[2] or 1,
                                            potency = use.boost.potency, area = use.boost.area,
                                            mp = use.boost.mp or 1, tiers = use.boost.tiers },
                    duration = type(use.duration) == 'table' and use.duration[tier] or use.duration,
                    wakes = use.wakes, trance = use.trance, gives = use.gives, gate = use.gate, pick_one = use.pick_one,
                    costs_hp = use.costs_hp, swaps = use.swaps, spends_tp = use.spends_tp,
                    ammo = use.ammo, pet_range = use.pet_range, tool = use.tool, last_shadow = use.last_shadow,
                    applies = use.applies, spreads = use.spreads, chip = use.chip, addendum = addendum or nil,
                    lucky = use.lucky, unlucky = use.unlucky, luopan = use.luopan, rune = use.rune,
                    priority = use.priority or 0, pet = use.pet, travel = use.travel, mob_skill = use.mob_skill,
                    -- the client blocks casts by this cost, so it is the one to trust
                    mp = (kind == 'ja' and CHARGES[row.type] or row.type == READY_MOVE) and 0 or row.mp,
                    tp = row.tp, charges = row.type == READY_MOVE and row.mp or nil,
                    recast = kind == 'ma' and id or row.recast_id,  -- spell id, or ability recast timer id
                    targets = row.targets, range = row.range, area = use.area or row.area,
                    cast = row.cast and row.cast / 4,  -- seconds; spells only
                    element = row.element, skill = row.skill, type = row.type,
                    from = from, level = level,
                }
                local a = out[#out]
                a.names = names(res.statuses, a.blocked_by or {}, a.requires or {})
            end
        end
    end

    for id, s in pairs(res.spells) do
        if s.type ~= TRUST and player.has_spell(id)
            and not (s.type == BLUE_MAGIC and player.set_spells and not player.set_spells[id]
                     and not (K[s.en] and K[s.en].unbridled)) then
            local from, level, addendum = spell_source(s, player)
            if from then add('ma', id, s, from, level, addendum) end
        end
    end
    for id, a in pairs(res.abilities) do
        if not SKIP_TYPES[a.type] and player.has_ability(id) then
            add(PET_TYPES[a.type] and 'pet' or 'ja', id, a)
        end
    end

    -- Enlightenment is an Addendum spell's way in without the Addendum, and
    -- Unbridled Learning an Unbridled spell's: can.use counts it, and the engine
    -- fires it first.
    local enlightenment, unbridled = catalog.find(out, 'Enlightenment', 'modifier'), catalog.find(out, UNBRIDLED, 'modifier')
    for _, a in ipairs(out) do
        a.via = a.addendum and enlightenment or a.unbridled and unbridled or nil
    end

    table.sort(out, function (a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.id ~= b.id then return a.id < b.id end
        return (a.role or '') < (b.role or '')
    end)

    -- Items: knowledge names each by id (no DAT says what an item cures) and the
    -- client spells it for /item (CatsEyeXI's custom items differ). Specific first.
    local items = {}
    for name, use in pairs(K) do
        if use.item then
            local r = res.items and res.items[use.item]
            items[#items + 1] = {
                kind = 'item', id = use.item, name = r and r.en or name, jp = r and r.jp or '', family = name, tier = 1,
                role = use.role, removes = ids(use.removes, idx, name), priority = use.priority or 0,
                one_of = use.one_of, targets = SELF, range = 0, area = 0, level = 0,
            }
        end
    end
    table.sort(items, function (a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    for _, a in ipairs(items) do out[#out + 1] = a end
    return out
end

return catalog
