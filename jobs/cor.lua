--[[
    Corsair: Phantom Rolls. The two rolls picked under Rolls (cfg.roll; one on a
    COR subjob) are kept up on you, and the last one rolled is Double-Upped
    while the risk picked says it's worth it (cor.decide, v2's rules). Snake Eye
    is a modifier the engine fires just before a Double-Up (core/engine.lua);
    Fold clears a Bust whenever it's ready.

    The totals come only from your own 0x028 job ability packets
    (core/packets.lua -> cor.ability), and the snapshot carries the last one
    (g.roll = { id, total, die, at, bust, doubled }), so the decision reads the snapshot alone.
    A Double-Up Chance is for the last roll alone: no other is ever doubled.
    A roll or Double-Up sent waits for its total; one that never comes (a lost
    packet) leaves that roll as it is after WAIT seconds, never doubled blind,
    and no total older than the last send is doubled. A new roll waits until
    the last one is settled, so its chase isn't cut short; while it waits,
    mem.busy_until keeps resting from starting (behaviors/rest.lua).
    Nothing goes while you're Invisible (a roll would break it), as buffs.
    With buff.hold_aoe on, a roll is held like an area buff spell until the
    party's players who lack it are inside its area (the DAT's, about 8 yalms).
]]--

local buff = require('behaviors.buff')
local can = require('core.can')

local cor = {}

cor.JOB = 17
cor.RISKS = { 'lowest', 'medium', 'highest' }
cor.DOUBLE_GAP = 6  -- seconds between Double-Ups, from the send and from its total (in-game proven, v2)
cor.WAIT = 5        -- seconds a roll or Double-Up sent waits for its total

local INVISIBLE, DOUBLE_UP_CHANCE, BUST, SNAKE_EYE = 69, 308, 309, 357  -- statuses
local ROLL, ROLL_SUB, DOUBLED, BUSTED, BUSTED_SUB = 420, 421, 424, 426, 427  -- 0x028 messages

local MAX_TOTAL = 11           -- 12 or more busts
local ZERO_RISK_MAX = 5        -- 5 + 6 = 11: no die busts from here
local UNLUCKY_REROLL_MAX = 8   -- past 8 a die busts more often than not

-- The roll packets -----------------------------------------------------------

local last  -- { id = catalog id, total, die, at, bust, doubled }: the last roll, as the server said it

-- One of your job ability packets, on your own target entry: `id` the catalog
-- id (on a Double-Up the server names the roll doubled), `total` its param,
-- `die` its info.
function cor.rolled(id, total, message, now, die)
    local bust = message == BUSTED or message == BUSTED_SUB or (message == DOUBLED and total > MAX_TOTAL)
    if bust or message == ROLL or message == ROLL_SUB or message == DOUBLED then
        last = { id = id, total = total, die = die, at = now, bust = bust or nil, doubled = message == DOUBLED or nil }
    end
end

cor.ability = cor.rolled
function cor.last() return last end
function cor.clear() last = nil end
cor.zone = cor.clear
function cor.read(g) g.roll = last end

-- The strategy (v2's lib/core/roll_strategy.lua) -------------------------------

local function lucky_reachable(total, lucky)
    return lucky ~= nil and lucky > total and lucky <= total + 6
end

-- Medium's rule; Highest takes it when Fold can't undo a Bust.
local function zone(total, lucky, unlucky)
    if lucky_reachable(total, lucky) then return 'double' end
    -- On unlucky, one more die is worth it while busting is at most even.
    if total == unlucky and total <= UNLUCKY_REROLL_MAX then return 'double' end
    return 'stop'
end

-- What to do with a roll at `total`: 'stop' | 'double' | 'snake_eye' (Snake Eye,
-- then Double-Up). risk: 'lowest' banks lucky and never risks a bust; 'medium'
-- banks lucky, chases it one die away and rerolls off unlucky; 'highest' chases
-- 11 while Fold is ready to undo a Bust, else plays as medium. Snake Eye takes 10
-- to 11 on every risk, and lucky - 1 to lucky but on highest (v2's rule; no roll's
-- lucky is over 5, so 5 or under doubles first and it never comes up).
function cor.decide(total, lucky, unlucky, risk, snake_ready, fold_ready)
    if total >= MAX_TOTAL then return 'stop' end
    if total <= ZERO_RISK_MAX then
        return (total == lucky and risk ~= 'highest') and 'stop' or 'double'
    end
    if snake_ready and total == MAX_TOTAL - 1 then return 'snake_eye' end
    if snake_ready and risk ~= 'highest' and total == lucky - 1 then return 'snake_eye' end
    if risk == 'lowest' then return 'stop' end
    if risk == 'highest' and fold_ready then return 'double' end
    return zone(total, lucky, unlucky)
end

-- The behavior -------------------------------------------------------------------

local function named(cat, name)
    for _, a in ipairs(cat) do
        if a.name == name and (a.role == 'roll' or a.role == 'modifier') then return a end
    end
end

-- The rolls picked, as catalog records: the second only on a COR main job, and
-- never the first again.
function cor.picked(cat, cfg, main)
    local out = {}
    for i, name in ipairs({ cfg.roll.first, cfg.roll.second }) do
        local a = (i == 1 or main == cor.JOB) and named(cat, name)
        if a and a.lucky and a ~= out[1] then out[#out + 1] = a end
    end
    return out
end

local function ready(a, g) return a ~= nil and (can.use(a, g)) end

-- Busy until `t`: a step of COR's is due then, so resting mustn't start before it.
local function busy(mem, t) mem.busy_until = math.max(mem.busy_until or -math.huge, t) end

local function up(a, g) return can.any(g.me.buffs, a.status) end

function cor.want(g, cat, cfg, mem)
    local rolls = cor.picked(cat, cfg, g.main)
    if not rolls[1] then return nil end
    local st = mem.cor or { sent = {} }  -- sent[id]: when the roll or its Double-Up last went
    mem.cor = st
    local fold, double, snake = named(cat, 'Fold'), named(cat, 'Double-Up'), named(cat, 'Snake Eye')
    local buffs = g.me.buffs
    if buffs[INVISIBLE] then return nil end

    -- A Bust takes a roll's place until it wears; Fold frees it at once.
    if buffs[BUST] and ready(fold, g) then return { action = fold, why = 'Bust' } end

    -- The last roll, doubled while it's worth it; until it's settled, no new roll.
    -- Only a total newer than every send: a roll sent since may own the Double-Up Chance.
    local r = g.roll
    local roll, newest = nil, -math.huge
    for _, at in pairs(st.sent) do newest = math.max(newest, at) end
    for _, a in ipairs(rolls) do if r and not r.bust and a.id == r.id then roll = a end end
    if roll and r.at >= newest and buffs[DOUBLE_UP_CHANCE] and up(roll, g) and double then
        local decision = (buffs[SNAKE_EYE] and r.total < MAX_TOTAL) and 'double'
            or cor.decide(r.total, roll.lucky, roll.unlucky, cfg.roll.risk, ready(snake, g), ready(fold, g))
        if decision ~= 'stop' then
            local gap = math.max(st.doubled or -math.huge, r.doubled and r.at or -math.huge) + cor.DOUBLE_GAP
            local _, _, wait = can.use(double, g)
            if g.now < gap or wait then busy(mem, math.max(gap, g.now + (wait or 0))); return nil end
            if not ready(double, g) then return nil end
            return { action = double, mods = decision == 'snake_eye' and { snake } or nil,
                     why = ('%s at %d'):format(roll.name, r.total),
                     sent = function (now) st.sent[roll.id], st.doubled = now, now end }
        end
    end
    for id, at in pairs(st.sent) do
        if g.now - at < cor.WAIT and not (r and r.id == id and r.at >= at) then  -- its total is on its way
            busy(mem, at + cor.WAIT)
            return nil
        end
    end

    -- A roll that isn't up, while a slot is free.
    local slots = (g.main == cor.JOB and 2 or 1) - (buffs[BUST] and 1 or 0)
    for _, a in ipairs(rolls) do
        if up(a, g) then slots = slots - 1 end
    end
    for _, a in ipairs(rolls) do
        if slots <= 0 then return nil end
        if not up(a, g) and can.use(a, g) then
            local near, away = buff.area(a, g, cfg.buff.hold_aoe, nil, can.yalms(a.area))
            if away then buff.wait_for(mem, a, near, away); return nil end
            return { action = a, why = 'not up', sent = function (now) st.sent[a.id] = now end }
        end
    end
end

-- Knowledge (core/knowledge.lua says what each field means) --------------------

-- Kept up and Double-Upped here, not as buff rows. The note is what the roll gives;
-- Double-Up and Fold are found by name.
local K = {
    ['Double-Up'] = { role = 'roll' },
    ['Fold']      = { role = 'roll' },
    ['Snake Eye'] = { role = 'modifier', note = 'the next die rolls 1' },  -- fired before a Double-Up
}
-- Phantom Rolls: { note, lucky, unlucky } (v2's table). Each shows the status named like it.
for name, r in pairs({
    ['Corsair\'s Roll'] = { 'EXP+', 5, 9 },      ['Ninja Roll'] = { 'EVA+', 4, 8 },
    ['Hunter\'s Roll'] = { 'ACC+', 4, 8 },       ['Chaos Roll'] = { 'ATK+', 4, 8 },
    ['Magus\'s Roll'] = { 'MDEF+', 2, 6 },       ['Healer\'s Roll'] = { 'Cure+', 3, 7 },
    ['Drachen Roll'] = { 'PACC+', 4, 8 },        ['Choral Roll'] = { 'SIR-', 2, 6 },
    ['Monk\'s Roll'] = { 'SB+', 3, 7 },          ['Beast Roll'] = { 'PATK+', 4, 8 },
    ['Samurai Roll'] = { 'STP+', 2, 6 },         ['Evoker\'s Roll'] = { 'Refresh+', 5, 9 },
    ['Rogue\'s Roll'] = { 'CRIT+', 5, 9 },       ['Warlock\'s Roll'] = { 'MACC+', 4, 8 },
    ['Fighter\'s Roll'] = { 'DA+', 5, 9 },       ['Puppet Roll'] = { 'PMAG+', 3, 7 },
    ['Gallant\'s Roll'] = { 'DMG Reflect', 3, 7 }, ['Wizard\'s Roll'] = { 'MATK+', 5, 9 },
    ['Dancer\'s Roll'] = { 'Regen+', 3, 7 },     ['Scholar\'s Roll'] = { 'CMP+', 2, 6 },
    ['Naturalist\'s Roll'] = { 'Enhancing+', 3, 7 }, ['Runeist\'s Roll'] = { 'MEVA+', 4, 8 },
    ['Companion\'s Roll'] = { 'Pet Regain & Regen', 2, 10 }, ['Bolter\'s Roll'] = { 'Move Speed+', 3, 9 },
    ['Caster\'s Roll'] = { 'Fast Cast+', 2, 7 },
}) do
    K[name] = { role = 'roll', note = r[1], lucky = r[2], unlucky = r[3] }
end
cor.knowledge = K

cor.behaviors = { { name = 'roll', run = cor.want, before = 'buff' } }

-- The rolls kept up (names, '' for none; the second only on a COR main job) and
-- how far Double-Up chases a total: 'lowest' | 'medium' | 'highest'.
cor.settings = { roll = { on = true, first = '', second = '', risk = 'medium' } }

-- SK Settings: Rolls, for a job with rolls (ui/model.lua).
cor.ui = {
    section = { id = 'roll', title = 'Rolls', header = 'Buff', before = 'pet' },
    set = { ['roll.first'] = 'name', ['roll.second'] = 'name', ['roll.risk'] = { list = cor.RISKS } },
}

-- The view's `roll`: the rolls to pick from, and the last one's total; and whether it's shown.
function cor.ui.view(cat, cfg, g)
    local rolls, done = {}, nil
    for _, a in ipairs(cat) do
        if a.lucky then
            rolls[#rolls + 1] = { name = a.name, label = ('%s (%s)'):format(a.name, a.note), lucky = a.lucky, unlucky = a.unlucky }
            -- While it's on you, or just busted (it's gone then).
            if g.roll and g.roll.id == a.id and (g.roll.bust or can.any(g.me.buffs, a.status)) then
                done = { name = a.name, total = g.roll.total, lucky = a.lucky, unlucky = a.unlucky, bust = g.roll.bust == true }
            end
        end
    end
    table.sort(rolls, function (x, y) return x.name < y.name end)
    return { first = cfg.roll.first, second = cfg.roll.second, risk = cfg.roll.risk, risks = cor.RISKS,
             two = g.main == cor.JOB, choices = rolls, last = done }, rolls[1] ~= nil
end

return cor
