# Sidekick3

Ground-up rewrite of [Sidekick](https://github.com/seekey13/Sidekick), the support-automation addon for Ashita v4 on [CatsEyeXI](https://www.catseyexi.com/).

**Status: in development.** It heals by urgency: the most HP for your MP or TP when someone is hurt, the fastest heal when they're in danger, a boost (Divine Seal, Accession...) when they're critical. It weighs area cures and Regen against single cures, learns what your cures really heal, and has a focus target. It also removes debuffs (with items too, when you turn them on), wakes sleepers, raises, keeps up buffs you turn on, recovers MP and TP (Convert, Devotion, Aspir, Meditate...), looks after your pet (Repair, Spirit Link, sending it in), keeps a Corsair's rolls up and Double-Ups them, and can follow a member and rest when there's nothing to do, for you, your party and trusts, your alliance, and players outside it you track. Sidekick v2 can stay loaded alongside it, but don't run both at once.

## What's different

v2 described every job's spells and abilities by hand in 22 job files. v3 reads them from the game: the client's spell and ability data gives levels, costs, recasts, ranges and targets, and the server's learned-spell and ability lists say what your character has. All that's left by hand is [core/knowledge.lua](core/knowledge.lua), one row per spell family describing what it is *for* (heal, buff, cure a status...), shared by every job.

## Use

```
/addon load sidekick3
/sk3                    open or close the window
/sk3 help               the command list
/sk3 plan               what it would do right now, without doing it
/sk3 start | stop       automation on / off (always off after a load)
/sk3 buff Haste p1 b0   keep a buff up on those targets (me, p1-p5, b0-c5 for the alliance, a tracked player's name); "off" turns it off
/sk3 buff Barfira       for pick-one groups (bar-elements, enspells, storms) name the spell; a Japanese client may name it in Japanese
/sk3 buff               list the buffs that are on
/sk3 focus Name | off   heal this member first, on its own HP lines
/sk3 follow Name | off  follow this member
/sk3 rest [on | off]    rest for MP when there's nothing to do
/sk3 profile [Name]     load a settings profile (default: back to your own settings); with no name, list them
/sk3 track [Name]       look after a player outside your alliance too: your target, or by name; else list them
/sk3 untrack Name | all stop tracking them
/sk3 state              what Sidekick reads from the game: party, trusts, buffs, target, flags
/sk3 catalog [unknown]  what it can automate for your job, by role (or what it can't)
/sk3 log                print each action as it's sent (on while in development)
/sk3 dump               write the client's spell/ability/status data to tests/data/
```

The HUD (`/sk3`) shows the party as Sidekick reads them, and what it will do next:

- **A card per member**: HP and MP bars with their %, the name, and the slot (ME, P1-P5), then one per tracked player (T1, T2..., HP only). The name and HP % turn red under your critical line, the slot and MP % under your Recover MP line. Hover a card for its distance and statuses, and whether it's a trust, tracked, KO or away.
- **The alliance's other parties** under the cards: a thin HP bar each, with its slot (B0-B5, C0-C5) and name, each party after a gap.
- **An arrow** at the member the next action is for, labelled like `Heal:Cure IV`: yellow while running, grey while stopped (what it would do). An action on you, your pet or the enemy points at your own card.
- **The title row**: hover it for your job, what Sidekick is doing or why it's waiting (casting, moving, safe zone...), your battle target and pet. Its icons start and stop automation, open SK Settings, and close the HUD.

Drag the HUD where you want it; Lock position keeps it there.

**SK Settings**, from the cog, has every setting under collapsing headers, each section with its on/off switch:

- **Profiles**: named snapshots of your settings (Dynamis, EXP...), each job pair with its own. Type a name and Save (with a profile loaded, a new name renames it; never over another profile), Save as (over one of that name too), New (every setting back to its default) or Delete; click one to load it. Your settings stay the working copy: changes after a load are kept, but reach the profile only when you Save it, and Default brings back the settings you had before you loaded one. A profile never changes the HUD, the Japanese client, following, the focus member or who healing skips.
- **Follow**: who to follow and how far they may get.
- **Heal**: healing, with its HP lines (danger, critical, and the focus member's own), gear potency and who to heal: the alliance's other parties too when you tick Heal the alliance, each of their parties then on a line of its own to untick; raising.
- **Remove**: waking sleepers (when one of your heals can), and debuff removal: spells, then items (Echo Drops, Remedy...) with how many you carry.
- **Buff**: Hold area buffs for the group, so Protectra, a bar-element or a song waits until the players in your party who lack it are near you (trusts follow and never hold it), and, while one waits that someone near you lacks too, says "Gather together for <spell>" in party chat every 5 seconds (one far player missing it is waited for quietly; untick Ask them to gather to always hold quietly); then each row picks a tier ("Auto" casts the best you can) or, for pick-one groups like bar-elements and songs, the spell; and the targets, ME and P1-P5, and when the spell can go outside the party, T1... for tracked players and a line each for the alliance's other parties, B0-B5 and C0-C5. On a Scholar, a row's stratagem chips fire one just before its spell: Pen (Penury) and Cel (Celerity) for white magic, Per (Perpetuance) for white enhancing, Par (Parsimony) and Ala (Alacrity) for black, each only under its Arts and while a charge is left; Acc (Accession) instead casts the spell on you for everyone in your party near you whenever one of the row's targets there lacks it (as v2), and waits for the group like an area buff. Under Heal, Keep a stratagem for healing (off by default) stops buff rows spending the last charge, so healing has one for Accession or Rapture. A spell that needs an Addendum you don't have up (Raise II, Reraise, Cursna...) goes through Enlightenment under Dark Arts, fired for it by itself. On a Corsair, **Rolls** keeps the rolls you pick up on you (Roll 2 on a Corsair main job only; none is picked at first) and Double-Ups the last one rolled by the Risk you pick, as v2: Lowest banks the lucky number and never risks a Bust past 5; Medium (the default) also chases lucky while it's one die away and doubles off the unlucky number up to 8; Highest goes for 11 while Fold is ready to undo a Bust. Every risk turns 10 into 11 with Snake Eye, and Fold clears a Bust whenever it's ready. A new roll waits until the last one is done doubling, and Hold area buffs for the group holds a roll too, for the players in your party within its area (about 8 yalms). Each die, total and Bust is printed while the action log is on, and resting waits while a roll is still being doubled.
- **Pet**, for a pet job: its HP line, and its care and send rows. Sending the pet in is opt-in, row by row; Repair, Maintenance and Reward need their oil or pet food worn.
- **Recover**: MP and TP lines (and the TP Chivalry spends from); resting for MP out of combat after a few quiet seconds, standing at full MP or when the leader leaves.
- **Tracked**: the players you track, each with Untrack, and Track for your target when it's a player outside your party and alliance.
- **UI / Log**: the HUD's bar and font sizes, spacing, panel opacity and lock; the action log and the last 10 actions sent, and why; Japanese client, shared by every job pair as the HUD is: spell, ability and item names (and the gather line) go out in Japanese, and Sidekick warns once in chat about any name the client has no Japanese spelling for, since it then goes out in English.

Each row turns a family on or off and says whether it's ready or why not.

**Tracked players** are looked after like members with whatever reaches outside a party: Cure and Curing Waltz, Protect, Shell, Haste, the -na spells, raises, following. Regen, Refresh, Erase and Healing Waltz can't go on them, and an area spell cast from you or a member (Curaga, Esuna, Protectra) lands on your own party only, so it never counts them. Only their HP % can be read: Sidekick `/check`s them for their level to estimate their max HP (they see that you examined them, as in v2; an /anon player is sized like you). Tracking lasts until Sidekick3 is reloaded; a buff row remembers them by name, so tracking them again brings their buffs back.

**The alliance's other two parties** are looked after with the same spells: raised, woken, cleared with the -na spells and buffed on their chips, and healed only when Heal the alliance is on (off by default, as in v2: their parties have healers of their own) or when one is your focus; healing then ranks them by urgency alone, like your party. An area spell lands on its target's party alone, so each party is weighed on its own: Curaga, Esuna and Protectra cast from you or a member never reach them, while a Cure spread by Majesty or Accession and aimed at one of them covers their party near them. Their statuses come from what the game reports around you, as a trust's do. A mob another party of the alliance claimed has no `<bt>` in the client, though you fight it too: Sidekick then takes the nearest one within 21 yalms claimed by anyone in the alliance as your battle target, as v2 did, and aims at it by its id.

The UI is one replaceable file: put your own in `ui/custom.lua` and it's used instead. [ui/README.md](ui/README.md) documents what a UI is given and what it can change, with an example.

Settings are kept per job pair in `config/addons/sidekick3/<character>/WHM_BLM.lua` (its profiles too), and the HUD's in `ui.lua` beside them, shared by every job pair. Healing, removal, waking, raising, recovery and pet care are on by default; buffs, items, sending the pet in, following, resting and healing the alliance only when you turn them on.

## Develop

Needs `luajit` and `luacheck`.

```
luajit tests/run.lua      unit tests, against the dumped client data in tests/data/
luacheck .
```

`tools/parity.lua` checks the catalog against v2's job files. Run it from a v2 checkout next to this one: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`.
