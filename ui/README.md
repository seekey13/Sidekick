# Your own Sidekick3 UI

Sidekick3's UI is one replaceable Lua file. Sidekick does all the deciding and acting; a UI only **shows** a table of data (`view`) and **changes** things through a table of functions (`act`). Anything that keeps to that contract can replace the standard UI: a compact HP list, a bar of on/off switches, one big window instead of two.

[window.lua](window.lua) is the standard UI and the reference: a heads-up display of the party's HP and MP (the **Sidekick3** window), whose cog opens **SK Settings**, every setting under collapsing headers. It uses nearly every field and every action below.

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
| `rest` | table | `{ on, delay, distance }`: rest after `delay` seconds with nothing to do; stand when the follow target is further than `distance` yalms |
| `track` | table | `{ target }`: your current target's name when it's a player you could track (not in your party or alliance, not tracked yet), else nil |
| `japanese` | bool | Spell, ability and item names are sent in Japanese |
| `log` | bool | Each action sent is printed to chat |
| `ui` | table | The UI's settings, shared by every job pair: `open` (bool), and any `ui.<name>` your UI saved. The standard HUD's, which yours may ignore: `hp_width`, `mp_width` (80 to 600), `hp_height` (10 to 120), `mp_height` (4 to 80), `name_size` (8 to 64), `text_size` (8 to 48), `gap` (0 to 40), all in pixels; `opacity` (0 to 100, the panel's %); `locked` (bool, it can't be dragged) |
| `sections` | list | Every setting, by section, below |

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
| `job` | string or nil | A tracked player's jobs once a `/check` has answered: `'WHM 75 / BLM 37'`; nil for everyone else |
| `alive` | bool | |
| `away` | bool | In another zone (its HP and MP are stale), or for a tracked player, out of range (its HP as last seen) |
| `tracked` | bool | You track this player: every `'tracked'` line, and a member who joined your party or alliance while tracked (they are tracked again when they leave) |
| `hpp`, `mpp` | number | HP and MP, 0 to 100 |
| `hp` | string | `'ok'`, `'low'` (under the danger line) or `'critical'` (under the critical line); the focus member's own lines for them |
| `uses_mp` | bool | It has MP: yours when your max MP is over 0; another member's once it has been seen with MP on its current jobs. Never a tracked player's: their MP can't be read (`mpp` is 0) |
| `mp` | string | `'low'` when it uses MP and is under the Recover MP line (`view.recover.mp`), else `'ok'` |
| `dist` | string | `''` for you, `'away'`, or like `'12.3y'` |
| `buffs` | string | Its statuses, the first 6 by name and `'+N'` for the rest |
| `buffs_all` | string | Every status, one per line (for a tooltip) |

### `view.heal`

`danger`, `critical`, `focus_danger`, `focus_critical` (HP %, 1 to 99); `focus` (a member's name, `''` for none); `alliance` (bool: the alliance's other parties are healed too; the focus member always is); `cure_potency`, `waltz_potency` (+% from gear, 0 to 50); `regen_potency` (+HP per Regen tick from gear, 0 to 30); `focus_names` (the members that can be the focus, you excluded, the alliance's and tracked players included); `members` (`{ name, healed, wrap }` for each member and tracked player, you excluded, and the alliance's while `alliance` is on; `healed` false when skipped; `wrap` true on the first of each of the alliance's parties, where the standard window starts a line).

### `view.sections[i]`

In this order. A section with rows is left out when your job has none for it (Pet shows only for a pet job), and Wake sleepers only shows when one of your heals wakes (a cure or waltz; not a pet's).

| `id` | `title` | `header` | Its settings |
|---|---|---|---|
| `'follow'` | Follow | Follow | `view.follow` |
| `'heal'` | Healing | Heal | `view.heal`, rows |
| `'revive'` | Revive | Heal | rows |
| `'wake'` | Wake sleepers | Remove | its switch only |
| `'remove'` | Debuff removal | Remove | rows: spells and abilities, then items |
| `'buff'` | Buffs | Buff | rows |
| `'pet'` | Pet | Pet | `view.pet_heal`, rows |
| `'recover'` | Recovery | Recover | `view.recover`, rows |
| `'rest'` | Resting | Recover | `view.rest` |
| `'track'` | Tracked players | Tracked | `view.track`, and the `party` and `alliance` lines with `tracked` |
| `'ui'` | UI / Log | UI / Log | `view.ui`, `view.log`, `view.recent`, `view.japanese` |

| Field | Type | What it is |
|---|---|---|
| `id`, `title`, `header` | string | As above. `header` is the collapsing header SK Settings puts it under, headers in the order their first section comes |
| `on` | bool or nil | The section's switch (`act.section`); every section has one but `track` and `ui` |
| `rows` | list or nil | One per spell family, pick-one group or item, below; nil for the sections without rows |
| `has_choices`, `has_targets` | bool or nil | Some row in the section has `choices` / `targets` (to lay out columns) |

### `view.sections[i].rows[j]`

| Field | Type | What it is |
|---|---|---|
| `key` | string | The row's id for `act`: a family (`'Cure'`, `'Haste'`), a pick-one group (`'barelement'`, `'minuet'`) or an item (`'Echo Drops'`) |
| `label` | string | `'Cure'`, `'Valor Minuet (+ATK)'`, `'Sword Madrigal / Blade Madrigal'` |
| `on` | bool | Rows start on, except buffs, sending the pet in (Assault, Fight, Deploy) and items |
| `ready` | bool | It could go right now |
| `avail` | string | `'ready'`, or why not: `'recast 12s'`, `'MP'`, `'TP'`, `'silenced'`, `'combat only'`, `'idle only'`, `'no ammo'`, `'pet too far'`, `'none left'`, `'pick one'`, `'not available'`... |
| `action` | string or nil | When ready, the spell, ability or item it would use, as the client names it: `'Cure V'` |
| `count` | number or nil | Item rows (`'Echo Drops'`, `'Remedy'`...): how many you carry |
| `choices` | list or nil | Buff rows with tiers or a pick-one group: `{ label, name }`. A tiered row's first choice is `'Auto (best)'` with `name` nil |
| `pick` | string or nil | The chosen `name`; nil is Auto |
| `choice` | string or nil | The label to show for the current pick: `'Auto (best)'`, `'Pick one'`, `'Protect II'`, `'Protect V (not available)'` |
| `targets` | list or nil | Buff rows that can go on others: 6 chips `{ slot, label, present, name, on, wrap }`, `slot` 0 (you, `'ME'`) to 5 (`'P5'`). `present` is false for an empty party slot (`name` is then nil). When the row's spells can go outside the party (Protect, Haste; not Regen), a chip follows for each tracked player, `'T1'` on, its `slot` their name; then 6 for each of the alliance's other parties that is there or has a chip on, `'B0'` to `'B5'` (`slot` 6 to 11) and `'C0'` to `'C5'` (12 to 17). `wrap` is true on `'B0'` and `'C0'`: the standard window starts a new line there |

## `act`

| Function | What it does |
|---|---|
| `act.run(on)` | Automation on or off. This session only: it is always off after a load |
| `act.log(on)` | Print each action sent to chat, or not. This session only |
| `act.close()` | Hide the UI (remembered); `/sk3` shows it again |
| `act.section(id, on)` | A section's switch: `'follow'`, `'heal'`, `'revive'`, `'wake'`, `'remove'`, `'buff'`, `'pet'`, `'recover'` or `'rest'` |
| `act.row(key, on)` | A row on or off |
| `act.pick(key, name)` | A row's choice: a `choices[i].name`, or nil for Auto |
| `act.target(key, slot)` | Turn a target chip on or off: its `slot`, 0 to 17 or a tracked player's name |
| `act.track(name)` | Track a player outside your party and alliance: by name, or your current target when nil (`view.track.target` names it). This session only |
| `act.untrack(name)` | Stop tracking a player, by name. Their buff chips stay set for when they're tracked again |
| `act.skip(name)` | Skip a member (or tracked player) in healing, or take them back: a `view.heal.members[i].name` |
| `act.set(path, value)` | A setting by path, below |

`act.set` paths:

| Path | Value |
|---|---|
| `'heal.danger'`, `'heal.critical'`, `'heal.focus_danger'`, `'heal.focus_critical'` | 1 to 99 |
| `'heal.focus'` | a name from `view.heal.focus_names`, or `''` |
| `'heal.cure_potency'`, `'heal.waltz_potency'` | 0 to 50 |
| `'heal.regen_potency'` | 0 to 30 |
| `'recover.mp'`, `'pet.heal'` | 1 to 99 |
| `'recover.tp'`, `'recover.min_tp'` | 0 to 3000 |
| `'follow.on'`, `'rest.on'`, `'heal.alliance'` | bool |
| `'follow.target'` | a name from `view.follow.names`, or `''` |
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
