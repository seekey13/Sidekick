# Sidekick3

Ground-up rewrite of [Sidekick](https://github.com/seekey13/Sidekick), the support-automation addon for Ashita v4 on [CatsEyeXI](https://www.catseyexi.com/).

**Status: in development.** It heals (with critical-HP boosts and a focus target), removes debuffs, raises, and keeps up buffs you turn on, for you, your party and trusts. No window yet: everything is a `/sk3` command. Sidekick v2 can stay loaded alongside it, but don't run both at once.

## What's different

v2 described every job's spells and abilities by hand in 22 job files. v3 reads them from the game: the client's spell and ability data gives levels, costs, recasts, ranges and targets, and the server's learned-spell and ability lists say what your character has. All that's left by hand is [core/knowledge.lua](core/knowledge.lua), one row per spell family describing what it is *for* (heal, buff, cure a status...), shared by every job.

## Use

```
/addon load sidekick3
/sk3                    open or close the window
/sk3 help               the command list
/sk3 plan               what it would do right now, without doing it
/sk3 start | stop       automation on / off (always off after a load)
/sk3 buff Haste p1 p2   keep a buff up on those targets (me, p1-p5); "off" turns it off
/sk3 buff Barfira       for pick-one groups (bar-elements, enspells, storms) name the spell
/sk3 buff               list the buffs that are on
/sk3 focus Name | off   heal this member first, at a higher threshold
/sk3 state              what Sidekick reads from the game: party, trusts, buffs, target, flags
/sk3 catalog [unknown]  what it can automate for your job, by role (or what it can't)
/sk3 log                print each action as it's sent (on while in development)
/sk3 dump               write the client's spell/ability/status data to tests/data/
```

Settings are kept per job pair in `config/addons/sidekick3/<character>/WHM_BLM.lua`. Healing, removal and raising are on by default; buffs only when you turn them on.

## Develop

Needs `luajit` and `luacheck`.

```
luajit tests/run.lua      unit tests, against the dumped client data in tests/data/
luacheck .
```

`tools/parity.lua` checks the catalog against v2's job files. Run it from a v2 checkout next to this one: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`.
