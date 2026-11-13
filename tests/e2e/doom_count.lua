--[[
    Doom read from its counter (core/buffs.lua, core/packets.lua): on the alliance player, whose statuses come from
    packets, with removal off so no Cursna ends it.
      1. Sidekick reads the Doom from its landing for 50 s while the server counts it down. Each count holds it
         buffs.DOOM_HOLD seconds; before the counter it was dropped at 45 s whatever the server held.
      2. Taken off by a GM: silent to all but them (status_effect_container.cpp sends a player's wear-off to that
         player only), as Holy Water they drink is. Sidekick reads it gone once the counts stop: within DOOM_HOLD.
    Automation stays on throughout (Sidekick's reading of the units is made as it decides): a stop fails it.
    The cleanup takes the Doom off should this fail first.
]]--

local buffs = require('core.buffs')

local DOOM = 15
local HELD = 50  -- seconds Sidekick must read it: past the old 45 s cap, short of the Doom's 60 s

local function clock() return vana and vana.time and vana.time.clock() or os.clock() end

return {
    about = 'Doom on the alliance player, removal off: read the whole time its counter runs, gone once the counts stop',
    timeout = 100,
    run = function (t)
        local who = t.ally()
        t.setting('remove.on', false)
        t.start()
        t.settle()
        local function doomed() local u = t.unit(who); return u ~= nil and u.buffs[DOOM] == true end
        local function running() return (t.status() or {}).running end
        -- One left from the scenario before (cursna_alliance's cleanup tells only them) is held DOOM_HOLD past its
        -- last count: read gone first.
        t.wait_for(function () return not doomed() end, buffs.DOOM_HOLD + 2,
            ('no Doom on %s in Sidekick\'s reading before any was given'):format(who))

        t.gm.effect(who, 'doom', 10, 60)
        local _, read = t.wait_for(doomed, 5, ('Sidekick reading Doom on %s'):format(who))
        t.time('doom_read', read)
        local from = clock()
        local why = t.wait_for(function ()
            if not running() then return 'stopped' end
            if not doomed() then return 'lost' end
            if clock() - from >= HELD then return 'held' end
        end, HELD + 5, 'the Doom held')
        t.check(why ~= 'stopped', 'automation stopped %.1fs after the Doom was read: Sidekick\'s reading went stale',
            clock() - from)
        t.check(why == 'held', 'Sidekick lost the Doom on %s %.1fs after reading it, while the server still counted it '
            .. 'down (each count holds it %ds)', who, clock() - from, buffs.DOOM_HOLD)
        t.note('Doom read on %s for %ds while its counter ran', who, HELD)

        t.gm.uneffect(who, 'doom')
        local _, gone = t.wait_for(function () return not doomed() end, buffs.DOOM_HOLD + 2,
            ('Doom gone from %s in Sidekick\'s reading once its counts stopped'):format(who))
        t.check(running(), 'automation stopped before the Doom was read gone: Sidekick\'s reading went stale')
        t.time('doom_gone', gone)
        t.note('silent removal: read gone %.1fs after, as its counts stopped', gone)
    end,
}
