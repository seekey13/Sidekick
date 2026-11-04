-- Everyone at full HP and MP with nothing on them: Sidekick, running, sends nothing.
return {
    about = 'nothing to do: no sends',
    run = function (t)
        t.start()
        t.settle()
        t.expect_none({}, 8)
    end,
}
