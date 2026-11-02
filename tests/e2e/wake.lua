-- A party member asleep at full HP: a heal that wakes (Cure, Curaga) on them, and they wake.
local SLEEP = 2

return {
    about = 'a sleeping party member gets a heal that wakes them',
    run = function (t)
        local who = t.member()
        t.need(t.cfg().wake.on, 'waking is off (Wake)')
        t.start()
        t.settle()
        t.gm.effect(who, 'sleep', 1, 60)
        local sent = t.expect({ behavior = 'wake', on = who }, 10)
        t.lands(sent, 10)
        t.wait_for(function () local u = t.unit(who); return u and not u.buffs[SLEEP] end, 8, who .. ' awake')
    end,
}
