# Sidekick3

Ground-up rewrite of [Sidekick](https://github.com/seekey13/Sidekick), the support-automation addon for Ashita v4 on [CatsEyeXI](https://www.catseyexi.com/).

**Status: in development, not yet automating.** Use Sidekick v2 to play. v3 can be loaded alongside it.

## What's different

v2 described every job's spells and abilities by hand in 22 job files. v3 reads them from the game: the client's spell and ability data gives levels, costs, recasts, ranges and targets, and the server's learned-spell and ability lists say what your character has. All that's left by hand is [core/knowledge.lua](core/knowledge.lua), one row per spell family describing what it is *for* (heal, buff, cure a status...), shared by every job.

## Use

```
/addon load sidekick3
/sk3 state              what Sidekick reads from the game: party, trusts, buffs, target, flags
/sk3 catalog            what Sidekick can automate for your current job, by role
/sk3 catalog unknown    usable actions no knowledge row covers
/sk3 dump               write the client's spell/ability/status data to tests/data/
```

## Develop

Needs `luajit` and `luacheck`.

```
luajit tests/run.lua      unit tests, against the dumped client data in tests/data/
luacheck .
```

`tools/parity.lua` checks the catalog against v2's job files. Run it from a v2 checkout next to this one: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`.
