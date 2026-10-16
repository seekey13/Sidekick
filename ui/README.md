# Your own Sidekick3 UI

Sidekick3's window is one replaceable Lua file. Sidekick does all the deciding and acting; a UI only **shows** a table of data (`view`) and **changes** things through a table of functions (`act`). Anything that keeps to that contract can replace the standard window: a compact HP list, a bar of on/off switches, two small windows instead of one.

[window.lua](window.lua) is the standard window and the reference: it uses every field and every action below.

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
| `party` | list | You, then your party and trusts, below |
| `bt` | table or nil | Your battle target: `{ name, hpp, dist }`, `dist` like `'4.3y'` |
| `pet` | table or nil | Your pet, the same shape as `bt` |
| `flags` | list of strings | What may be holding automation up, in this order: `'casting'`, `'moving'`, `'combat'`, `'safe zone'`, `'mounted'`, `'dead'`, `'resting'`, `'incapacitated'`, `'silenced'`, `'amnesia'` |
| `recent` | list | The last 10 actions sent, newest first: `{ age, text, why }`, e.g. `{ 12, 'Cure IV -> Kupipi', 'heal: Kupipi at 62%' }`; `age` in whole seconds |
| `heal` | table | Healing's settings, below |
| `wake` | bool | Sleeping members are woken with a heal that wakes |
| `recover` | table | `{ mp, tp, min_tp, spends_tp }`: recover MP under `mp` % (yours; a member's for Devotion), TP under `tp` (0 to 3000) in combat; Chivalry only from `min_tp` TP. `spends_tp`: a row spends TP (Chivalry), so `min_tp` is worth showing |
| `pet_heal` | number | Heal your pet under this HP % |
| `follow` | table | `{ on, target, distance, names }`: follow `target` (a name, `''` for none) once further than `distance` yalms; `names` are the members that can be followed |
| `rest` | table | `{ on, delay, distance }`: rest after `delay` seconds with nothing to do; stand when the follow target is further than `distance` yalms |
| `japanese` | bool | Spell and ability names are sent in Japanese |
| `log` | bool | Each action sent is printed to chat |
| `ui` | table | The UI's settings: `open` (bool), `display` (`'headers'`, `'tabs'` or `'groups'`), `size` (`'auto'` or `'custom'`), and any `ui.<name>` your UI saved. `display` and `size` are the standard window's; yours may ignore them |
| `sections` | list | What can be automated, by behavior, below |

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
| `tag` | string | `'ME'`, `'P1'` to `'P5'` |
| `kind` | string | `'self'`, `'party'` or `'trust'` |
| `name` | string | |
| `alive` | bool | |
| `away` | bool | In another zone: its HP and MP are stale |
| `hpp`, `mpp` | number | HP and MP, 0 to 100 |
| `hp` | string | `'ok'`, `'low'` (under the danger line) or `'critical'` (under the critical line); the focus member's own lines for them |
| `dist` | string | `''` for you, `'away'`, or like `'12.3y'` |
| `buffs` | string | Its statuses, the first 6 by name and `'+N'` for the rest |
| `buffs_all` | string | Every status, one per line (for a tooltip) |

### `view.heal`

`danger`, `critical`, `focus_danger`, `focus_critical` (HP %, 1 to 99); `focus` (a member's name, `''` for none); `cure_potency`, `waltz_potency` (+% from gear, 0 to 50); `regen_potency` (+HP per Regen tick from gear, 0 to 30); `focus_names` (the members that can be the focus, you excluded); `members` (`{ name, healed }` for each member, you excluded; `healed` false when skipped).

### `view.sections[i]`

In this order; a behavior with nothing for your job to do is left out.

| `id` | `title` | `group` |
|---|---|---|
| `'heal'` | Healing | Healing |
| `'remove'` | Debuffs | Support |
| `'buff'` | Buffs | Support |
| `'revive'` | Raise | Support |
| `'recover'` | Recovery | Support |
| `'pet'` | Pet | Support |
| `'move'` | Follow & rest | Utility |
| `'options'` | Options | Utility |

| Field | Type | What it is |
|---|---|---|
| `id`, `title`, `group` | string | As above. `group` is the page the standard window puts it on in its `'groups'` layout |
| `on` | bool or nil | The behavior's switch; nil for `move` and `options` |
| `rows` | list or nil | One per spell family or pick-one group, below; nil for `move` (its settings are `view.follow` and `view.rest`) and `options` (`view.japanese` and `view.log`) |
| `has_choices`, `has_targets` | bool or nil | Some row in the section has `choices` / `targets` (to lay out columns) |

### `view.sections[i].rows[j]`

| Field | Type | What it is |
|---|---|---|
| `key` | string | The row's id for `act`: a family (`'Cure'`, `'Haste'`) or a pick-one group (`'barelement'`, `'minuet'`) |
| `label` | string | `'Cure'`, `'Valor Minuet (+ATK)'`, `'Sword Madrigal / Blade Madrigal'` |
| `on` | bool | Rows start on, except buffs and sending the pet in (Assault, Fight, Deploy) |
| `ready` | bool | It could go right now |
| `avail` | string | `'ready'`, or why not: `'recast 12s'`, `'MP'`, `'TP'`, `'silenced'`, `'combat only'`, `'idle only'`, `'no ammo'`, `'pet too far'`, `'pick one'`, `'not available'`... |
| `action` | string or nil | When ready, the spell or ability it would use: `'Cure V'` |
| `choices` | list or nil | Buff rows with tiers or a pick-one group: `{ label, name }`. A tiered row's first choice is `'Auto (best)'` with `name` nil |
| `pick` | string or nil | The chosen `name`; nil is Auto |
| `choice` | string or nil | The label to show for the current pick: `'Auto (best)'`, `'Pick one'`, `'Protect II'`, `'Protect V (not available)'` |
| `targets` | list or nil | Buff rows that can go on others: 6 chips `{ slot, label, present, name, on }`, `slot` 0 (you, `'ME'`) to 5 (`'P5'`). `present` is false for an empty party slot (`name` is then nil) |

## `act`

| Function | What it does |
|---|---|
| `act.run(on)` | Automation on or off. This session only: it is always off after a load |
| `act.log(on)` | Print each action sent to chat, or not. This session only |
| `act.close()` | Hide the window (remembered); `/sk3` shows it again |
| `act.section(id, on)` | A behavior on or off: `'heal'`, `'remove'`, `'wake'`, `'recover'`, `'pet'`, `'buff'` or `'revive'` |
| `act.row(key, on)` | A row on or off |
| `act.pick(key, name)` | A row's choice: a `choices[i].name`, or nil for Auto |
| `act.target(key, slot)` | Turn a target chip (0 to 5) on or off |
| `act.skip(name)` | Skip a member in healing, or take them back: a `view.heal.members[i].name` |
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
| `'follow.on'`, `'rest.on'` | bool |
| `'follow.target'` | a name from `view.follow.names`, or `''` |
| `'follow.distance'`, `'rest.distance'` | 1 to 15 |
| `'rest.delay'` | 1 to 20 |
| `'japanese'` | bool |
| `'ui.display'`, `'ui.size'` | as in `view.ui` |
| `'ui.<name>'` | your UI's own: a string, number or bool |

Nothing is checked, so keep values in range. Settings are kept per job pair (one file for WHM/BLM, another for WHM/SCH), so a UI's own `ui.<name>` is too.

### Saving

Sidekick saves after any `act` call that changes a setting, once no ImGui widget is held. Call `act.set` on every frame a slider moves; it is saved when the slider is let go.

## ImGui in Ashita

`local imgui = require('imgui')`. Ashita's binding differs from C++ ImGui in a few ways:

- **Widget values are one-element tables.** `local v = { view.japanese }` then `if imgui.Checkbox('Japanese', v) then act.set('japanese', v[1]) end`. The same for `SliderInt`, `InputText` and the rest.
- **`Text`, `TextColored` and `SetTooltip` take a printf format.** A `%` in what you show must be doubled: `imgui.Text((s:gsub('%%', '%%%%')))`. `why` texts and HP like `'62%'` need it.
- **Labels are ids.** Two widgets with the same label in one window clash; add a unique suffix after `##` (`'On##heal'`), which isn't shown. Use `###` to keep the id when the label changes (`'Recent (3)###recent'`).
- **Close what you open.** `Begin` always needs `End`. `BeginTable`, `BeginCombo`, `BeginTabBar`, `BeginTabItem` and `BeginPopup*` need their `End*` only when they returned true. Every `Push*` needs its `Pop*`.
- **Constants** like `ImGuiWindowFlags_NoTitleBar` are globals `require('imgui')` defines. When you use a new one, add it to `read_globals` in `.luacheckrc`: luacheck then accepts it, and the test below defines it.

## Test it

```
luajit tests/run.lua ui_window
```

With `ui/custom.lua` present, this also draws it through a fake ImGui in every layout, running and stopped, and fails on a Lua error or an ImGui scope left open. The fake answers `false` to calls it has no handler for; if your UI needs a number back (a width, say), add a handler in `tests/ui_window_test.lua`. In the game, `/addon reload sidekick3` picks up each change.

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
        if sec.rows then
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
