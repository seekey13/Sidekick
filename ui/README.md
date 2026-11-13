# Your own Sidekick UI

Sidekick's UI is a theme: one Lua file in `ui/`, any of which can draw it ([Themes](#themes)). Sidekick does all the deciding and acting; a UI only **shows** a table of data (`view`) and **changes** things through a table of functions (`act`). Anything that keeps to that contract can replace the standard UI: a compact HP list, a bar of on/off switches, one big window instead of two.

[window.lua](window.lua) is the standard UI and the reference: a heads-up display of the party's HP, MP and TP, your pet's under yours and another session's under its card (the **Sidekick** window), whose cog on your own card opens **Sidekick Settings** (as `/sk` does), a page per group of settings listed down its left, and, with `ui.widget` on, **SK Widget**, one row: each character (yours, then each other Sidekick session's) in a pill, green running, blue held (asleep, mounted, zoning...) and red stopped, with its name, its run button and its cog, `ui.widget_size` pixels high; right-click a name to load one of its profiles. While your target is a player you could track (`view.track.target`), the HUD points an **Add Tracked** pill at your card, ahead of the action labels there, and the widget ends its row with one; a click anywhere on either tracks them (`act.track`). It uses nearly every field and every action below. Its look is [kit.lua](kit.lua)'s, after VanaCore's own `/vana` window ([docs/vana-ui-style.md](../docs/vana-ui-style.md)): a palette, and switches, sliders, drop-downs, chips and buttons drawn on ImGui's draw lists over invisible buttons. A custom UI can `require('ui.kit')` for the same look; each control takes its value and returns the new one and whether it changed, and `kit.frame(scale, view.japanese)` must run once a frame before any of them (on a Japanese client it draws in Meiryo, which has the kana and kanji Segoe UI lacks; on Ashita 4.16, in the Japanese font Ashita's boot config adds, as [the README](../README.md) says). `kit.list_rows` (8; `kit.rows(view.ui.list_rows)` takes the user's Drop-down rows) is the most choices a `kit.dropdown`'s list shows before it scrolls (`kit.list_size(px, min_w, max_w)` before a `kit.popup` of your own caps it the same), and `kit.selectable` in its body opens the list scrolled to the ticked choice. `kit.tooltips()` after them draws the frame's tooltip: only the last `kit.tooltip` asked for shows, as with `SetTooltip` (without it, the next `kit.frame` draws it, a frame late).

## Themes

A UI file is a **theme**. Standard is `ui/window.lua`; every other `.lua` file in `ui/` is a theme too, but for Sidekick's own `kit.lua` and `model.lua`. Sidekick comes with one, **Classic** (`ui/classic.lua`): Sidekick 2.9.1's windows, drawn from this version's view.

Sidekick Settings' **UI / Log** page lists them under **Theme**, Standard first, then each by its name; a click on one draws Sidekick with it at once. `/sk theme` lists them in chat, and `/sk theme <name>` (a theme's name, or its file's: `/sk theme Classic`, `/sk theme classic`, `/sk theme standard`) picks one. A theme can offer the pick too, from `view.themes` and `act.theme`: Classic's is the **Theme** drop-down on its Party State (`/sk hud`).

The theme picked is the PC's: every character on it draws with it, kept in `config/addons/sidekick/theme.txt`. Every other Sidekick session running on the PC switches to it within a second. With none picked yet, Sidekick draws with `ui/custom.lua` when there is one (the one file it took before themes), else Standard.

## Install

1. Write a `.lua` file in `ui/`, any name but Sidekick's own (`kit.lua`, `model.lua`, `window.lua`, `classic.lua`): copy `ui/window.lua` to start from the standard window, or start from the [example](#example). Give it a `name` (below).
2. Open Sidekick Settings (`/sk`): a file added since Sidekick loaded is found then, and listed under UI / Log's Theme. Click it there, or `/sk theme <its name>`.
3. To go back, pick Standard: under Theme, or `/sk theme standard`.

Every theme in `ui/` is loaded as Sidekick loads, and one added later the next time Sidekick Settings open or `/sk theme` lists them. An edit to one already loaded waits for `/addon reload sidekick`. If one fails to load (a syntax error, say), the lists say so and why, and it can't be picked; one picked that fails, at a load, is said in chat and Standard drawn instead. If a theme raises an error while drawing, Sidekick closes every window of it and prints the error; `/sk hud`, `/sk` or `/sk alt` opens it again, and `/sk theme standard` goes back to Standard. Git ignores every `.lua` in `ui/` but Sidekick's own, so updating Sidekick leaves yours alone (it does replace `ui/classic.lua`: to change it, copy it to a file of your own and give the copy a `name` of its own).

### Upgrading from 3.0.0

In 3.0.0, `/sk` showed or hid the whole UI. From 3.0.1, `/sk` shows Sidekick Settings, `/sk hud` the HUD and `/sk alt` other sessions' Sidekick Settings, each apart from the others, and `render` is called while any one of them is up. A UI written for 3.0.0 draws nothing for `/sk`, so the first `/sk` after a load says so in chat while `ui/custom.lua` (where such a UI was kept) is drawing. To bring one up to date:

- Draw the HUD only while `view.ui.open`, and Sidekick Settings while `view.ui.settings` rather than a flag of its own: a cog calls `act.settings(not view.ui.settings)`, the window's close button `act.settings(false)`.
- Leave Sidekick Settings up when the HUD closes (`act.close()` no longer closes them).
- Draw `view.remote`'s windows whatever `view.ui.open` and `view.ui.widget` say: `/sk alt` shows them alone.
- A UI with a single window shows it for `view.ui.open or view.ui.settings`, and its close button calls both `act.close()` and `act.settings(false)`, as the [example](#example) does.

## The contract

A UI file returns a table with one function (and, optionally, `name` and `load`: below):

```lua
local ui = {}
ui.name = 'My theme'  -- as the theme lists show it; without one, the file's name (my_theme for ui/my_theme.lua)

-- Called every frame while the HUD, Sidekick Settings (yours or another session's) or the widget is up, from
-- Ashita's d3d_present.
function ui.render(view, act)
end

return ui
```

- **It draws everything itself**, its window or windows included (`imgui.Begin` / `imgui.End`).
- **`view` is rebuilt every frame** and is a copy: changing it changes nothing.
- **`act` is the only way to change anything.** Sidekick saves settings for you (see [Saving](#saving)).
- **Every ImGui scope it opens must be closed, even when it errors.** ImGui crashes the game on a `Begin` with no `End`. Guard the inside of the window with `pcall`, end the window, then raise the error, as the example and `window.lua` do.
- **State of its own** (which page is showing, a collapsed panel) lives in locals in the file and lasts until the addon reloads. To keep a preference across reloads, save it under `ui.` with `act.set('ui.<name>', value)` and read it back from `view.ui.<name>`.
- **Each window shows apart from the others.** Draw the HUD only while `view.ui.open`, Sidekick Settings only while `view.ui.settings`, another session's only while it's in `view.remote`, and a widget only while `view.ui.widget`: Sidekick calls `render` while any one of them is up, so each can be shown alone (the standard UI's are). A UI with a single window may show it for `view.ui.open` or `view.ui.settings`, as the example does.
- `/sk`, `/sk hud` and `/sk alt` opening and closing the windows, the commands, and automation itself don't depend on the UI. A UI with no Start button still runs with `/sk start`.
- **`ui.load()`, if the UI has one, is called once from Ashita's `load` event**, before the first frame, for every theme in `ui/` whether it's the one drawing or not: a switch to it then needs no reload. That is where to add fonts: Ashita 4.16's ImGui (1.81) takes none mid-frame. The standard UI's adds Segoe UI there (`kit.bake`). A theme added after Sidekick loaded has its `load` run at the next `/addon reload sidekick`; picked before then, it draws, and chat says so in each session that draws it.
- **Its file is run when Sidekick finds it**, and its table is kept: anything at the top of the file runs then, whether or not the theme is ever drawn. One that failed to load is run again each time Sidekick looks in `ui/`, till it loads. Like a module from `require`, it gets its name as `...` (`'ui.mine'` for `ui/mine.lua`). Only the files in `ui/` itself are themes: one in a folder under it is not, so a theme's own files can go in a folder of its own and be required from it.

## `view`

Text that may contain `%` (names, `why` text) must be escaped before it's drawn: see [ImGui in Ashita](#imgui-in-ashita).

**Language.** On a Japanese client (`view.japanese`) the text Sidekick writes for you to show is Japanese, UTF-8 as ImGui takes it: every `label`, `choice`, `avail`, `action`, `note` and `text`, `status.text` and `status.dim`, `recent`, `pointer.text` and `others[i].text`, `job` (`'白75/黒37'`), a party line's `buffs`, the rune sets' `label` and a rune's `label`, `element`, `resist` and `ailments`. Spells, abilities, items and statuses go by the client's own Japanese names. What you pass back to `act` or compare stays English: `key`, `name`, `slot`, a section's `id`, `title` and `header`, `status.state`, `status.halted` and `flags`; the standard window translates the fixed words among them itself. It stays English while no Japanese font can draw it (core/lang.lua's `lang.drawable`, which `kit.frame` sets). A Japanese client gives a trust's, your pet's or a mob's name in Japanese, Shift-JIS: a `name` field holds it as the game does, for `act`; draw it through `lang.text(name)`. For your UI's own words, `require('core.lang')`: `lang.t(s)` and `lang.f(fmt, ...)` give core/ja.lua's Japanese for an English string while the UI is in Japanese (add yours there), `lang.name(english)` a spell's or ability's Japanese name.

| Field | Type | What it is |
|---|---|---|
| `job` | string | `'WHM 75 / BLM 37'`, or `'WAR 75'` with no subjob |
| `status` | table | The status line, below |
| `party` | list | You, then your party and trusts, then the players you track, below |
| `alliance` | list | The alliance's other two parties, as `party` lines (kind `'alliance'`, tags `'B0'` to `'B5'` and `'C0'` to `'C5'`); empty outside an alliance. The standard HUD draws them as thin HP rows under the cards |
| `bt` | table or nil | Your battle target: `{ name, hpp, dist }`, `dist` like `'4.3y'`. With no `<bt>` of your party's, the nearest mob another party of the alliance claimed |
| `pet` | table or nil | Your pet: `{ name, hpp, mpp, tp, dist, pools, uses_mp }`, as `bt` plus its MP % and its TP (0 to 3000); `pools` is true (its MP and TP are known: another session's pet, `party[i].pet`, has it false until that session's file names it); `uses_mp`: it has MP, once seen with some (a wyvern or a jug pet never is). The standard HUD gives it a card under yours, tagged `PET`: its HP, MP and TP bars each an alliance row's size, its name pale cyan (`#C2FFFF`) while a member's would be white, its tag on the TP bar; no MP bar while `ui.hide_mp` is on and it has no MP |
| `flags` | list of strings | What may be holding automation up, in this order: `'casting'`, `'moving'`, `'combat'`, `'safe zone'`, `'AFK asleep'`, `'mounted'`, `'dead'`, `'resting'`, `'incapacitated'`, `'silenced'`, `'amnesia'` |
| `recent` | list | The last 10 actions sent, newest first: `{ age, text, why }`, e.g. `{ 12, 'Cure IV -> Kupipi', 'heal: Kupipi at 62%' }`; `age` in whole seconds |
| `pointer` | table or nil | What automation is about to do, or would do, for the standard HUD's arrow: `{ text, member, ally, live, pet }`. `text` is the behavior then the action, `'Heal:Cure IV'`; a target with no line of its own is added by name (`'Heal:Cure IV -> Name'`). `member` is the index in `party` it is for: the target's, else yours (an action on you, your pet or the enemy, as pet care's `'Pet:Healing Ruby'`). For an alliance member, `ally` is their index in `alliance` and `member` is nil. `pet` is true when it is your pet's own, pet care or sending it in (`'Pet:Healing Ruby'`, `'Pet:Deploy'`), while `view.pet` is there: the standard HUD points at the pet's card then; `member` is still yours, for a UI with no pet card. `live`: running, it is the decision about to go or, for a moment after (longer while it is being cast), what was just sent; stopped (false), what it would do. nil when there is nothing |
| `others` | list | What the other Sidekick sessions on this PC are doing as it goes, for the standard HUD's blue labels: `{ session, text, member, ally, pet }` each, by `session` (its character's name). `text`, `member` and `ally` as `pointer`'s, but an action on no one (on that session's player, its pet or the enemy) is at that session's own line, never yours. `pet` is true for its pet's own (care, sending it in) while that line has a `pet`: the standard HUD points at that pet's card then. One shows while that session's own `pointer` would show what it just sent: a moment after it goes, longer while it's being cast. Empty when none is acting, or none is on a line here |
| `heal` | table | Healing's settings, below |
| `recover` | table | `{ mp, tp, min_tp, spends_tp, target, names, devotion }`: recover MP under `mp` % (yours; a member's for Devotion), TP under `tp` (0 to 3000) in combat; Chivalry only from `min_tp` TP. `spends_tp`: a row spends TP (Chivalry), so `min_tp` is worth showing. Devotion goes only on `target` (a name from `names`: your party but you, those whose job has MP), or with `''` on the member lowest on MP. A target in your party but away (another zone, dead, out of range) gets none and no one else does; while the target isn't in your party, the member lowest on MP gets it. `devotion`: a row gives a member MP (Devotion), so `target` is worth showing |
| `pet_heal` | number | Heal your pet under this HP % |
| `follow` | table | `{ on, target, distance, names }`: follow `target` (a name, `''` for none) once further than `distance` yalms, mounted, in a safe zone and with automation stopped too; `names` are the members (the alliance's and tracked players too) that can be followed |
| `buff` | table | `{ hold_aoe, gather, one_shadow, shadows }`: `hold_aoe` holds an area buff spell (Protectra, songs) while a player in your party who lacks it is out of its reach; `gather` then asks them to gather in party chat, at most every 5 seconds, when someone near you lacks it too; `one_shadow` recasts Utsusemi while its last shadow is up (for Ichi, cancelling that shadow a second into the cast), and `shadows` says your job has Utsusemi, so it's worth showing |
| `roll` | table | Corsair's rolls: `{ first, second, risk, risks, two, choices, last }`. `first` and `second` are the rolls kept up, by name (`''` for none); `two` is true on a Corsair main job, the only one that keeps a second. `risk` is how far Double-Up chases a total, one of `risks`: `'lowest'`, `'medium'`, `'highest'`. `choices` lists every roll you have, by name: `{ name, label, lucky, unlucky }`, as `{ name = 'Corsair\'s Roll', label = 'Corsair\'s Roll (EXP+)', lucky = 5, unlucky = 9 }`. `last` is the last roll's total while it's on you (or it just busted), when it's one of them: `{ name, total, lucky, unlucky, bust }`, else nil. A `second` equal to `first` keeps one roll |
| `song` | table | Bard's songs: `{ slots, choices, sets, pianissimo, ready, avail }`. `slots` is how many songs stand on each target, 2 on a Bard main job, 1 on a subjob. `choices` lists every song you have, in id order (each kind's tiers together), `{ name, label }`, as `{ name = 'Valor Minuet IV', label = 'Valor Minuet IV (+ATK)' }`. `sets` are Area, then each party slot: `{ key, label, picks, name, present, immune }`; `key` is `'area'`, `'me'` or `'p1'` to `'p5'`, `label` `'Area'`, `'ME'`, `'P1'`...; `picks` holds a song name (or `''`) for each of the 2 slots, though only the first `slots` count; set slot `i` with `act.set('song.<key>_<i>', name)`. Area songs are sung as they are, on everyone near you; a party slot's on whoever is in it (`name`, `present`; nil and false for an empty slot) through Pianissimo, never on a trust that can't be hurt (`immune`). `pianissimo` is false when you have none (under Bard 20), so a party slot's songs can't go; otherwise `ready` and `avail` are Pianissimo's, as a row's. `timed` is true on a Bard main job from 75, where `duration` (Song Duration, seconds, 0 off) is set with `act.set('song.duration', n)`: each song is then sung again that long after it landed. `fast` (Pianissimo fast casting, set with `act.set('song.fast', on)`) fires Pianissimo before an area song too and cancels it a second into the cast; only worth showing while `pianissimo` is true. Off BRD, `choices` and `sets` are empty and `slots` 0 |
| `geo` | table | Geomancer's luopan: `{ distance, linger, entrust, entrust_spell, indi, names }`. Full Circle recalls the luopan once who it went on is further than `distance` yalms from it (3 to 30), and a debuff's `linger` seconds after combat (1 to 20). Entrust puts the Indi- spell `entrust_spell` (a name from `indi`, every Indi- you have, or `''`) on the member `entrust` (a name from `names`, your party but you, or `''`) |
| `rune` | table | Rune Fencer's runes: `{ slots, runes, sets }`. `slots` is how many runes stand at once at your RUN level, main or sub (1 to 3). `runes` lists every rune you have, `{ name, label, element, resist, ailments }`, as `{ name = 'Ignis', label = 'Ignis', element = 'Fire', resist = 'Ice', ailments = 'Paralyze / Bind' }` (`label` the name as shown, `イグニス` in Japanese): what it adds to your attacks, the element it resists, the ailments it defends against. `sets` are Idle, then each ward you have (Vallation, Valiance, Pflug): `{ key, label, shows, ward, on, ready, avail, picks }`. `picks` holds a rune name (or `''`) for each of the 3 slots, though only the first `slots` count; set slot `i` with `act.set('rune.<key>_<i>', name)`. `shows` is the field of `runes` the set's picks are best named by (`'element'` for Idle, `'resist'` for Vallation and Valiance, `'ailments'` for Pflug). A ward's set also has `ward` (its name, the row key for `act.row`), `on` (its row), `ready` and `avail` as a row's. Off RUN, `slots` is 0 and `runes` and `sets` are empty |
| `maneuver` | table | Puppetmaster's maneuvers: `{ choices, picks, ready, avail }`. `choices` lists every maneuver you have, in element order, `{ name, label }`, as `{ name = 'Fire Maneuver', label = 'Fire' }`. `picks` holds a maneuver name (or `''`) for each of the 3 slots; the same one twice keeps two up. Set slot `i` with `act.set('maneuver.slot_<i>', name)`. `ready` and `avail` as a row's, for them all (they share one recast and gate: `'no pet'` without an automaton out, `'blocked by a status'` under Overload). Off PUP, `choices` is empty and `ready` and `avail` nil |
| `rest` | table | `{ on, mp, distance }`: rest as soon as your MP falls under `mp` %, until it's full; stand when the follow target (`follow.target`, shown in Resting too) is further than `distance` yalms |
| `afk` | table | `{ minutes, asleep, left }`: AFK sleep pauses automation once no one in your party has moved and there has been no combat for `minutes` (1 to 60), and your own movement wakes it; its switch is the `'afk'` section's. `asleep` is true while it sleeps; `left` is the seconds until it would, nil while it's off, asleep or automation is stopped (it counts only while running) |
| `track` | table | `{ target }`: your current target's name when it's a player you could track (not in your party or alliance, not tracked yet), else nil. The standard HUD and widget offer it as an Add Tracked pill, for `act.track(target)` |
| `japanese` | bool | A Japanese client: spell, ability and item names are sent in Japanese, and the view's text is Japanese (see Language, above). Shared by every job pair: it's kept in `ui`'s file (`ui.japanese`) |
| `log` | bool | Each action sent is printed to chat (`/sk log`; off at load). The standard UI has no switch for it |
| `profiles` | table | `{ active, names }`: the profile loaded (nil for Default, the working copy) and every saved profile's name, in order, case aside. Each job pair has its own |
| `themes` | table | `{ current, list }`: the themes in `ui/` (Themes, above), the PC's, every character's. `list`: Standard first, then the rest by name, each `{ key, name, file, error, standard }`: `key` its file's name without `.lua` (`'classic'`; Standard's `'window'`), what `act.theme` takes; `name` as it gives it (`'Classic'`), else its `key`; `file` (`'ui/classic.lua'`); `error`, why it failed to load (it can't be picked), else nil; `standard`, true for Standard (shown as 標準 on a Japanese client). `current`: the `key` of the one drawing. The standard UI lists them on UI / Log; another session's view has none |
| `ui` | table | The UI's settings, shared by every job pair: `open` (bool, the HUD is shown now: false once `/sk hud`, `act.hud(false)`, `act.close()` or an error hid it), `settings` (bool, Sidekick Settings are shown now: `/sk` and `act.settings` switch them, apart from the HUD; this session only, closed at load and by an error), and any `ui.<name>` your UI saved. The standard HUD's, which yours may ignore: `hp_width`, `mp_width`, `tp_width` (80 to 600), `hp_height` (10 to 120), `mp_height`, `tp_height` (4 to 80), `name_size` (8 to 64), `text_size` (8 to 48), `gap` (0 to 40), all in pixels; `hide_mp` (bool, on by default: a card with no MP, a line or pet whose `uses_mp` is false, has no MP bar; a tracked player's, and another session's pet's while `pools` is false, stay: their MP is unknown, not none); `locked` (bool, it and the widget can't be dragged); `widget` (bool, the widget is shown, with the UI closed too: `/sk widget` switches it; a UI with no widget may ignore it); `widget_size` (10 to 48, the standard widget's text and icons' height in pixels); Sidekick Settings' `scale` (50 to 200, % of the size that suits the screen; nil for 100); `list_rows` (3 to 30, the most choices a standard drop-down's list, or the widget's profile menu, shows before it scrolls; nil for 8); `zone_stop` (bool, off by default: automation stops each time you zone, logging in and out too); `load_stopped` (bool, on by default: automation starts stopped at each load; off, it starts as it was left, kept in `running`, which Sidekick writes: not free for a UI's own use, nor the live state, which is `view.status.running`); `japanese` (bool, the client's language, as `view.japanese`: not free for a UI's own use) |
| `sections` | list | Every setting, by section, below |
| `remote` | list | The Sidekick Settings of other Sidekick sessions on this PC you have open (`act.watch`, or `/sk alt`), by name: `{ name, view, other }`. `view` is the view that session built and sent (nil until its first one comes, about a second): the same fields as yours but `pointer`, `others`, `ui`, `remote` and `sessions`, plus `session` (its name) and `version`. Draw it with `act.remote(name)` in place of `act`. `other` is true (and `view` nil) when that session runs another version of Sidekick, whose view this one can't draw |
| `sessions` | list | Every other Sidekick session on this PC, by name, from their session files (in your party or not; a zone, yours or theirs, leaves each as it was): `{ name, running, halted, open, profiles }`, as `party[i].session` |
| `session` | string or nil | Only on a view in `remote`: the session it came from. nil on yours |

### `view.status`

| Field | Type | What it is |
|---|---|---|
| `running` | bool | Automation is on |
| `state` | string | `'Running'` or `'Stopped'` |
| `text` | string | Running: the last action sent, or `'nothing sent yet'`. Stopped: what it would do now (`'would: Cure IV -> Kupipi (heal: Kupipi at 62%)'`), or why it wouldn't; with Follow on and a leader, `'following Kupipi; '` before it (Follow is sent while stopped), unless Follow is the would-do |
| `dim` | string or nil | Running and not acting: why (`'casting'`, `'safe zone'`, `'AFK asleep'`, `'nothing to do'`...) |
| `halted` | string or nil | Running, but held by what stops everything for longer than a moment (Follow alone goes on mounted and in a safe zone): `'zoning'`, `'dead'`, `'mounted'`, `'safe zone'`, `'AFK asleep'` or `'incapacitated'` (not casting or moving). The standard widget's pill turns blue |

### `view.party[i]`

| Field | Type | What it is |
|---|---|---|
| `tag` | string | `'ME'`, `'P1'` to `'P5'`; `'T1'`, `'T2'`... for the players you track; in `alliance`, `'B0'` to `'B5'` and `'C0'` to `'C5'` |
| `kind` | string | `'self'`, `'party'`, `'trust'` or `'tracked'` (a player outside your party and alliance you track: `/sk track`); `'alliance'` in `alliance` |
| `name` | string | |
| `job` | string or nil | A tracked player's jobs once a `/check` or another session's file has answered: `'WHM 75 / BLM 37'`; nil for everyone else |
| `alive` | bool | |
| `away` | bool | In another zone (its HP and MP are stale), or for a tracked player, out of range (its HP as last seen, or as another Sidekick session on this PC reads it) |
| `tracked` | bool | You track this player: every `'tracked'` line, and a member who joined your party or alliance while tracked (they are tracked again when they leave) |
| `shared` | string or nil | A tracked player another Sidekick session on this PC lists (its party): that session's character name. Tracked while it lists them; untracked by hand, they stay off until tracked again |
| `hpp`, `mpp` | number | HP and MP, 0 to 100 |
| `tp` | number | TP, 0 to 3000. Never a tracked player's: their TP can't be read (0). The standard HUD draws it as a bar of three parts, 1000 TP each, under the MP bar (under the HP bar when the MP bar is left out: `ui.hide_mp`), with `tag` on it |
| `hp` | string | `'ok'`, `'low'` (under the danger line) or `'critical'` (under the critical line); the focus member's own lines for them |
| `uses_mp` | bool | It has MP: yours when your max MP is over 0; another member's when its main job or its sub job (at a level over 0) has MP (WHM, BLM, RDM, PLD, DRK, SMN, BLU, SCH, GEO, RUN), at 0 MP too, or once it has been seen with MP on its current jobs; the alliance's once seen with MP. Never a tracked player's: their MP can't be read (`mpp` is 0) |
| `mp` | string | `'low'` when it uses MP and is under the Recover MP line (`view.recover.mp`), else `'ok'` |
| `dist` | string | `''` for you, `'away'`, or like `'12.3y'` |
| `buffs` | string | Its statuses, the first 6 by name and `'+N'` for the rest |
| `buffs_all` | string | Every status, one per line (for a tooltip) |
| `session` | table or nil | This player is another Sidekick session on this PC (a party member, a tracked player or one of the alliance; never you or a trust): `{ name, running, halted, open, profiles }`. `running`: its automation is on; `halted`: it's on but held, as `status.halted` (nil otherwise); `open`: its Sidekick Settings are shown here (`view.remote`); `profiles`: `{ active, names }` as `view.profiles`, that session's (`act.remote(name).profile` loads one there), or nil while unknown. The standard HUD puts a run icon and a cog on its card, as on yours |
| `pet` | table or nil | Only on a line with `session` (not of the alliance): its pet, while your client draws it, `{ name, hpp, mpp, tp, dist, pools, uses_mp }` as `view.pet`. `hpp` and `dist` are your client's; `mpp`, `tp` and `uses_mp` come from that session's file, with `pools` true, while the file names this pet (its id and name: a new pet may reuse the id); until then (just called, or swapped for another) they're 0 and false, and `pools` false. The client reads MP and TP for your own pet only. The standard HUD gives it a card under that session's, as yours |

### `view.heal`

`threshold`, `danger`, `critical`, `focus_threshold`, `focus_danger`, `focus_critical` (HP %, 1 to 99: efficient heals run from `danger` up to `threshold`); `focus` (a member's name, `''` for none); `cure_potency`, `waltz_potency` (+% from gear, 0 to 50); `regen_potency` (+HP per Regen tick from gear, 0 to 30); `reserve` (bool: buff rows leave the last stratagem charge for healing) and `stratagems` (bool: your job has stratagems, so `reserve` is worth showing); `no_efficient` (bool: your job has heals efficient healing could use, but every one's row is off or its tiers unticked, so `threshold` and `focus_threshold` can do nothing: the standard window and Classic grey their sliders and say why); `focus_names` (the members that can be the focus, you excluded, the alliance's and tracked players included); `targets`, the slot chips healing runs on (the same shape as a buff row's `targets`, below: you included, both alliance parties always, empty slots included, tracked players last). A chip is `on` while that person is present and not skipped by name (`act.skip`); the standard window draws no chip for an empty slot. The alliance's other parties are always healed when a heal reaches them. Each heal's tiers are on its row, as `tiers` (below).

### `view.sections[i]`

In this order. A section with rows is left out when your job has none for it (Pet shows only for a pet job), Wake sleepers only shows when one of your heals wakes (a cure or waltz; not a pet's), Rolls only when you have a roll (Corsair), Songs only when you have a song (Bard, main or sub), Geomancy only when you have a Geo- spell (a Geomancer main job), Runes only when you have a rune (Rune Fencer, main or sub), and Maneuvers for a Puppetmaster, main or sub, automaton out or not (none goes until one is). Rows for abilities the client lists only at times (pet commands, pacts and Ready moves with no pet out, stratagems outside their Arts) are there from the job's level, `ready` false with why (`no pet`, `needs Light Arts`, `not listed`).

| `id` | `title` | `header` | Its settings |
|---|---|---|---|
| `'profile'` | Profiles | Profiles | `view.profiles` |
| `'follow'` | Follow | Follow | `view.follow` |
| `'heal'` | Healing | Heal | `view.heal`, rows |
| `'revive'` | Revive | Heal | rows |
| `'wake'` | Wake sleepers | Remove | its switch only |
| `'remove'` | Debuff removal | Remove | `who` (the slot chips removal runs on), rows: its spells and abilities (`remover`), the debuffs they and its items clear (`debuff`), then the items |
| `'buff'` | Buffs | Buff | `view.buff`, rows |
| `'roll'` | Rolls | Buff | `view.roll` (a job with rolls only) |
| `'song'` | Songs | Buff | `view.song` (a job with songs only) |
| `'geo'` | Geomancy | Buff | `view.geo`, rows: the Geo row (its luopan's spell and targets), the Geo debuff row, Full Circle, Blaze of Glory, Entrust |
| `'rune'` | Runes | Buff | `view.rune` (a job with runes only) |
| `'pet'` | Pet | Pet | `view.pet_heal`, rows |
| `'maneuver'` | Maneuvers | Pet | `view.maneuver` (a job with maneuvers only) |
| `'recover'` | Recovery | Recover | `view.recover`, rows |
| `'rest'` | Resting | Recover | `view.rest` |
| `'track'` | Tracked players | Tracked | `view.track`, and the `party` and `alliance` lines with `tracked` |
| `'afk'` | AFK sleep | AFK | `view.afk` |
| `'ui'` | UI / Log | UI / Log | `view.ui`, `view.recent`, `view.japanese` |

| Field | Type | What it is |
|---|---|---|
| `id`, `title`, `header` | string | As above. `header` is the collapsing header Sidekick Settings puts it under, headers in the order their first section comes |
| `on` | bool or nil | The section's switch (`act.section`); every section has one but `profile`, `track` and `ui` |
| `rows` | list or nil | One per spell family, pick-one group or item, below; nil for the sections without rows. Roles in the section's order (Healing's heals, then its emergencies), each role's in the catalog's order (abilities, spells, then pet commands, by id; items last), but Buffs' in the order they're cast: by priority, highest first (a row with a pick, by its pick's), then by name in English, as `label` is on an English client |
| `has_choices`, `has_targets`, `has_mods` | bool or nil | Some row in the section has `choices` / `targets` / `mods` (to lay out columns) |
| `who` | list or nil | Debuff removal: the slot chips it runs on, the same shape as `targets` below. `on` is true for a player who is there and not switched off by name (`cfg.remove.off`); an empty slot, or a member with no name yet, can't be switched (the standard window draws no chip for an empty slot). `act.who(name, on)` sets it, so it follows them from slot to slot. Present players start on |

### `view.sections[i].rows[j]`

| Field | Type | What it is |
|---|---|---|
| `key` | string | The row's id for `act`: a family (`'Cure'`, `'Haste'`), a pick-one group (`'barelement'`, `'minuet'`), an item (`'Echo Drops'`) or, on a `debuff` row, the status's name as the client has it (`'paralysis'`, `'Dia'`) |
| `label` | string | `'Cure'`, `'Valor Minuet (+ATK)'`, `'Sword Madrigal / Blade Madrigal'` |
| `on` | bool | Rows start on, except buffs (and a Geomancer's Geo and Geo debuff rows), sending the pet in (Assault, Fight, Deploy) and items |
| `debuff` | bool or nil | Debuff removal's debuff rows, one per status your removers clear, in status id order (Poison, Paralysis, Blindness...): true. `on` is everyone's (removed, unless `cfg.remove.skip` names it). `own[name]` is that player's chip when they have their own set (`false` is stored: they leave it on); a player with no entry uses `on`. Doom is a row like any other. Switched with `act.debuff(key, on, name)`, not `act.row`. `ready` and `avail` are by the removers that are on that clear it; `action` names every spell, ability and item that clears it, on or not (`'Paralyna, Esuna, Remedy'`) |
| `usable` | bool or nil | `debuff` rows: false while no remover that is on clears it (`avail` `'nothing on removes it'`): the standard window draws its chip as an outline that can't be clicked |
| `remover` | bool or nil | Debuff removal's spell and ability rows (Paralyna, Erase, Healing Waltz...), switched with `act.row` as any row: true. The standard window draws them as checkboxes, above the debuffs, which it draws as chips |
| `shared` | bool or nil | `remover` rows whose family has another role too (Chakra heals): true. Its row is one, so unticking it here stops its healing too |
| `ready` | bool | It could go right now |
| `avail` | string | `'ready'` (or, for a pet care row or Sange whose ammo you hold but don't wear, `'equips <item>'`: it's equipped first, then the row goes), or why not: `'recast 12s'`, `'MP'`, `'TP'`, `'silenced'`, `'combat only'`, `'idle only'`, `'no ammo'`, `'no tools'`, `'pet too far'`, `'none left'`, `'pick one'`, `'not available'`, `'every tier unticked'` (a heal row whose every `tiers` entry is unticked)... |
| `tiers` | list or nil | Healing rows with more than one tier (Cure, Curaga, Regen, the waltzes, Drain, Healing Ruby), in the catalog's order: `{ name, label, on, wakes }`, one per name. `on` is false once unticked (`act.heal_spell`, stored in `heal.never`): healing never uses it, while the row's other tiers still go and waking still may, when `wakes` (true for a heal that wakes a sleeper: not a Regen, Drain or a pet's). A heal alone on its row, or a Ready move, is listed only once unticked, so it can be ticked again. The standard window draws them as checkboxes under the row's name |
| `action` | string or nil | When ready, the spell, ability or item it would use, as the client names it: `'Cure V'` (a `debuff` row: what clears it) |
| `count` | number or nil | Item rows (`'Echo Drops'`, `'Remedy'`...): how many you carry |
| `tools` | number or nil | Ninjutsu rows (Utsusemi, Tonko, Monomi): how many casts the tools in your inventory pay for (their own tool, and Shikanofuda on a NIN main job) |
| `choices` | list or nil | Buff rows (and the Geomancy section's) with tiers or a pick-one group: `{ label, name }`. A tiered row's first choice is `'Auto (best)'` with `name` nil. An enspell or storm row's first is its Auto, `{ label = 'Auto (weather/day)', match = true }` (`'Auto (weather)'` for storms), with no `name`: choosing it is `act.match(key, true)`, and it's the one ticked while `match` is on (no tier is then) |
| `pick` | string or nil | The chosen `name`; nil is Auto |
| `choice` | string or nil | The label to show for the current pick: `'Auto (best)'`, `'Pick one'`, `'Protect II'`, `'Protect V (not available)'`; with `match` on, `'Auto: Enfire II (weather)'` (below), `'Auto: Enblizzard'` (nothing matches: the pick goes) or the Auto choice's label (nothing picked either) |
| `targets` | list or nil | Buff rows that can go on others (and the Geo row: its luopan goes on the first of them who lacks it): chips `{ slot, label, group, present, name, on, wrap, immune }`. `immune` is true for a trust that can't be hurt (Moogle, Sakura, Kupofried...), which Sidekick never heals, buffs or cleanses: draw its chip greyed and take no click (never on the Geo row, whose luopan can stand on it). Your party is always there, `slot` 0 (you, `'ME'`) to 5 (`'P5'`), `group` `'party'`. `present` is false for an empty slot (`name` is then nil). When the row's spells can go outside the party (Protect, Haste; not Regen, which stops at the six party chips), both of the alliance's other parties are always listed, empty slots included: `'B0'` to `'B5'` (`slot` 6 to 11, `group` `'a'`) then `'C0'` to `'C5'` (12 to 17, `group` `'b'`). Then one chip per tracked player, `'T1'` on, `group` `'tracked'`, its `slot` their name. `wrap` is true on the first chip of `'a'`, `'b'` and `'tracked'`. The standard window draws one row per `group`, leaving out an empty slot (and a row with no one there) unless its chip is on, so it can be switched off |
| `mods` | list or nil | Buff rows a modifier fits (SCH's stratagems, RUN's Embolden): `{ name, label, note, on }`, as `{ 'Penury', 'Penury', 'half the MP', false }`: `label` is its full name, in Japanese the Japanese one. One that is on is fired just before the row's spell when its status isn't on you; Accession instead spreads the spell from you to the row's targets near you whenever one there lacks it. nil for other rows and jobs |
| `hold` | bool or nil | Rows with `mods`: the spell waits while one of the modifiers on for it can't go with it (on recast, fewer charges than stratagems to fire, the wrong Arts, Accession unable to spread it to someone it would reach, or short of MP for it), as v2's Hold for Stratagem; false, it goes without. A held row's `ready` is false and `avail` says what it waits for (`'waits for Embolden: recast 120.0s'`). nil for rows without `mods` |
| `match` | bool or nil | Enspell and storm rows: Auto, the first of `choices`, is chosen (Match): the tier matching the sky goes in place of `pick`, which is kept, the last one picked, for while nothing matches. nil for rows that can't match. Set with `act.match`; `act.pick` clears it. Both windows show it as that first choice of the pick's drop-down. On with nothing matching and nothing picked, `ready` is false and `avail` says `'no match'` |
| `match_rule` | string or nil | With `match`: what it reads. `'weather'` (storms) the zone's weather alone; `'element'` (enspells) the element your weather (a storm on you stacks with or replaces the zone's) and the day favor most, by LandSandBoat's enspell bonus (core/sky.lua) |
| `matched` | string or nil | With `match` on, the tier the sky picks now (`'Enfire II'`), else nil. `choice` then shows it and why: `'Auto: Enfire II (weather)'`, `'(storm)'` or `'(day)'`; `ready`, `avail` and `action` are its |
| `gate` | string or nil | When the row goes: `'combat'` only in combat (a battle target up, and for 5 seconds after it goes, as the `'combat'` flag), `'idle'` only out of it, nil any time (the default). Set with `act.gate`, one or the other; while it doesn't hold, `ready` is false and `avail` says `'combat only'` or `'idle only'`. It's healing's, not waking's: a heal gated either way still wakes a sleeper, as one healing never uses does. Every row of an action has it (not a `debuff` row). The standard window shows the one set as a pill after the row's name, on its line even when it has a pick: Combat in the palette's rose, Idle in its teal; with the pointer over the row, both, to click; the name leaves room for both either way, so the one set stays put, and while the pointer stays neither moves, a click aside (a second click where the first was clears it); they're dimmed while the row is off |
| `gate_fixed` | bool or nil | `gate` is built in and can't be set: true for a row whose every action has the same one of its own (Berserk and the sambas in combat, Raise, Sneak and Spectral Jig out of it) or is aimed at the enemy (Drain, Assault: in combat, since it needs a battle target). The standard window shows its pill always and alone, with no click |
| `also` | string or nil | The `title` of another section with a row of the same key (Sublimation: Buffs and Recovery; Chakra: Healing and Debuff removal). The two are one setting: their `on` and `gate` are the same, and setting either sets both. The standard window says so in the gate pills' tooltip |

## `act`

| Function | What it does |
|---|---|
| `act.run(on)` | Automation on or off. This session only: it is off after a load, unless `ui.load_stopped` is off (then as it was left) |
| `act.log(on)` | Print each action sent to chat, or not, as `/sk log`. This session only |
| `act.hud(on)` | Show the HUD (`on` true) or hide it, remembered, as `/sk hud` (the standard Sidekick Settings' Show the HUD switch) |
| `act.close()` | Hide the HUD, as `act.hud(false)`; `/sk hud` shows it again. Sidekick Settings stay as they are, and a widget while `ui.widget` is on |
| `act.settings(on)` | Show Sidekick Settings (`on` true) or hide them, as `/sk`. This session only |
| `act.theme(key)` | Draw with another theme, a `view.themes.list[i].key`, as `/sk theme`: at once, from this frame's end, and on every character on this PC (not a setting: nothing in the settings changes). One that failed to load isn't taken. Never another session's (`act.remote` has none) |
| `act.section(id, on)` | A section's switch: `'follow'`, `'heal'`, `'revive'`, `'wake'`, `'remove'`, `'buff'`, `'roll'`, `'song'`, `'geo'`, `'rune'`, `'pet'`, `'maneuver'`, `'recover'`, `'rest'` or `'afk'` |
| `act.row(key, on)` | A row on or off |
| `act.who(name, on)` | Removal runs on this player (`on` true) or leaves them alone, Doom too. `name` is a `who` chip's `name`. Nil toggles |
| `act.debuff(key, on, name)` | A debuff removed (`on` true) or left on: for everyone without a set of their own, or with `name`, for that player. A player's first change copies everyone's into their own set, and later changes stay there. Nil `on` toggles |
| `act.debuffs(names, on, name)` | Every status in `names` removed (`on` true) or left on (`on` false), for everyone or, with `name`, that player. Statuses not in `names` keep what they were |
| `act.pick(key, name)` | A row's choice: a `choices[i].name`, or nil for Auto (best). It turns a row's `match` off: a tier picked leaves Auto |
| `act.target(key, slot, on)` | Turn a target chip on or off: its `slot`, 0 to 17 or a tracked player's name; `on` true or false sets it, nil toggles it |
| `act.mod(key, name, on)` | Turn a modifier chip on or off: its `name` (`'Penury'`, `'Accession'`); `on` sets it, nil toggles it |
| `act.hold(key, on)` | A row's Hold: `true`, its spell waits while a modifier on for it can't go with it; `false` (the default), it goes without |
| `act.match(key, on)` | A row's Auto (Match; a row with `match` not nil): `true`, it follows the sky, its pick kept for when nothing matches; `false` (the default), its pick goes |
| `act.gate(key, gate)` | A row's gate: `'combat'` (it goes only in combat), `'idle'` (only out of it) or nil (any time). Setting one replaces the other. Saved apart from the row (`gates`, by row key), so it never makes a row nor changes its `on`. Has no effect on a row with `gate_fixed`: its own gate wins. A modifier chip (Penury, Accession on a buff row) never takes one |
| `act.track(name)` | Track a player outside your party and alliance: by name, or your current target when nil (`view.track.target` names it). This session only |
| `act.untrack(name)` | Stop tracking a player, by name. Their buff chips stay set for when they're tracked again |
| `act.profile(name)` | Load a profile: a `view.profiles.names[i]`, or nil for Default (the settings as they were before a profile was loaded). Loading one never changes `ui`, `japanese`, following, AFK sleep, the focus, who healing skips or who Devotion goes on |
| `act.save_profile(name, as_new)` | Save the settings as they are now under `name`. Without `as_new`, while another profile is loaded, that profile is renamed to `name` instead (as v2). A blank name, `'Default'`, or another profile's name saves nothing: only `as_new` replaces a profile. Changes after a load go to the settings, never the profile, until it's saved |
| `act.new_profile()` | Every setting back to its default (but those a profile never changes), on Default; profiles are kept |
| `act.delete_profile(name)` | Delete a profile; deleting the loaded one goes back to Default |
| `act.skip(name, skip)` | Skip a person in healing (`skip` true), or take them back (false): a `view.heal.targets` chip's `name`. Nil toggles. An empty slot has no name and cannot be skipped ahead of time |
| `act.heal_spell(name, on)` | Heal with one heal (`on` true) or never (false): a heal row's `tiers` `name`. Its row's other tiers go on as they were, and waking uses it either way. Nil toggles |
| `act.set(path, value)` | A setting by path, below |
| `act.watch(name, on)` | Show another session's Sidekick Settings (a `party[i].session.name`), or stop: it then sends its view, which comes in `view.remote`. `/sk alt` does the same. This session only; closed when that session goes |
| `act.remote(name)` | Another session's `act`, to change it from here: `run`, `section`, `row`, `who`, `debuff`, `debuffs`, `pick`, `target`, `mod`, `hold`, `match`, `gate`, `profile`, `save_profile`, `new_profile`, `delete_profile`, `track` (by name only), `untrack`, `skip`, `heal_spell` and `set`. `target`, `mod`, `hold`, `match`, `skip`, `heal_spell`, `who`, `debuff` and `debuffs` need their state (`true` or `false`), never a toggle: the view you click is a moment old; `gate` takes the gate to set, or nil for none. `who` takes the player's name first; `debuff` and `debuffs` take it last, or none for everyone's. `target`, `mod`, `hold` and `match` are refused there for a row that has no chips in that session (a buff or luopan row of its job), and `match` for one that can't follow the sky (not an enspell or storm row); `gate` for a row it doesn't have, or one whose gate is built in. `set` takes only the paths in the table below but `'japanese'` and `'ui.*'` (the HUD is each session's own), a number held to its range. There's no `close`, `log`, `watch` or `remote` (`/sk log` on that session turns its log on). Each call goes through the files the sessions share and is made there, through its own `act`, within a second or so (a quarter second while its Sidekick Settings are open); its view in `view.remote` then shows it |

`act.set` paths:

| Path | Value |
|---|---|
| `'heal.threshold'`, `'heal.danger'`, `'heal.critical'`, `'heal.focus_threshold'`, `'heal.focus_danger'`, `'heal.focus_critical'` | 1 to 99 |
| `'heal.focus'` | a name from `view.heal.focus_names`, or `''` |
| `'recover.target'` | a name from `view.recover.names`, or `''` (the member lowest on MP) |
| `'heal.cure_potency'`, `'heal.waltz_potency'` | 0 to 50 |
| `'heal.regen_potency'` | 0 to 30 |
| `'recover.mp'`, `'rest.mp'`, `'pet.heal'` | 1 to 99 |
| `'recover.tp'`, `'recover.min_tp'` | 0 to 3000 |
| `'follow.on'`, `'rest.on'`, `'afk.on'`, `'heal.reserve'`, `'buff.hold_aoe'`, `'buff.gather'`, `'song.fast'` | bool |
| `'follow.target'` | a name from `view.follow.names`, or `''` |
| `'roll.first'`, `'roll.second'` | a name from `view.roll.choices`, or `''` |
| `'roll.risk'` | one of `view.roll.risks` |
| `'geo.distance'` | 3 to 30 |
| `'geo.linger'` | 1 to 20 |
| `'geo.entrust'` | a name from `view.geo.names`, or `''` |
| `'geo.entrust_spell'` | a name from `view.geo.indi`, or `''` |
| `'rune.idle_1'` to `'rune.idle_3'`, `'rune.vallation_1'`..., `'rune.valiance_1'`..., `'rune.pflug_1'`... | a name from `view.rune.runes`, or `''` |
| `'maneuver.slot_1'` to `'maneuver.slot_3'` | a name from `view.maneuver.choices`, or `''` |
| `'song.area_1'`, `'song.area_2'`, `'song.me_1'`, `'song.me_2'`, `'song.p1_1'` to `'song.p5_2'` | a name from `view.song.choices`, or `''` |
| `'song.duration'` | 0 to 300 |
| `'follow.distance'`, `'rest.distance'` | 1 to 15 |
| `'afk.minutes'` | 1 to 60 |
| `'japanese'` | bool |
| `'ui.hp_width'`, `'ui.mp_width'`, `'ui.tp_width'` | 80 to 600 |
| `'ui.hp_height'` | 10 to 120 |
| `'ui.mp_height'`, `'ui.tp_height'` | 4 to 80 |
| `'ui.name_size'` | 8 to 64 |
| `'ui.text_size'` | 8 to 48 |
| `'ui.gap'` | 0 to 40 |
| `'ui.locked'`, `'ui.widget'`, `'ui.hide_mp'`, `'ui.zone_stop'`, `'ui.load_stopped'` | bool |
| `'ui.widget_size'` | 10 to 48 |
| `'ui.scale'` | 50 to 200 |
| `'ui.list_rows'` | 3 to 30 |
| `'ui.<name>'` | your UI's own: a string, number or bool (not `open` or `settings`: Sidekick sets `view.ui`'s from what's shown now) |

Nothing is checked, so keep values in range. Settings are kept per job pair (one file for WHM/BLM, another for WHM/SCH), but for `ui`: every job pair shares it (its own file, `ui.lua`), so a UI's own `ui.<name>` is the same whatever you play.

### Saving

Sidekick saves after any `act` call that changes a setting, once no ImGui widget is held. Call `act.set` on every frame a slider moves; it is saved when the slider is let go.

## ImGui in Ashita

`local imgui = require('imgui')`. Ashita's binding differs from C++ ImGui in a few ways:

- **Widget values are one-element tables.** `local v = { view.japanese }` then `if imgui.Checkbox('Japanese', v) then act.set('japanese', v[1]) end`. The same for `SliderInt`, `InputText` and the rest.
- **`Text`, `TextColored` and `SetTooltip` take a printf format.** A `%` in what you show must be doubled: `imgui.Text((s:gsub('%%', '%%%%')))`. `why` texts and HP like `'62%'` need it.
- **Draw-list text is not a format.** `imgui.GetWindowDrawList():AddText(imgui.GetFont(), size, { x, y }, color, s)` draws `s` as is, at `size` pixels: don't double its `%`. Colours there are `imgui.GetColorU32({ r, g, b, a })`.
- **Labels are ids.** Two widgets with the same label in one window clash; add a unique suffix after `##` (`'On##heal'`), which isn't shown. Use `###` to keep the id when the label changes (`'Recent (3)###recent'`).
- **Close what you open.** `Begin` and `BeginChild` always need `End` and `EndChild`. `BeginTable`, `BeginCombo`, `BeginTabBar`, `BeginTabItem` and `BeginPopup*` need their `End*` only when they returned true. Every `Push*` needs its `Pop*`.
- **Constants** like `ImGuiWindowFlags_NoDecoration` are globals `require('imgui')` defines. When you use a new one, add it to `read_globals` in `.luacheckrc`: luacheck then accepts it, and the test below defines it.
- **Two ImGui versions.** Ashita 4.30's libraries (VanaCore's default) are ImGui 1.92 (`IMGUI_VERSION_NUM` 19223), Ashita 4.16's are 1.81 (18000), and some calls differ between them: `BeginChild`'s third argument, the corner flags of `AddRectFilled`, `PushFont`'s size (1.81 takes the font alone: `kit.push_font` sizes it with `SetWindowFontScale`). `ui/kit.lua` handles them; use it, or check `IMGUI_VERSION_NUM` yourself.

## Test it

```
luajit tests/run.lua ui_window
```

This also loads every theme in `ui/` (Classic, and yours) and draws each through a fake ImGui, running and stopped with its HUD and Sidekick Settings each shown and hidden, and fails on a theme that won't load, a Lua error or an ImGui scope left open. The fake answers `false` to calls it has no handler for; if your UI needs a number back (a width, say), add a handler in `tests/ui_window_test.lua`. It reports every popup open, so a drop-down's list is drawn and its choices can be clicked; for `ui/kit.lua`'s controls it steps `kit.clock` a second a frame (every eased value lands at once) and drags a slider through `kit.dragged`. In the game, `/addon reload sidekick` picks up each change.

## Example

A compact window: Start/Stop, the status line, everyone's HP, and the behavior switches. Saved as `ui/mini.lua`, it's listed as Mini.

```lua
local imgui = require('imgui')

local ui = {}
ui.name = 'Mini'

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
    if not (view.ui.open or view.ui.settings) then return end  -- one window, for /sk hud and /sk alike; no widget
    local open = { true }
    local ok, err = true, nil
    if imgui.Begin('Sidekick mini', open, ImGuiWindowFlags_AlwaysAutoResize) then
        ok, err = pcall(draw, view, act)  -- an error still reaches End below
    end
    imgui.End()
    if not open[1] then  -- closed for both, until either opens it again
        act.close()
        act.settings(false)
    end
    if not ok then error(err, 0) end
end

return ui
```

## Asking an AI to write one

Give it this file and `ui/window.lua`, and say what you want: *"Using Sidekick's ui/README.md, write a theme, ui/narrow.lua: a narrow window with the party's HP bars, a Start/Stop button and a checkbox per buff row."* Then run the test above, open Sidekick Settings (`/sk`) and pick it under UI / Log's Theme, or `/sk theme narrow`.
