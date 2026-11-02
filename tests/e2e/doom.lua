-- Doom on a party member: Cursna on them whatever the Debuff switches say, and again once its recast allows while the
-- Doom stays (Cursna takes it off (10 + healing skill / 30)% of the time: one in five at WHM75's skill). 60 seconds
-- of Doom; the cleanup takes it off, or raises them should it run out.
local DOOM = 15
local CURSNA_RECAST = 10  -- seconds (the server's spell_list)

return {
    about = 'a Doomed party member gets Cursna, and again while the Doom stays',
    run = function (t)
        local who = t.member()
        t.need(t.action('Cursna'), 'no Cursna among Sidekick3\'s actions for this job')
        t.start()
        t.settle()
        t.gm.effect(who, 'doom', 10, 60)
        local first = t.expect({ behavior = 'remove', on = who, action = 'Cursna' }, 10)
        local landed = t.lands(first, 10)
        local function gone() local u = t.unit(who); return u and not u.buffs[DOOM] end
        if landed.targets[1].message ~= 75 then  -- not "no effect": it went
            t.wait_for(gone, 5, 'Doom gone from ' .. who)
            t.note('the first Cursna took it')
            return
        end
        t.note('the first Cursna had no effect')
        t.wait_for(function ()
            for _, x in ipairs(t.sends({ action = 'Cursna', on = who })) do if x.seq > first.seq then return x end end
            return gone()
        end, CURSNA_RECAST + 6, 'another Cursna once its recast was up')
    end,
}
