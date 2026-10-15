--[[
    Decide the next action. The gates that stop everything are checked once here;
    then each behavior, in priority order, may return an intent:
        { action = catalog record, target = unit or nil (you / battle target), why = text }
    The first intent wins. A behavior returning { hold = true } (a cure nearly off
    recast) lets only the quick behaviors after it run until the cure goes out.
]]--

local can = require('core.can')

local engine = {}

local THROTTLE = 1.1        -- the server's lockout after any action
local SPELL_THROTTLE = 3.1  -- ...and after a spell, counted from when it lands

-- Priority order. `quick` behaviors still run while a cure is held for.
engine.BEHAVIORS = {
    { name = 'heal', run = require('behaviors.heal') },
    { name = 'remove', run = require('behaviors.remove'), quick = true },
    { name = 'buff', run = require('behaviors.buff') },
    { name = 'revive', run = require('behaviors.revive') },
}

local GATES = { 'loading', 'dead', 'mounted', 'safe', 'incapacitated', 'resting', 'casting', 'moving' }

-- The intent for now, or nil and why not. `mem` is the engine's own memory
-- between ticks (behaviors keep theirs in it too).
function engine.decide(g, cat, cfg, mem)
    for _, gate in ipairs(GATES) do
        if g[gate] then return nil, gate end
    end
    local holding = false
    for _, b in ipairs(engine.BEHAVIORS) do
        if cfg[b.name].on and (b.quick or not holding) then
            local intent = b.run(g, cat, cfg, mem)
            if intent and intent.hold then
                holding = true
            elseif intent then
                intent.behavior = b.name
                return intent
            end
        end
    end
    return nil, holding and 'waiting for a cure' or 'nothing to do'
end

-- Whether the server will take a command yet.
function engine.ready(g, mem)
    local since_finish = g.now - (g.finished or -math.huge)
    return g.now - (mem.sent_at or -math.huge) >= THROTTLE
        and since_finish >= (g.spell_finish and SPELL_THROTTLE or THROTTLE)
end

function engine.command(intent, cfg)
    return can.command(intent.action, intent.target, cfg.japanese)
end

-- Record a send: the throttle restarts and the intent's behavior is told.
function engine.sent(intent, g, mem)
    mem.sent_at = g.now
    if intent.sent then intent.sent(g.now) end
end

return engine
