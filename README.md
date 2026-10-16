# Sidekick3

Ground-up rewrite of [Sidekick](https://github.com/seekey13/Sidekick), the support-automation addon for Ashita v4 on [CatsEyeXI](https://www.catseyexi.com/).

**Status: in development.** It heals by urgency: the most HP for your MP or TP when someone is hurt, the fastest heal when they're in danger, a boost (Divine Seal, Accession...) when they're critical. It weighs area cures and Regen against single cures, learns what your cures really heal, and has a focus target. It also removes debuffs (with items too, when you turn them on), wakes sleepers, raises, keeps up buffs you turn on, recovers MP and TP (Convert, Devotion, Aspir, Meditate...), looks after your pet (Repair, Spirit Link, sending it in), and can follow a member and rest when there's nothing to do, for you, your party and trusts. Sidekick v2 can stay loaded alongside it, but don't run both at once.

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
/sk3 focus Name | off   heal this member first, on its own HP lines
/sk3 follow Name | off  follow this member
/sk3 rest [on | off]    rest for MP when there's nothing to do
/sk3 state              what Sidekick reads from the game: party, trusts, buffs, target, flags
/sk3 catalog [unknown]  what it can automate for your job, by role (or what it can't)
/sk3 log                print each action as it's sent (on while in development)
/sk3 dump               write the client's spell/ability/status data to tests/data/
```

The window (`/sk3`) does what the commands do and shows what Sidekick sees:

- **Start / Stop**, and what it would do right now, or why it's waiting (casting, moving, safe zone...).
- **Party**: everyone as Sidekick reads them: HP against your danger and critical lines, MP, distance, statuses; then your battle target, pet and the flags that stop automation.
- **Recent actions**: the last 10 sent, and why.
- **A section per behavior** (Healing, Debuffs, Buffs, Raise, Recovery, Pet), each with its on/off switch. Each row turns a family on or off and says whether it's ready or why not; item rows under Debuffs (Echo Drops, Remedy...) also show how many you carry. Buff rows also pick a tier ("Auto" casts the best you can) or, for pick-one groups like bar-elements and songs, the spell; and the targets, ME and P1-P5. Healing has its HP lines (danger, critical, and the focus member's own), gear potency, who to heal and whether to wake sleepers above its rows; Recovery its MP and TP lines (and the TP Chivalry spends from); Pet its HP line. Sending the pet in is opt-in, row by row; Repair, Maintenance and Reward need their oil or pet food worn.
- **Follow & rest**: who to follow and how far they may get; resting for MP out of combat after a few quiet seconds, standing at full MP or when the leader leaves.
- **Options**: Japanese client, action log.

Right-click any section header or tab to lay the sections out as collapsing headers, as tabs, or as Healing / Support / Utility pages of tabs. Right-click empty space in the window to switch between fitting it to its contents and a size you drag (the contents then scroll).

The window is one replaceable file: put your own in `ui/custom.lua` and it's used instead. [ui/README.md](ui/README.md) documents what a UI is given and what it can change, with an example.

Settings are kept per job pair in `config/addons/sidekick3/<character>/WHM_BLM.lua`. Healing, removal, waking, raising, recovery and pet care are on by default; buffs, items, sending the pet in, following and resting only when you turn them on.

## Develop

Needs `luajit` and `luacheck`.

```
luajit tests/run.lua      unit tests, against the dumped client data in tests/data/
luacheck .
```

`tools/parity.lua` checks the catalog against v2's job files. Run it from a v2 checkout next to this one: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`.
