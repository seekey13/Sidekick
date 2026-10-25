--[[
    Decide the next action. The gates that stop everything are checked once here
    (AFK sleep among them: core/afk.lua, g.afk set by Sidekick3.lua);
    then each behavior, in priority order, may return an intent:
        { action = catalog record, target = unit or nil (you / battle target), why = text }
    or, for what isn't a spell or ability (/heal, /follow):
        { command = text, action = { name = shown name }, why = text }
    The first intent wins. A behavior returning { hold = true } (a cure nearly off
    recast) lets only the quick behaviors after it run until the cure goes out.
    While you rest, only resting runs: it alone decides when to stand.
    While you're Invisible, which any action breaks, only the behaviors marked
    `invisible` run: healing, for a member under their danger line alone, and
    buffs, for the travel buffs alone (Sneak, Invisible, Tonko, Monomi, Spectral
    Jig). Following goes on, and resting may still stand, but none starts. Sneak
    breaks on nothing, so it stops nothing. Your own Invisible goes last of all
    (buff.last), once everything else, members' travel buffs too, is done.
    A buff held for the group to gather (behaviors/buff.lua) leaves mem.gather,
    which engine.gather turns into a party chat line.
    An intent may name a status of yours to cancel a moment into its cast
    (intent.cancel: Utsusemi's last shadow, jobs/nin.lua; Pianissimo under an
    area song, jobs/brd.lua), which engine.cancel says when to send.
    Modifiers: an intent may list intent.mods (stratagems a buff row turned on,
    Snake Eye before a Double-Up, Blaze of Glory before a luopan, Entrust before
    an Indi- on a member, Embolden before enhancing magic, Pianissimo before a
    song on one member), and an Addendum
    spell you lack the Addendum for has action.via (Enlightenment), as an
    Unbridled spell does (Unbridled Learning, jobs/blu.lua).
    One whose status isn't on you goes first, alone; its status is then taken as
    on you for EXPECT seconds, so the next decision sends the spell.
]]--

local buff = require('behaviors.buff')
local can = require('core.can')
local pet = require('behaviors.pet')
local status = require('core.status')
local util = require('core.util')

local engine = {}

-- Priority order. `quick` behaviors still run while a cure is held for; `setting`
-- is the cfg table whose `on` switches it, when not its name; `shown` the name its
-- intents go by (the HUD's 'Buff:', the log), when not its own; `invisible` ones
-- still run while you're Invisible (each narrows itself then).
engine.BEHAVIORS = {
    -- Light Arts: ahead of healing, which is cheaper under it, but for a critical member (behaviors/buff.lua).
    { name = 'first', run = buff.first, setting = 'buff', shown = 'buff', invisible = true },
    { name = 'heal', run = require('behaviors.heal').want, invisible = true },
    { name = 'remove', run = require('behaviors.remove'), quick = true },
    { name = 'wake', run = require('behaviors.wake'), quick = true },
    { name = 'recover', run = require('behaviors.recover') },
    { name = 'pet', run = pet.care, quick = true },
    { name = 'revive', run = require('behaviors.revive') },
    { name = 'roll', run = require('jobs.cor').want },
    { name = 'rune', run = require('jobs.run').want, quick = true },
    { name = 'geo', run = require('jobs.geo').want },
    { name = 'buff', run = buff.want, invisible = true },
    { name = 'song', run = require('jobs.brd').want },
    { name = 'pet_send', run = pet.send, setting = 'pet', quick = true },
    { name = 'maneuver', run = require('jobs.pup').want, quick = true },
    -- Your own Invisible (Tonko, Spectral Jig): nothing else goes under it (behaviors/buff.lua).
    { name = 'last', run = buff.last, setting = 'buff', shown = 'buff', invisible = true },
    { name = 'follow', run = require('behaviors.follow').want, invisible = true },
    { name = 'rest', run = require('behaviors.rest'), resting = true },
}

local GATES = { 'loading', 'dead', 'mounted', 'safe', 'afk', 'incapacitated', 'casting', 'moving' }
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
    local holding, invisible = false, g.me.buffs[status.INVISIBLE]
    for _, b in ipairs(engine.BEHAVIORS) do
        if (b.resting or not g.resting) and (b.invisible or not invisible or b.resting and g.resting)
            and cfg[b.setting or b.name].on and (b.quick or not holding) then
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
