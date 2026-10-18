# Your own Sidekick3 UI

Sidekick3's UI is one replaceable Lua file. Sidekick does all the deciding and acting; a UI only **shows** a table of data (`view`) and **changes** things through a table of functions (`act`). Anything that keeps to that contract can replace the standard UI: a compact HP list, a bar of on/off switches, one big window instead of two.

[window.lua](window.lua) is the standard UI and the reference: a heads-up display of the party's HP and MP (the **Sidekick3** window), whose cog on your own card opens **SK Settings**, every setting under collapsing headers. It uses nearly every field and every action below.

## Install

1. Write `ui/custom.lua` (copy `ui/window.lua` to start from the standard window, or start from the [example](#example)).
2. `/addon reload sidekick3`, then `/sk3` to open it.
3. To go back, delete or rename `ui/custom.lua` and reload.

When `ui/custom.lua` exists, Sidekick uses it instead of `ui/window.lua`. If it fails to load (a syntax error, say), Sidekick prints the error and uses the standard window. If it raises an error while drawing, Sidekick closes it and prints the error; `/sk3` opens it again. Git ignores `ui/custom.lua`, so updating Sidekick3 leaves it alone.

## The contract

A UI file returns a table with one function:

```lua
local ui = {}

-- Called every frame while the window is open, from Ashita's d3d_present.
function ui.render(view, act)
end

return ui
```

- **It draws everything itself**, its window or windows included (`imgui.Begin` / `imgui.End`).
- **`view` is rebuilt every frame** and is a copy: changing it changes nothing.
- **`act` is the only way to change anything.** Sidekick saves settings for you (see [Saving](#saving)).
- **Every ImGui scope it opens must be closed, even when it errors.** ImGui crashes the game on a `Begin` with no `End`. Guard the inside of the window with `pcall`, end the window, then raise the error, as the example and `window.lua` do.
- **State of its own** (which page is showing, a collapsed panel) lives in locals in the file and lasts until the addon reloads. To keep a preference across reloads, save it under `ui.` with `act.set('ui.<name>', value)` and read it back from `view.ui.<name>`.
- `/sk3` opening and closing the window, the commands, and automation itself don't depend on the UI. A UI with no Start button still runs with `/sk3 start`.

## `view`

Text that may contain `%` (names, `why` text) must be escaped before it's drawn: see [ImGui in Ashita](#imgui-in-ashita).

| Field | Type | What it is |
|---|---|---|
| `job` | string | `'WHM 75 / BLM 37'`, or `'WAR 75'` with no subjob |
| `status` | table | The status line, below |
| `party` | list | You, then your party and trusts, then the players you track, below |
| `alliance` | list | The alliance's other two parties, as `party` lines (kind `'alliance'`, tags `'B0'` to `'B5'` and `'C0'` to `'C5'`); empty outside an alliance. The standard HUD draws them as thin HP rows under the cards |
| `bt` | table or nil | Your battle target: `{ name, hpp, dist }`, `dist` like `'4.3y'`. With no `<bt>` of your party's, the nearest mob another party of the alliance claimed |
| `pet` | table or nil | Your pet, the same shape as `bt` |
| `flags` | list of strings | What may be holding automation up, in this order: `'casting'`, `'moving'`, `'combat'`, `'safe zone'`, `'mounted'`, `'dead'`, `'resting'`, `'incapacitated'`, `'silenced'`, `'amnesia'` |
| `recent` | list | The last 10 actions sent, newest first: `{ age, text, why }`, e.g. `{ 12, 'Cure IV -> Kupipi', 'heal: Kupipi at 62%' }`; `age` in whole seconds |
| `pointer` | table or nil | What automation is about to do, or would do, for the standard HUD's arrow: `{ text, member, ally, live }`. `text` is the behavior then the action, `'Heal:Cure IV'`; a target with no line of its own is added by name (`'Heal:Cure IV -> Name'`). `member` is the index in `party` it is for: the target's, else yours (an action on you, your pet or the enemy, as pet care's `'Pet:Healing Ruby'`). For an alliance member, `ally` is their index in `alliance` and `member` is nil. `live`: running, it is the decision about to go or, for a moment after (longer while it is being cast), what was just sent; stopped (false), what it would do. nil when there is nothing |
| `heal` | table | Healing's settings, below |
| `recover` | table | `{ mp, tp, min_tp, spends_tp }`: recover MP under `mp` % (yours; a member's for Devotion), TP under `tp` (0 to 3000) in combat; Chivalry only from `min_tp` TP. `spends_tp`: a row spends TP (Chivalry), so `min_tp` is worth showing |
| `pet_heal` | number | Heal your pet under this HP % |
| `follow` | table | `{ on, target, distance, names }`: follow `target` (a name, `''` for none) once further than `distance` yalms; `names` are the members (the alliance's and tracked players too) that can be followed |
| `buff` | table | `{ hold_aoe, gather }`: `hold_aoe` holds an area buff spell (Protectra, songs) while a player in your party who lacks it is out of its reach; `gather` then asks them to gather in party chat, at most every 5 seconds, when someone near you lacks it too |
| `roll` | table | Corsair's rolls: `{ first, second, risk, risks, two, choices, last }`. `first` and `second` are the rolls kept up, by name (`''` for none); `two` is true on a Corsair main job, the only one that keeps a second. `risk` is how far Double-Up chases a total, one of `risks`: `'lowest'`, `'medium'`, `'highest'`. `choices` lists every roll you have, by name: `{ name, label, lucky, unlucky }`, as `{ name = 'Corsair\'s Roll', label = 'Corsair\'s Roll (EXP+)', lucky = 5, unlucky = 9 }`. `last` is the last roll's total while it's on you (or it just busted), when it's one of them: `{ name, total, lucky, unlucky, bust }`, else nil. A `second` equal to `first` keeps one roll |
| `geo` | table | Geomancer's luopan: `{ distance, linger, entrust, entrust_spell, indi, names }`. Full Circle recalls the luopan once who it went on is further than `distance` yalms from it (3 to 30), and a debuff's `linger` seconds after combat (1 to 20). Entrust puts the Indi- spell `entrust_spell` (a name from `indi`, every Indi- you have, or `''`) on the member `entrust` (a name from `names`, your party but you, or `''`) |
| `rune` | table | Rune Fencer's runes: `{ slots, runes, sets }`. `slots` is how many runes stand at once at your RUN level, main or sub (1 to 3). `runes` lists every rune you have, `{ name, element, resist, ailments }`, as `{ name = 'Ignis', element = 'Fire', resist = 'Ice', ailments = 'Paralyze / Bind' }`: what it adds to your attacks, the element it resists, the ailments it defends against. `sets` are Idle, then each ward you have (Vallation, Valiance, Pflug): `{ key, label, shows, ward, on, ready, avail, picks }`. `picks` holds a rune name (or `''`) for each of the 3 slots, though only the first `slots` count; set slot `i` with `act.set('rune.<key>_<i>', name)`. `shows` is the field of `runes` the set's picks are best named by (`'element'` for Idle, `'resist'` for Vallation and Valiance, `'ailments'` for Pflug). A ward's set also has `ward` (its name, the row key for `act.row`), `on` (its row), `ready` and `avail` as a row's. Off RUN, `slots` is 0 and `runes` and `sets` are empty |
| `rest` | table | `{ on, delay, distance }`: rest after `delay` seconds with nothing to do; stand when the follow target is further than `distance` yalms |
| `track` | table | `{ target }`: your current target's name when it's a player you could track (not in your party or alliance, not tracked yet), else nil |
| `japanese` | bool | Spell, ability and item names are sent in Japanese. Shared by every job pair: it's kept in `ui`'s file (`ui.japanese`) |
| `log` | bool | Each action sent is printed to chat |
| `profiles` | table | `{ active, names }`: the profile loaded (nil for Default, the working copy) and every saved profile's name, in order, case aside. Each job pair has its own |
| `ui` | table | The UI's settings, shared by every job pair: `open` (bool), and any `ui.<name>` your UI saved. The standard HUD's, which yours may ignore: `hp_width`, `mp_width` (80 to 600), `hp_height` (10 to 120), `mp_height` (4 to 80), `name_size` (8 to 64), `text_size` (8 to 48), `gap` (0 to 40), all in pixels; `opacity` (0 to 100, the panel's %); `locked` (bool, it can't be dragged); `japanese` (bool, the client's language, as `view.japanese`: not free for a UI's own use) |
| `sections` | list | Every setting, by section, below |
| `remote` | list | The SK Settings of other Sidekick sessions on this PC you have open (`act.watch`; sent only while your UI is open), by name: `{ name, view, other }`. `view` is the view that session built and sent (nil until its first one comes, about a second): the same fields as yours but `pointer`, `ui` and `remote`, plus `session` (its name) and `version`. Draw it with `act.remote(name)` in place of `act`. `other` is true (and `view` nil) when that session runs another version of Sidekick3, whose view this one can't draw |
| `session` | string or nil | Only on a view in `remote`: the session it came from. nil on yours |

### `view.status`

| Field | Type | What it is |
|---|---|---|
| `running` | bool | Automation is on |
| `state` | string | `'Running'` or `'Stopped'` |
| `text` | string | Running: the last action sent, or `'nothing sent yet'`. Stopped: what it would do now (`'would: Cure IV -> Kupipi (heal: Kupipi at 62%)'`), or why it wouldn't |
| `dim` | string or nil | Running and not acting: why (`'casting'`, `'safe zone'`, `'nothing to do'`...) |

### `view.party[i]`

| Field | Type | What it is |
|---|---|---|
| `tag` | string | `'ME'`, `'P1'` to `'P5'`; `'T1'`, `'T2'`... for the players you track; in `alliance`, `'B0'` to `'B5'` and `'C0'` to `'C5'` |
| `kind` | string | `'self'`, `'party'`, `'trust'` or `'tracked'` (a player outside your party and alliance you track: `/sk3 track`); `'alliance'` in `alliance` |
| `name` | string | |
| `job` | string or nil | A tracked player's jobs once a `/check` or another session's file has answered: `'WHM 75 / BLM 37'`; nil for everyone else |
| `alive` | bool | |
| `away` | bool | In another zone (its HP and MP are stale), or for a tracked player, out of range (its HP as last seen, or as another Sidekick session on this PC reads it) |
| `tracked` | bool | You track this player: every `'tracked'` line, and a member who joined your party or alliance while tracked (they are tracked again when they leave) |
| `shared` | string or nil | A tracked player another Sidekick session on this PC lists (its party): that session's character name. Tracked while it lists them; untracked by hand, they stay off until tracked again |
| `hpp`, `mpp` | number | HP and MP, 0 to 100 |
| `hp` | string | `'ok'`, `'low'` (under the danger line) or `'critical'` (under the critical line); the focus member's own lines for them |
| `uses_mp` | bool | It has MP: yours when your max MP is over 0; another member's once it has been seen with MP on its current jobs. Never a tracked player's: their MP can't be read (`mpp` is 0) |
| `mp` | string | `'low'` when it uses MP and is under the Recover MP line (`view.recover.mp`), else `'ok'` |
| `dist` | string | `''` for you, `'away'`, or like `'12.3y'` |
| `buffs` | string | Its statuses, the first 6 by name and `'+N'` for the rest |
| `buffs_all` | string | Every status, one per line (for a tooltip) |
| `session` | table or nil | This player is another Sidekick session on this PC (a party member, a tracked player or one of the alliance; never you or a trust): `{ name, running, open }`. `running`: its automation is on; `open`: its SK Settings are shown here (`view.remote`). The standard HUD puts a run icon and a cog on its card, as on yours |

### `view.heal`

`danger`, `critical`, `focus_danger`, `focus_critical` (HP %, 1 to 99); `focus` (a member's name, `''` for none); `alliance` (bool: the alliance's other parties are healed too; the focus member always is); `cure_potency`, `waltz_potency` (+% from gear, 0 to 50); `regen_potency` (+HP per Regen tick from gear, 0 to 30); `reserve` (bool: buff rows leave the last stratagem charge for healing) and `stratagems` (bool: your job has stratagems, so `reserve` is worth showing); `focus_names` (the members that can be the focus, you excluded, the alliance's and tracked players included); `members` (`{ name, healed, wrap }` for each member and tracked player, you excluded, and the alliance's while `alliance` is on; `healed` false when skipped; `wrap` true on the first of each of the alliance's parties, where the standard window starts a line).

### `view.sections[i]`

In this order. A section with rows is left out when your job has none for it (Pet shows only for a pet job), Wake sleepers only shows when one of your heals wakes (a cure or waltz; not a pet's), Rolls only when you have a roll (Corsair), Geomancy only when you have a Geo- spell (a Geomancer main job), and Runes only when you have a rune (Rune Fencer, main or sub).

| `id` | `title` | `header` | Its settings |
|---|---|---|---|
| `'profile'` | Profiles | Profiles | `view.profiles` |
| `'follow'` | Follow | Follow | `view.follow` |
| `'heal'` | Healing | Heal | `view.heal`, rows |
| `'revive'` | Revive | Heal | rows |
| `'wake'` | Wake sleepers | Remove | its switch only |
| `'remove'` | Debuff removal | Remove | rows: spells and abilities, then items |
| `'buff'` | Buffs | Buff | `view.buff`, rows |
| `'roll'` | Rolls | Buff | `view.roll` (a job with rolls only) |
| `'geo'` | Geomancy | Buff | `view.geo`, rows: the Geo row (its luopan's spell and targets), the Geo debuff row, Full Circle, Blaze of Glory, Entrust |
| `'rune'` | Runes | Buff | `view.rune` (a job with runes only) |
| `'pet'` | Pet | Pet | `view.pet_heal`, rows |
| `'recover'` | Recovery | Recover | `view.recover`, rows |
| `'rest'` | Resting | Recover | `view.rest` |
| `'track'` | Tracked players | Tracked | `view.track`, and the `party` and `alliance` lines with `tracked` |
| `'ui'` | UI / Log | UI / Log | `view.ui`, `view.log`, `view.recent`, `view.japanese` |

| Field | Type | What it is |
|---|---|---|
| `id`, `title`, `header` | string | As above. `header` is the collapsing header SK Settings puts it under, headers in the order their first section comes |
| `on` | bool or nil | The section's switch (`act.section`); every section has one but `profile`, `track` and `ui` |
| `rows` | list or nil | One per spell family, pick-one group or item, below; nil for the sections without rows |
| `has_choices`, `has_targets`, `has_mods` | bool or nil | Some row in the section has `choices` / `targets` / `mods` (to lay out columns) |

### `view.sections[i].rows[j]`

| Field | Type | What it is |
|---|---|---|
| `key` | string | The row's id for `act`: a family (`'Cure'`, `'Haste'`), a pick-one group (`'barelement'`, `'minuet'`) or an item (`'Echo Drops'`) |
| `label` | string | `'Cure'`, `'Valor Minuet (+ATK)'`, `'Sword Madrigal / Blade Madrigal'` |
| `on` | bool | Rows start on, except buffs (and a Geomancer's Geo and Geo debuff rows), sending the pet in (Assault, Fight, Deploy) and items |
| `ready` | bool | It could go right now |
| `avail` | string | `'ready'`, or why not: `'recast 12s'`, `'MP'`, `'TP'`, `'silenced'`, `'combat only'`, `'idle only'`, `'no ammo'`, `'pet too far'`, `'none left'`, `'pick one'`, `'not available'`... |
| `action` | string or nil | When ready, the spell, ability or item it would use, as the client names it: `'Cure V'` |
| `count` | number or nil | Item rows (`'Echo Drops'`, `'Remedy'`...): how many you carry |
| `choices` | list or nil | Buff rows (and the Geomancy section's) with tiers or a pick-one group: `{ label, name }`. A tiered row's first choice is `'Auto (best)'` with `name` nil |
| `pick` | string or nil | The chosen `name`; nil is Auto |
| `choice` | string or nil | The label to show for the current pick: `'Auto (best)'`, `'Pick one'`, `'Protect II'`, `'Protect V (not available)'` |
| `targets` | list or nil | Buff rows that can go on others (and the Geo row: its luopan goes on the first of them who lacks it): 6 chips `{ slot, label, present, name, on, wrap }`, `slot` 0 (you, `'ME'`) to 5 (`'P5'`). `present` is false for an empty party slot (`name` is then nil). When the row's spells can go outside the party (Protect, Haste; not Regen), a chip follows for each tracked player, `'T1'` on, its `slot` their name; then 6 for each of the alliance's other parties that is there or has a chip on, `'B0'` to `'B5'` (`slot` 6 to 11) and `'C0'` to `'C5'` (12 to 17). `wrap` is true on `'B0'` and `'C0'`: the standard window starts a new line there |
| `mods` | list or nil | Buff rows a modifier fits (SCH's stratagems, RUN's Embolden): `{ name, label, note, on }`, as `{ 'Penury', 'Pen', 'half the MP', false }`. One that is on is fired just before the row's spell when its status isn't on you; Accession (`'Acc'`) instead spreads the spell from you to the row's targets near you whenever one there lacks it. nil for other rows and jobs |
| `hold` | bool or nil | Rows with `mods`: the spell waits while one of the modifiers on for it can't go with it (on recast, fewer charges than stratagems to fire, the wrong Arts, Accession unable to spread it to someone it would reach, or short of MP for it), as v2's Hold for Stratagem; false, it goes without. A held row's `ready` is false and `avail` says what it waits for (`'waits for Emb: recast 120.0s'`). nil for rows without `mods` |

## `act`

| Function | What it does |
|---|---|
| `act.run(on)` | Automation on or off. This session only: it is always off after a load |
| `act.log(on)` | Print each action sent to chat, or not. This session only |
| `act.close()` | Hide the UI (remembered); `/sk3` shows it again |
| `act.section(id, on)` | A section's switch: `'follow'`, `'heal'`, `'revive'`, `'wake'`, `'remove'`, `'buff'`, `'roll'`, `'geo'`, `'rune'`, `'pet'`, `'recover'` or `'rest'` |
| `act.row(key, on)` | A row on or off |
| `act.pick(key, name)` | A row's choice: a `choices[i].name`, or nil for Auto |
| `act.target(key, slot, on)` | Turn a target chip on or off: its `slot`, 0 to 17 or a tracked player's name; `on` true or false sets it, nil toggles it |
| `act.mod(key, name, on)` | Turn a modifier chip on or off: its `name` (`'Penury'`, `'Accession'`); `on` sets it, nil toggles it |
| `act.hold(key, on)` | A row's Hold: `true`, its spell waits while a modifier on for it can't go with it; `false` (the default), it goes without |
| `act.track(name)` | Track a player outside your party and alliance: by name, or your current target when nil (`view.track.target` names it). This session only |
| `act.untrack(name)` | Stop tracking a player, by name. Their buff chips stay set for when they're tracked again |
| `act.profile(name)` | Load a profile: a `view.profiles.names[i]`, or nil for Default (the settings as they were before a profile was loaded). Loading one never changes `ui`, `japanese`, following, the focus or who healing skips |
| `act.save_profile(name, as_new)` | Save the settings as they are now under `name`. Without `as_new`, while another profile is loaded, that profile is renamed to `name` instead (as v2). A blank name, `'Default'`, or another profile's name saves nothing: only `as_new` replaces a profile. Changes after a load go to the settings, never the profile, until it's saved |
| `act.new_profile()` | Every setting back to its default (but those a profile never changes), on Default; profiles are kept |
| `act.delete_profile(name)` | Delete a profile; deleting the loaded one goes back to Default |
| `act.skip(name, skip)` | Skip a member (or tracked player) in healing (`skip` true), or take them back (false): a `view.heal.members[i].name`; nil toggles |
| `act.set(path, value)` | A setting by path, below |
| `act.watch(name, on)` | Show another session's SK Settings (a `party[i].session.name`), or stop: it then sends its view, which comes in `view.remote`. This session only; closed when that session goes |
| `act.remote(name)` | Another session's `act`, to change it from here: `run`, `section`, `row`, `pick`, `target`, `mod`, `hold`, `profile`, `save_profile`, `new_profile`, `delete_profile`, `track` (by name only), `untrack`, `skip` and `set`. `target`, `mod`, `hold` and `skip` need their state (`true` or `false`), never a toggle: the view you click is a moment old. `target`, `mod` and `hold` are refused there for a row that has no chips in that session (a buff or luopan row of its job). `set` takes only the paths in the table below but `'japanese'` and `'ui.*'` (the HUD is each session's own), a number held to its range. There's no `close`, `log`, `watch` or `remote`. Each call goes through the files the sessions share and is made there, through its own `act`, within a second or so (a quarter second while its SK Settings are open); its view in `view.remote` then shows it |

`act.set` paths:

| Path | Value |
|---|---|
| `'heal.danger'`, `'heal.critical'`, `'heal.focus_danger'`, `'heal.focus_critical'` | 1 to 99 |
| `'heal.focus'` | a name from `view.heal.focus_names`, or `''` |
| `'heal.cure_potency'`, `'heal.waltz_potency'` | 0 to 50 |
| `'heal.regen_potency'` | 0 to 30 |
| `'recover.mp'`, `'pet.heal'` | 1 to 99 |
| `'recover.tp'`, `'recover.min_tp'` | 0 to 3000 |
| `'follow.on'`, `'rest.on'`, `'heal.alliance'`, `'heal.reserve'`, `'buff.hold_aoe'`, `'buff.gather'` | bool |
| `'follow.target'` | a name from `view.follow.names`, or `''` |
| `'roll.first'`, `'roll.second'` | a name from `view.roll.choices`, or `''` |
| `'roll.risk'` | one of `view.roll.risks` |
| `'geo.distance'` | 3 to 30 |
| `'geo.linger'` | 1 to 20 |
| `'geo.entrust'` | a name from `view.geo.names`, or `''` |
| `'geo.entrust_spell'` | a name from `view.geo.indi`, or `''` |
| `'rune.idle_1'` to `'rune.idle_3'`, `'rune.vallation_1'`..., `'rune.valiance_1'`..., `'rune.pflug_1'`... | a name from `view.rune.runes`, or `''` |
| `'follow.distance'`, `'rest.distance'` | 1 to 15 |
| `'rest.delay'` | 1 to 20 |
| `'japanese'` | bool |
| `'ui.hp_width'`, `'ui.mp_width'` | 80 to 600 |
| `'ui.hp_height'` | 10 to 120 |
| `'ui.mp_height'` | 4 to 80 |
| `'ui.name_size'` | 8 to 64 |
| `'ui.text_size'` | 8 to 48 |
| `'ui.gap'` | 0 to 40 |
| `'ui.opacity'` | 0 to 100 |
| `'ui.locked'` | bool |
| `'ui.<name>'` | your UI's own: a string, number or bool |

Nothing is checked, so keep values in range. Settings are kept per job pair (one file for WHM/BLM, another for WHM/SCH), but for `ui`: every job pair shares it (its own file, `ui.lua`), so a UI's own `ui.<name>` is the same whatever you play.

### Saving

Sidekick saves after any `act` call that changes a setting, once no ImGui widget is held. Call `act.set` on every frame a slider moves; it is saved when the slider is let go.

## ImGui in Ashita

`local imgui = require('imgui')`. Ashita's binding differs from C++ ImGui in a few ways:

- **Widget values are one-element tables.** `local v = { view.japanese }` then `if imgui.Checkbox('Japanese', v) then act.set('japanese', v[1]) end`. The same for `SliderInt`, `InputText` and the rest.
- **`Text`, `TextColored` and `SetTooltip` take a printf format.** A `%` in what you show must be doubled: `imgui.Text((s:gsub('%%', '%%%%')))`. `why` texts and HP like `'62%'` need it.
- **Draw-list text is not a format.** `imgui.GetWindowDrawList():AddText(imgui.GetFont(), size, { x, y }, color, s)` draws `s` as is, at `size` pixels: don't double its `%`. Colours there are `imgui.GetColorU32({ r, g, b, a })`.
- **Labels are ids.** Two widgets with the same label in one window clash; add a unique suffix after `##` (`'On##heal'`), which isn't shown. Use `###` to keep the id when the label changes (`'Recent (3)###recent'`).
- **Close what you open.** `Begin` always needs `End`. `BeginTable`, `BeginCombo`, `BeginTabBar`, `BeginTabItem` and `BeginPopup*` need their `End*` only when they returned true. Every `Push*` needs its `Pop*`.
- **Constants** like `ImGuiWindowFlags_NoDecoration` are globals `require('imgui')` defines. When you use a new one, add it to `read_globals` in `.luacheckrc`: luacheck then accepts it, and the test below defines it.

## Test it

```
luajit tests/run.lua ui_window
```

With `ui/custom.lua` present, this also draws it through a fake ImGui, running and stopped, and fails on a Lua error or an ImGui scope left open. The fake answers `false` to calls it has no handler for; if your UI needs a number back (a width, say), add a handler in `tests/ui_window_test.lua`. In the game, `/addon reload sidekick3` picks up each change.

## Example

A compact window: Start/Stop, the status line, everyone's HP, and the behavior switches.

```lua
local imgui = require('imgui')

local ui = {}

-- Ashita's Text takes a printf format: double any '%'.
local function text(s) imgui.Text((tostring(s):gsub('%%', '%%%%'))) end

local function draw(view, act)
    local s = view.status
    if imgui.Button(s.running and 'Stop##mini' or 'Start##mini') then act.run(not s.running) end
    imgui.SameLine()
    text(s.text)
    for _, p in ipairs(view.party) do
        text(('%-3s %-14s %3d%%'):format(p.tag, p.name, p.hpp))
    end
    for _, sec in ipairs(view.sections) do
        if sec.on ~= nil then
            local v = { sec.on }
            if imgui.Checkbox(sec.title .. '##mini_' .. sec.id, v) then act.section(sec.id, v[1]) end
        end
    end
end

function ui.render(view, act)
    local open = { true }
    local ok, err = true, nil
    if imgui.Begin('Sidekick3 mini', open, ImGuiWindowFlags_AlwaysAutoResize) then
        ok, err = pcall(draw, view, act)  -- an error still reaches End below
    end
    imgui.End()
    if not open[1] then act.close() end
    if not ok then error(err, 0) end
end

return ui
```

## Asking an AI to write one

Give it this file and `ui/window.lua`, and say what you want: *"Using Sidekick3's ui/README.md, write ui/custom.lua: a narrow window with the party's HP bars, a Start/Stop button and a checkbox per buff row."* Then run the test above and `/addon reload sidekick3`.
