-- A player in the alliance's other parties, under the danger line. Healing them is opt-in (Heal > Alliance,
-- heal.alliance): with it on, a heal lands on them; with it off, none goes for 8 seconds.
return {
    about = 'an alliance member at 40% HP: healed only with Alliance healing on',
    run = function (t)
        local who = t.ally()
        local on = t.cfg().heal.alliance
        t.start()
        t.settle()
        t.gm.hp_pct(who, 40)
        if on then
            t.lands(t.expect({ behavior = 'heal', on = who }, 10), 15)
        else
            t.note('alliance healing is off (Sidekick Settings: Heal > Alliance): expecting no heal')
            t.expect_none({ behavior = 'heal', on = who }, 8)
        end
    end,
}
