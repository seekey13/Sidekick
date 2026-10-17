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
    { name = 'buff', run = require('behaviors.buff') },
    { name = 'pet_send', run = pet.send, setting = 'pet', quick = true },
    { name = 'follow', run = require('behaviors.follow').want },
    { name = 'rest', run = require('behaviors.rest'), resting = true },
}

local GATES = { 'loading', 'dead', 'mounted', 'safe', 'incapacitated', 'casting', 'moving' }
engine.GATHER_EVERY = 5  -- seconds between asks to gather, as v2
-- 集まってください。 in Shift-JIS, the game's chat encoding (as the names from the DATs).
local GATHER_JP = '\x8f\x57\x82\xdc\x82\xc1\x82\xc4\x82\xad\x82\xbe\x82\xb3\x82\xa2\x81\x42'

-- The intent for now, or nil and why not. `mem` is the engine's own memory
-- between ticks (behaviors keep theirs in it too).
function engine.decide(g, cat, cfg, mem)
    mem.gather = nil
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
                intent.behavior = b.name
                return intent
            end
        end
    end
    local w = mem.gather
    local away = w and (w.who.dist and ('%.1fy away'):format(w.who.dist) or 'not in sight')
    return nil, g.resting and 'resting' or holding and 'waiting for a cure'
        or w and ('holding %s: %s %s'):format(w.action.name, w.who.name, away) or 'nothing to do'
end

-- The party chat line asking everyone to gather for the buff held on this
-- decision, at most every GATHER_EVERY seconds; nil when there's none to send.
function engine.gather(g, cfg, mem)
    local w = mem.gather
    if not (w and cfg.buff.gather) or g.now - (mem.gathered_at or -math.huge) < engine.GATHER_EVERY then return nil end
    mem.gathered_at = g.now
    local a = w.action
    if cfg.japanese and (a.jp or '') ~= '' then return '/p ' .. GATHER_JP .. '  ' .. a.jp end
    return '/p Gather together for ' .. a.name
end

-- Whether the server will take a command yet.
function engine.ready(g, mem)
    local since_finish = g.now - (g.finished or -math.huge)
    return g.now - (mem.sent_at or -math.huge) >= can.THROTTLE
        and since_finish >= (g.spell_finish and can.SPELL_THROTTLE or can.THROTTLE)
end

-- The chat command for `intent`; `g` names a battle target the client has no <bt> for.
function engine.command(intent, cfg, g)
    return intent.command or can.command(intent.action, intent.target, cfg.japanese, g and g.bt)
end

-- Record a send: the throttle restarts and the intent's behavior is told.
function engine.sent(intent, g, mem)
    mem.sent_at = g.now
    if intent.sent then intent.sent(g.now) end
end

return engine
