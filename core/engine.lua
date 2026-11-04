--[[
    Decide the next action. The gates that stop everything (GATES) are checked
    once here. A town and AFK sleep pause automation; a `manual` behavior still
    runs through that pause (a roll you just named), but not through an event.
    Then each behavior, in priority order, may return an intent:
        { action = catalog record, target = unit or nil (you / battle target), why = text }
    or, for what isn't a spell or ability (/heal, /follow, /equip):
        { command = text, action = { name = shown name }, why = text }
    The first intent wins. A behavior returning { hold = true } (a cure nearly off
    recast) lets only the `quick` behaviors after it run until the cure goes out.
    While you rest only resting runs; while you're Invisible, which any action
    breaks, only the `invisible` behaviors, each narrowing itself.

    An intent may also carry:
      mods    modifiers to fire first (stratagems, Snake Eye, Blaze of Glory, Entrust,
              Embolden, Pianissimo). One not on you that can go now goes first,
              alone; its status is then taken as on you for EXPECT seconds, so the
              next decision sends the spell. One that can't go is skipped: the spell
              goes without it. An action's `via` (Enlightenment for an Addendum spell
              you lack the Addendum for, Unbridled Learning) goes first the same way.
      cancel  a status of yours to cancel a moment into the cast (engine.cancel)
      expect  statuses to take as on you once it's sent
      sent    function (now), called once it's sent
      once    set when the intent is a commanded roll (jobs/cor.lua): Sidekick sends
              it while automation is stopped, and nothing else
    A buff held for the group (behaviors/buff.lua) leaves mem.gather, which
    engine.gather turns into a party chat line.
]]--

local buff = require('behaviors.buff')
local can = require('core.can')
local heal = require('behaviors.heal')
local jobs = require('core.jobs')
local pet = require('behaviors.pet')
local status = require('core.status')
local util = require('core.util')

local engine = {}

-- Priority order. `quick` behaviors still run while a cure is held for; `setting`
-- is the cfg table whose `on` switches it, when not its name; `always` runs with
-- that switch off; `manual` runs through a pause (a town, AFK sleep); `shown`
-- the name its intents go by (the HUD's 'Buff:', the log), when not its own;
-- `invisible` ones still run while you're Invisible (each narrows itself then).
engine.BEHAVIORS = {
    -- Light Arts: ahead of healing, which is cheaper under it, but for a critical member (behaviors/buff.lua).
    { name = 'first', run = buff.first, setting = 'buff', shown = 'buff', invisible = true },
    { name = 'heal', run = heal.urgent, invisible = true },
    -- Removal: after critical and danger healing, ahead of efficient healing.
    { name = 'remove', run = require('behaviors.remove'), quick = true },
    { name = 'heal_efficient', run = heal.efficient, setting = 'heal', shown = 'heal' },
    { name = 'wake', run = require('behaviors.wake'), quick = true },
    { name = 'recover', run = require('behaviors.recover') },
    { name = 'pet', run = pet.care, quick = true },
    { name = 'revive', run = require('behaviors.revive') },
    { name = 'buff', run = buff.want, invisible = true },
    { name = 'pet_send', run = pet.send, setting = 'pet', quick = true },
    -- Your own Invisible (Tonko, Spectral Jig): nothing else goes under it (behaviors/buff.lua).
    { name = 'last', run = buff.last, setting = 'buff', shown = 'buff', invisible = true },
    { name = 'follow', run = require('behaviors.follow').want, invisible = true },
    { name = 'rest', run = require('behaviors.rest'), resting = true, invisible = true },
}
-- The job modules' behaviors, each before the one it names (core/jobs.lua): Rolls, runes
-- and Geomancy before buffs, songs after them, maneuvers after sending the pet in.
for _, list in jobs.each('behaviors') do
    for _, b in ipairs(list) do
        local at
        for i, x in ipairs(engine.BEHAVIORS) do if x.name == b.before then at = i end end
        assert(at, 'a job behavior goes before an unknown one: ' .. tostring(b.before))
        local e = util.shallow_copy(b)
        e.before = nil
        table.insert(engine.BEHAVIORS, at, e)
    end
end

local GATES = { 'loading', 'dead', 'mounted', 'safe', 'afk', 'incapacitated', 'casting', 'moving' }
-- A town, AFK sleep: a manual behavior still runs. Not an event (a cutscene, an NPC
-- you're talking to), a safe zone too, where the client takes no action.
local PAUSE = { safe = true, afk = true }
engine.EXPECT = 2  -- seconds a modifier's status is taken as on you once it's sent
engine.GATHER_EVERY = 5  -- seconds between asks to gather, as v2
engine.CANCEL_AFTER = 1    -- seconds into the cast to cancel intent.cancel, as v2
engine.CANCEL_UNTIL = 1.1  -- ...or as soon as the cast shows until then (can.THROTTLE: no send comes sooner)
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
    return { action = first, expect = first.status, once = intent.once,
             why = ('for %s%s: %s'):format(a.name, on, intent.why) }
end

-- `g` with the statuses expected from modifiers just sent on you: a copy for
-- this decision only, so the HUD and /sk state still show what the game says.
local function expecting(g, mem)
    local extra = nil
    for id, until_ in pairs(mem.expect or {}) do
        if g.now < until_ then extra = extra or {}; extra[id] = true else mem.expect[id] = nil end
    end
    if not extra then return g end
    local me = util.overlay(g.me, { buffs = util.overlay(g.me.buffs, extra) })
    local units = {}
    for i, u in ipairs(g.units) do units[i] = u == g.me and me or u end
    return util.overlay(g, { me = me, units = units })
end

-- The intent for now, or nil and why not. `mem` is the engine's own memory
-- between ticks (behaviors keep theirs in it too).
function engine.decide(g, cat, cfg, mem)
    mem.gather, mem.waiting = nil, nil
    g = expecting(util.overlay(g, { gates = cfg.gates }), mem)  -- the rows' Combat and Idle, for can.gate
    local pause  -- the first of a town or AFK sleep: the reason given, over any gate after it
    for _, gate in ipairs(GATES) do
        if g[gate] then
            if not PAUSE[gate] or g.event then return nil, pause or gate end
            pause = pause or gate
        end
    end
    local holding, invisible = false, g.me.buffs[status.INVISIBLE]
    for _, b in ipairs(engine.BEHAVIORS) do
        if (not pause or b.manual) and (b.resting or not g.resting) and (b.invisible or not invisible)
            and (b.always or cfg[b.setting or b.name].on) and (b.quick or not holding) then
            local intent = b.run(g, cat, cfg, mem)
            if intent and intent.hold then
                holding = true
            elseif intent then
                intent = modifier(intent, g) or intent
                intent.behavior = b.shown or b.name
                return intent
            end
        end
    end
    local w, h = mem.gather, mem.waiting
    local away = w and (w.who.dist and ('%.1fy away'):format(w.who.dist) or 'not in sight')
    return nil, pause or g.resting and 'resting' or holding and 'waiting for a cure'
        or w and ('holding %s: %s %s'):format(w.action.name, w.who.name, away)
        or h and ('holding %s for %s'):format(h.action.name, h.mod.name)
        or invisible and 'invisible' or 'nothing to do'
end

-- The party chat line asking everyone to gather for the buff held on this
-- decision (when someone near you lacks it too), at most every GATHER_EVERY
-- seconds; nil when there's none to send.
function engine.gather(g, cfg, mem)
    local w = mem.gather
    if not (w and w.ask and cfg.buff.gather) or g.now - (mem.gathered_at or -math.huge) < engine.GATHER_EVERY then return nil end
    mem.gathered_at = g.now
    local a = w.action
    if cfg.ui.japanese then return '/p ' .. GATHER_JP .. '  ' .. util.spelled(a.name, a.jp, true) end
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

-- The status of yours to cancel now for the intent last sent, or nil: once
-- CANCEL_AFTER seconds have passed since the send, and only while that cast goes
-- on (one cut short before then keeps it); a cast that shows late (lag) is waited
-- for until CANCEL_UNTIL. Cleared once sent or past that.
function engine.cancel(g, mem)
    local c = mem.cancel
    if not c or g.now - c.at < engine.CANCEL_AFTER then return nil end
    if not g.casting and g.now - c.at < engine.CANCEL_UNTIL then return nil end  -- not shown yet
    mem.cancel = nil
    if g.casting and g.me.buffs[c.id] then return c.id end
end

-- Record a send: the throttle restarts, a modifier's status is expected, a
-- status to cancel mid-cast is noted (engine.cancel), and the intent's behavior is told.
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
