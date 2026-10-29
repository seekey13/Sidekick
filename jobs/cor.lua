--[[
    Corsair: Phantom Rolls. The rolls picked under Rolls (cfg.roll; the second on a
    COR main job only) are kept up on you, and the last one rolled is Double-Upped
    while the risk picked says it's worth it (cor.decide). Snake Eye is a modifier
    the engine fires just before a Double-Up; Fold clears a Bust whenever it's ready.

    The totals come only from your own 0x028 job ability packets (core/packets.lua
    -> cor.ability); the snapshot carries the last (g.roll = { id, total, die, at,
    bust, doubled }) and each roll's (g.roll_totals), cor.read. A Double-Up Chance is the last
    roll's alone. A roll or Double-Up sent waits for its total and is never doubled
    blind: one that never comes leaves the roll as it is after WAIT seconds, and no
    total older than the last send is doubled. A new roll waits until the last is
    settled, while mem.busy_until keeps resting from starting. With roll.max_at_11,
    while one roll picked stands at 11 the other is doubled at max risk (no die can
    bust it then), or rolled again once it can't be doubled. With buff.hold_aoe on, a
    roll is held for the group like an area buff spell, within the roll's own area.

    /sk3 "Bolter's Roll" (a roll's name; the quotes are optional) arms that roll now
    and Double-Ups it at lowest, so a Bust cannot happen: it stops on the lucky
    number, and otherwise on the highest total no die can bust, and Snake Eye still
    turns a 10 into an 11. It goes with automation stopped and with Rolls switched
    off, ahead of healing; between Double-Ups the rest goes as usual. While it runs,
    the rolls kept up wait. Once it holds, that same total is not gambled on by a
    higher Risk. mem.cor.shot is the roll until then; mem.cor.safe is the total held.
]]--

local buff = require('behaviors.buff')
local can = require('core.can')
local lang = require('core.lang')
local util = require('core.util')

local cor = {}

cor.JOB = 17
cor.RISKS = { 'lowest', 'medium', 'highest' }
cor.DOUBLE_GAP = 6  -- seconds between Double-Ups, from the send and from its total (in-game proven, v2)
cor.WAIT = 5        -- seconds a roll or Double-Up sent waits for its total

local DOUBLE_UP_CHANCE, BUST, SNAKE_EYE = 308, 309, 357  -- statuses
local ROLL, ROLL_SUB, DOUBLED, BUSTED, BUSTED_SUB = 420, 421, 424, 426, 427  -- 0x028 messages

local MAX_TOTAL = 11           -- 12 or more busts
local ZERO_RISK_MAX = 5        -- 5 + 6 = 11: no die busts from here
local UNLUCKY_REROLL_MAX = 8   -- past 8 a die busts more often than not

-- The roll packets -----------------------------------------------------------

local last  -- { id = catalog id, total, die, at, bust, doubled }: the last roll, as the server said it
local totals, totals_at = {}, {}  -- [catalog id] = each roll's last total (none once it busts), and when

-- One of your job ability packets, on your own target entry: `id` the catalog
-- id (on a Double-Up the server names the roll doubled), `total` its param,
-- `die` its info.
function cor.rolled(id, total, message, now, die)
    local bust = message == BUSTED or message == BUSTED_SUB or (message == DOUBLED and total > MAX_TOTAL)
    if bust or message == ROLL or message == ROLL_SUB or message == DOUBLED then
        last = { id = id, total = total, die = die, at = now, bust = bust or nil, doubled = message == DOUBLED or nil }
        totals[id], totals_at[id] = not bust and total or nil, now
    end
end

cor.ability = cor.rolled
function cor.last() return last end
function cor.totals() return util.shallow_copy(totals) end
-- The roll `id` is seen down: its total goes, but not one newer than WAIT,
-- whose status may not show yet.
function cor.forget(id, now)
    if totals_at[id] and now - totals_at[id] >= cor.WAIT then totals[id], totals_at[id] = nil, nil end
end
function cor.clear() last, totals, totals_at = nil, {}, {} end
cor.zone = cor.clear
function cor.read(g) g.roll, g.roll_totals = last, cor.totals() end

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
-- 'max' (another roll at 11 with roll.max_at_11: no bust) doubles until 11.
function cor.decide(total, lucky, unlucky, risk, snake_ready, fold_ready)
    if total >= MAX_TOTAL then return 'stop' end
    if risk == 'max' then return (snake_ready and total == MAX_TOTAL - 1) and 'snake_eye' or 'double' end
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

-- A typed roll name: case and the apostrophe aside ("bolters roll", "\"Bolter's Roll\""),
-- or the ability's Japanese name as the DAT spells it.
local function norm_name(s)
    return (s:lower():gsub('^"+', ''):gsub('"+$', ''):gsub('\'', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

function cor.roll_named(cat, name)
    if not name or name == '' then return nil end
    local want = norm_name(name)
    if want == '' then return nil end
    for _, a in ipairs(cat) do
        if a.lucky and (norm_name(a.name) == want or (a.jp or '') ~= '' and norm_name(a.jp) == want) then return a end
    end
end

-- Arm `roll` (a catalog record): the next decisions cast it, then Double-Up at lowest.
-- A roll already armed is replaced. `mem` is the engine's memory.
function cor.order(mem, roll)
    local st = mem.cor or { sent = {} }
    mem.cor = st
    st.shot = { id = roll.id }
    st.safe = nil
end

function cor.pending(mem)
    local st = mem.cor
    return st ~= nil and st.shot ~= nil
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

local function up(a, g) return not can.lacks(a, g.me) end

-- One commanded roll (/sk3 "Bolter's Roll"): cast it, then Double-Up at lowest until
-- it holds. Runs ahead of healing and while you rest, and with Rolls switched off.
-- A Bust already up is Folded first so the roll has a slot; a Bust of this roll ends
-- it (Folded when Fold can go now). The total it holds is mem.cor.safe, so the risk
-- picked does not gamble on that same roll.
function cor.shot(g, cat, _, mem)
    local st = mem.cor
    local shot = st and st.shot
    if not shot then return nil end
    local roll
    for _, a in ipairs(cat) do
        if a.id == shot.id and a.lucky then roll = a end
    end
    if not roll then st.shot = nil; return nil end
    local fold, double, snake = named(cat, 'Fold'), named(cat, 'Double-Up'), named(cat, 'Snake Eye')
    local buffs = g.me.buffs
    local r = g.roll
    local ours = shot.sent and r and r.id == shot.id and r.at >= shot.sent

    if buffs[BUST] or (ours and r.bust) then
        if ours and r.bust and not ready(fold, g) then st.shot = nil; return nil end
        if ready(fold, g) then
            return { action = fold, once = true, why = 'Bust',
                     sent = ours and function () st.shot = nil end or nil }
        end
        if not fold then st.shot = nil end  -- no Fold: the roll cannot take the slot
        return nil
    end

    if not shot.sent then
        if not can.use(roll, g) then return nil end
        return { action = roll, once = true, why = 'asked',
                 sent = function (now) shot.sent, st.sent[roll.id] = now, now end }
    end

    if not ours then
        if g.now - shot.sent < cor.WAIT then busy(mem, shot.sent + cor.WAIT); return nil end
        st.shot = nil  -- its total never came: leave the roll as it is
        return nil
    end

    -- Same gap as the rolls kept up. lowest, never the risk picked and never max_at_11:
    -- a Bust is not a risk this command takes.
    if buffs[DOUBLE_UP_CHANCE] and up(roll, g) and double then
        local decision = (buffs[SNAKE_EYE] and r.total < MAX_TOTAL) and 'double'
            or cor.decide(r.total, roll.lucky, roll.unlucky, 'lowest', ready(snake, g), ready(fold, g))
        if decision == 'stop' then
            st.safe, st.shot = { id = r.id, at = r.at }, nil
            return nil
        end
        local gap = math.max(st.doubled or -math.huge, r.doubled and r.at or -math.huge) + cor.DOUBLE_GAP
        local _, _, wait = can.use(double, g)
        if g.now < gap or wait then busy(mem, math.max(gap, g.now + (wait or 0))); return nil end
        if not ready(double, g) then return nil end
        return { action = double, once = true, mods = decision == 'snake_eye' and { snake } or nil,
                 why = ('%s at %d'):format(roll.name, r.total),
                 sent = function (now) st.sent[roll.id], st.doubled = now, now end }
    end
    -- The total is in and the chance is not, yet: the buff can trail the packet.
    if g.now - r.at < cor.WAIT then busy(mem, r.at + cor.WAIT); return nil end
    st.shot = nil
    return nil
end

-- The roll picked that stands at 11 while roll.max_at_11 is on, other than
-- `but`: the risk is 'max' while it's up.
function cor.eleven(g, cat, cfg, but)
    if not cfg.roll.max_at_11 then return nil end
    for _, a in ipairs(cor.picked(cat, cfg, g.main)) do
        if a ~= but and (g.roll_totals or {})[a.id] == MAX_TOTAL and up(a, g) then return a end
    end
end

-- For the Rolls section: the roll at 11 while the other picked is under it, so is
-- doubled at max risk.
function cor.maxed(g, cat, cfg)
    local rolls = cor.picked(cat, cfg, g.main)
    for i in ipairs(rolls) do
        local other = rolls[3 - i]
        local e = other and (g.roll_totals or {})[other.id] ~= MAX_TOTAL and cor.eleven(g, cat, cfg, other)
        if e then return e end
    end
end

function cor.want(g, cat, cfg, mem)
    local rolls = cor.picked(cat, cfg, g.main)
    if not rolls[1] then return nil end
    local st = mem.cor or { sent = {} }  -- sent[id]: when the roll or its Double-Up last went
    mem.cor = st
    local fold, double, snake = named(cat, 'Fold'), named(cat, 'Double-Up'), named(cat, 'Snake Eye')
    local buffs = g.me.buffs
    for _, a in ipairs(rolls) do
        if not up(a, g) then cor.forget(a.id, g.now) end
    end
    if st.shot then return nil end  -- a commanded roll owns doubling until it holds or gives up

    -- A Bust takes a roll's place until it wears; Fold frees it at once.
    if buffs[BUST] and ready(fold, g) then return { action = fold, why = 'Bust' } end

    -- The last roll, doubled while it's worth it; until it's settled, no new roll.
    -- Only a total newer than every send: a roll sent since may own the Double-Up Chance.
    -- A total /sk3 "<roll>" already held at lowest is not gambled on by the risk picked.
    local r = g.roll
    local roll, newest = nil, -math.huge
    for _, at in pairs(st.sent) do newest = math.max(newest, at) end
    for _, a in ipairs(rolls) do if r and not r.bust and a.id == r.id then roll = a end end
    if st.safe and not (r and st.safe.id == r.id and st.safe.at == r.at and not r.bust) then st.safe = nil end
    if not st.safe and roll and r.at >= newest and buffs[DOUBLE_UP_CHANCE] and up(roll, g) and double then
        local decision = (buffs[SNAKE_EYE] and r.total < MAX_TOTAL) and 'double'
            or cor.decide(r.total, roll.lucky, roll.unlucky, cor.eleven(g, cat, cfg, roll) and 'max' or cfg.roll.risk,
                ready(snake, g), ready(fold, g))
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

    -- With max_at_11, the other roll up under 11 and past doubling (rolled before the
    -- 11, or its Double-Up Chance gone) is rolled again, to chase 11 at max risk.
    for _, a in ipairs(rolls) do
        local total = (g.roll_totals or {})[a.id]
        if total and total < MAX_TOTAL and up(a, g) and can.use(a, g) and cor.eleven(g, cat, cfg, a) then
            local near, away = buff.area(a, g, cfg.buff.hold_aoe, nil, can.yalms(a.area))
            if away then buff.wait_for(mem, a, near, away); return nil end
            return { action = a, why = ('at %d, for 11'):format(total), sent = function (now) st.sent[a.id] = now end }
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

cor.behaviors = {
    -- Ahead of healing: the command asked for it now. `always` so Rolls may be off;
    -- `resting` so it still goes while /heal is on (the roll stands you up).
    { name = 'roll_shot', run = cor.shot, before = 'first', always = true, resting = true, shown = 'roll' },
    { name = 'roll', run = cor.want, before = 'buff' },
}

-- The rolls kept up (names, '' for none; the second only on a COR main job) and
-- how far Double-Up chases a total: 'lowest' | 'medium' | 'highest';
-- `max_at_11`: while one stands at 11, the other is doubled until it's 11 too.
cor.settings = { roll = { on = true, first = '', second = '', risk = 'medium', max_at_11 = false } }

-- Sidekick Settings: Rolls, for a job with rolls (ui/model.lua).
cor.ui = {
    section = { id = 'roll', title = 'Rolls', header = 'Buff', before = 'pet' },
    set = { ['roll.first'] = 'name', ['roll.second'] = 'name', ['roll.risk'] = { list = cor.RISKS },
            ['roll.max_at_11'] = 'bool' },
}

-- The view's `roll`: the rolls to pick from, the last one's total and the one at 11
-- doubling the other at max risk; and whether it's shown.
function cor.ui.view(cat, cfg, g)
    local rolls, done = {}, nil
    for _, a in ipairs(cat) do
        if a.lucky then
            rolls[#rolls + 1] = { name = a.name, label = lang.f('%s (%s)', lang.name(a.name, a.jp), lang.t(a.note)),
                                  lucky = a.lucky, unlucky = a.unlucky }
            -- While it's on you, or just busted (it's gone then).
            if g.roll and g.roll.id == a.id and (g.roll.bust or can.any(g.me.buffs, a.status)) then
                done = { name = a.name, total = g.roll.total, lucky = a.lucky, unlucky = a.unlucky, bust = g.roll.bust == true }
            end
        end
    end
    table.sort(rolls, function (x, y) return x.label < y.label end)  -- as shown: by name, its note after it
    return { first = cfg.roll.first, second = cfg.roll.second, risk = cfg.roll.risk, risks = cor.RISKS,
             two = g.main == cor.JOB, choices = rolls, last = done, max_at_11 = cfg.roll.max_at_11,
             eleven = (cor.maxed(g, cat, cfg) or {}).name }, rolls[1] ~= nil
end

return cor
