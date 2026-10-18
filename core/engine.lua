--[[
    Decide the next action. The gates that stop everything are checked once here;
    then each behavior, in priority order, may return an intent:
        { action = catalog record, target = unit or nil (you / battle target), why = text }
    or, for what isn't a spell or ability (/heal, /follow):
        { command = text, action = { name = shown name }, why = text }
    The first intent wins. A behavior returning { hold = true } (a cure nearly off
    recast) lets only the quick behaviors after it run until the cure goes out.
    While you rest, only resting runs: it alone decides when to stand.
    A buff held for the group to gather (behaviors/buff.lua) leaves mem.gather,
    which engine.gather turns into a party chat line.
    An intent may name a status of yours to cancel a moment into its cast
    (intent.cancel: Utsusemi's last shadow, jobs/nin.lua).
    Modifiers: an intent may list intent.mods (stratagems a buff row turned on,
    Snake Eye before a Double-Up, Blaze of Glory before a luopan, Entrust before
    an Indi- on a member, Embolden before enhancing magic), and an Addendum
    spell you lack the Addendum for has action.via (Enlightenment).
    One whose status isn't on you goes first, alone; its status is then taken as
    on you for EXPECT seconds, so the next decision sends the spell.
]]--

local can = require('core.can')
local pet = require('behaviors.pet')

local engine = {}

-- Priority order. `quick` behaviors still run while a cure is held for; `setting`
-- is the cfg table whose `on` switches it, when not its name.
engine.BEHAVIORS = {
    { name = 'heal', run = require('behaviors.heal').want },
    { name = 'remove', run = require('behaviors.remove'), quick = true },
    { name = 'wake', run = require('behaviors.wake'), quick = true },
    { name = 'recover', run = require('behaviors.recover') },
    { name = 'pet', run = pet.care, quick = true },
    { name = 'revive', run = require('behaviors.revive') },
    { name = 'roll', run = require('jobs.cor').want },
    { name = 'rune', run = require('jobs.run').want, quick = true },
    { name = 'geo', run = require('jobs.geo').want },
    { name = 'buff', run = require('behaviors.buff').want },
    { name = 'pet_send', run = pet.send, setting = 'pet', quick = true },
    { name = 'maneuver', run = require('jobs.pup').want, quick = true },
    { name = 'follow', run = require('behaviors.follow').want },
    { name = 'rest', run = require('behaviors.rest'), resting = true },
}

local GATES = { 'loading', 'dead', 'mounted', 'safe', 'incapacitated', 'casting', 'moving' }
engine.EXPECT = 2  -- seconds a modifier's status is taken as on you once it's sent
engine.GATHER_EVERY = 5  -- seconds between asks to gather, as v2
-- 集まってください。 in Shift-JIS, the game's chat encoding (as the names from the DATs).
local GATHER_JP = '\x8f\x57\x82\xdc\x82\xc1\x82\xc4\x82\xad\x82\xbe\x82\xb3\x82\xa2\x81\x42'

-- The modifier to send before `intent`'s action, as an intent of its own, or nil.
local function modifier(intent, g)
    local a = intent.action
    local first = a.via and a.requires and not can.any(g.me.buffs, a.requires) and a.via
    for _, m in ipairs(intent.mods or {}) do
        if first then break end
        if m.status and not can.any(g.me.buffs, m.status) and can.use(m, g) then first = m end
    end
    if not first then return nil end
    local on = intent.target and (' -> ' .. intent.target.name) or ''
    return { action = first, expect = first.status, why = ('for %s%s: %s'):format(a.name, on, intent.why) }
end

-- `g` with the statuses expected from modifiers just sent on you: a copy for
-- this decision only, so the HUD and /sk3 state still show what the game says.
local function expecting(g, mem)
    local extra = nil
    for id, until_ in pairs(mem.expect or {}) do
        if g.now < until_ then extra = extra or {}; extra[id] = true else mem.expect[id] = nil end
    end
    if not extra then return g end
    local me = setmetatable({ buffs = setmetatable(extra, { __index = g.me.buffs }) }, { __index = g.me })
    local units = {}
    for i, u in ipairs(g.units) do units[i] = u == g.me and me or u end
    return setmetatable({ me = me, units = units }, { __index = g })
end

-- The intent for now, or nil and why not. `mem` is the engine's own memory
-- between ticks (behaviors keep theirs in it too).
function engine.decide(g, cat, cfg, mem)
    mem.gather, mem.waiting = nil, nil
    g = expecting(g, mem)
    for _, gate in ipairs(GATES) do
        if g[gate] then return nil, gate end
    end
    local holding = false
    for _, b in ipairs(engine.BEHAVIORS) do
        if (b.resting or not g.resting) and cfg[b.setting or b.name].on and (b.quick or not holding) then
            local intent = b.run(g, cat, cfg, mem)
            if intent and intent.hold then
                holding = true
            elseif intent then
                intent = modifier(intent, g) or intent
                intent.behavior = b.name
                return intent
            end
        end
    end
    local w, h = mem.gather, mem.waiting
    local away = w and (w.who.dist and ('%.1fy away'):format(w.who.dist) or 'not in sight')
    return nil, g.resting and 'resting' or holding and 'waiting for a cure'
        or w and ('holding %s: %s %s'):format(w.action.name, w.who.name, away)
        or h and ('holding %s for %s'):format(h.action.name, h.mod.name) or 'nothing to do'
end

-- The party chat line asking everyone to gather for the buff held on this
-- decision (when someone near you lacks it too), at most every GATHER_EVERY
-- seconds; nil when there's none to send.
function engine.gather(g, cfg, mem)
    local w = mem.gather
    if not (w and w.ask and cfg.buff.gather) or g.now - (mem.gathered_at or -math.huge) < engine.GATHER_EVERY then return nil end
    mem.gathered_at = g.now
    local a = w.action
    if cfg.ui.japanese then return '/p ' .. GATHER_JP .. '  ' .. ((a.jp or '') ~= '' and a.jp or a.name) end
    return '/p Gather together for ' .. a.name
end

-- Whether the server will take a command yet.
function engine.ready(g, mem)
    local since_finish = g.now - (g.finished or -math.huge)
    return g.now - (mem.sent_at or -math.huge) >= can.THROTTLE
        and since_finish >= (g.spell_finish and can.SPELL_THROTTLE or can.THROTTLE)
end

-- The chat command for `intent`; `g` names a battle target the client has no <bt> for.
-- The second result is true when a Japanese client is sent an English name (can.command).
function engine.command(intent, cfg, g)
    if intent.command then return intent.command, intent.english end  -- an equip may name its item in English
    return can.command(intent.action, intent.target, cfg.ui.japanese, g and g.bt)
end

-- Record a send: the throttle restarts, a modifier's status is expected, a
-- status to cancel mid-cast is noted (jobs/nin.lua), and the intent's behavior is told.
function engine.sent(intent, g, mem)
    mem.sent_at = g.now
    mem.cancel = intent.cancel and { id = intent.cancel, at = g.now } or nil
    for _, id in ipairs(intent.expect or {}) do
        mem.expect = mem.expect or {}
        mem.expect[id] = g.now + engine.EXPECT
    end
    if intent.sent then intent.sent(g.now) end
end

return engine
