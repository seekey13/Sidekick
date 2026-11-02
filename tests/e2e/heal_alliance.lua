-- A player in the alliance's other parties, under the danger line. Healing them is opt-in (Heal > Alliance,
-- heal.alliance), so the scenario sets it both ways: on, a heal lands on them; off, none goes for 8 seconds.
return {
    about = 'an alliance member at 40% HP: healed with Alliance healing on, not with it off',
    run = function (t)
        local who = t.ally()
        local function at_40()
            t.gm.hp_pct(who, 40)
            t.wait_for(function () return t.who(who).hpp <= 45 end, 5, who .. ' at 40%')  -- else "none sent" proves nothing
        end
        t.start()
        t.setting('heal.alliance', true)
        t.settle()
        at_40()
        t.lands(t.expect({ behavior = 'heal', on = who }, 10), 15)
        t.setting('heal.alliance', false)
        t.settle()
        at_40()
        t.expect_none({ behavior = 'heal', on = who }, 8)
    end,
}
