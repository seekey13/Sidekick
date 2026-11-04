-- A party member dies: Sidekick raises them, and the Raise lands. Their raise menu is their own game's to take; the
-- cleanup revives them at their home point and brings them back.
return {
    about = 'a dead party member gets a Raise that lands',
    timeout = 120,
    run = function (t)
        local who = t.member()
        t.need(t.cfg().revive.on, 'raising is off (Revive)')
        t.need(t.action('Raise') or t.action('Raise II') or t.action('Raise III'), 'no Raise among Sidekick\'s actions')
        t.start()
        t.settle()
        t.gm.kill(who)
        t.wait_for(function () return t.who(who).dead end, 5, who .. ' dead')
        local sent = t.expect({ behavior = 'revive', on = who }, 15)
        t.lands(sent, 30)
    end,
}
