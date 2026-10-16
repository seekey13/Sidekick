# HUD UI pivot: implementation plan

Branch `UI-pivot`. Written 2026-10-16 at the end of the session that designed it; the user approved the design and the three choices under [Decisions](#decisions). Implement it in one go: the branch is half-done and `ui/model.lua` does not load until step 1 is in.

## Goal

Replace the standard window (`ui/window.lua`) with two windows:

1. **Sidekick3**, a heads-up display of the party's HP and MP, drawn to the user's mockup.
2. **SK Settings**, every setting under collapsing headers, opened from the HUD's cog.

Mockup (the user's image; white = transparent):

```
 ┌─────────────────────────────┐
 │ Sidekick3          [▶][⚙][⊗]│   title row: grey panel, black bold text, black icons
 │┌───────────────────────────┐│
 ││                       100%││   HP bar: pink gradient, % top-right
 ││Seekey                     ││   name: large, bottom-left
 │├───────────────────────────┤│
 ││ME                     100%││   MP bar: olive gradient, tag left, % right
 │└───────────────────────────┘│
 │            ...              │
 │┌───────────────────────────┐│
 ││▌                       10%││   critical HP: name and % in #F07A7A
 ││Commandobill               ││ ◀ Heal:Cure III     arrow at whoever the next action is for
 │├───────────────────────────┤│
 ││P2                     100%││
 │└───────────────────────────┘│
 └─────────────────────────────┘
```

## Decisions

From the user, this session:

- Use the ImGui default font. Keep the spirit of the mockup's structure. The window is transparent outside the grey panel.
- Colours: typical text `#FFFFFF`. Under the critical HP line, or under the Recover MP line, text is `#F07A7A`. HP gradient `#FF9090` (top) to `#E37476` (bottom). MP gradient `#D1D18E` to `#BABF74`.
- The X closes the HUD (as `act.close()` does now).
- The cog opens a separate **SK Settings** window: auto-sized, collapsing section headers only, and its own close X. Do **not** recreate the other features. The tabs and pages layouts, the auto or custom window size, the right-click menus, and the old header, party table and recent actions panels all go. This reverses the earlier "keep all three display modes and both size modes" decision.
- Headers, in this order: **Follow, Heal, Remove, Buff, Pet, Recover, UI / Log**. v2's sections map onto them:

  | v2 section | Header |
  |---|---|
  | Auto Follow | Follow |
  | Focus Healing, Group Healing, AOE Healing, Revive | Heal |
  | Sleep Removal, Debuff Removal, Item Debuff Removal | Remove |
  | Buffs, Rolls, Geo | Buff |
  | Pet Control, Pet Healing, Pet Debuff Removal | Pet |
  | Resting, Resource Recovery | Recover |
  | (new) | UI / Log |

- UI / Log has sliders for HP bar width and height, MP bar width and height, font sizes, and anything else that configures the HUD. Its Log part is the current Recent actions list.
- The SVG icons the user supplied (MDI `cog` and `close-circle`) can't be loaded by ImGui. Draw them as shapes (see [Icons](#icons)); no image files are needed.
- **The three choices the user approved** ("no change to the 3"):
  1. Start/Stop is a play/stop icon in the HUD title row, left of the cog, in the same style.
  2. `cfg.ui` is shared by every job pair (its own settings file, `ui.lua`), so HUD sizes don't reset when you change job. This settles the open "per job pair or global" UI question in the masterplan memory.
  3. The tabs and pages layouts and the auto or custom size modes are removed.

## State of the branch

Uncommitted:

- **`core/settings.lua`: done.** `DEFAULTS.ui = { open = false, hp_width = 220, hp_height = 40, mp_width = 220, mp_height = 18, name_size = 22, text_size = 14, gap = 8, opacity = 100, locked = false }`. `settings.load(pair)` loads the job pair's file without `ui`, then sets `loaded.ui = lib.load(ui_defaults, 'ui')`. `settings.save()` nils `loaded.ui` while saving the pair's file, then saves `'ui'`. An old pair file's stale `ui` key is dropped on its next save.
- **`ui/model.lua`: partial.** Done so far:
  - The new `model.SECTIONS` list (below).
  - `POINTED` and `POINTED_CAST` constants.
  - `wakes` computed beside `spends_tp`.
  - `view.wake` removed.
  - Each section built with `header` and `on = cfg[s.id].on`; wake is shown only when `wakes`.
  - `view.pointer = pointer(...)` is called, **but `pointer` is not defined yet** and party entries lack `mp` and `uses_mp`. Step 1 fixes both.
- Untouched: `ui/window.lua`, `tests/ui_window_test.lua`, `tests/ui_model_test.lua`, `ui/README.md`, `.luacheckrc`. `Sidekick3.lua` needs no change: it only reads `cfg.ui.open`.

Auto mode's server-side check gave no verdict on Edit and Write all session ("skipped this action"); shell commands were fine. Implement in the accept-edits mode.

## Step 1: finish `ui/model.lua`

Replace `party` and `entity` with this. It adds `uses_mp`, `mp` and `pointer`:

```lua
local function party(g, cfg, statuses)
    local out = {}
    for _, u in ipairs(g.units) do
        local buffs, all = buff_names(u.buffs, statuses)
        out[#out + 1] = {
            tag = SLOT_LABELS[u.slot], kind = u.kind, name = u.name, alive = u.alive, away = not u.in_zone,
            hpp = u.hpp, hp = hp_state(u, cfg.heal), mpp = u.mpp, uses_mp = u.uses_mp == true,
            mp = u.uses_mp and u.mpp < cfg.recover.mp and 'low' or 'ok',
            dist = not u.in_zone and 'away' or u.kind == 'self' and '' or ('%.1fy'):format(u.dist or 0),
            buffs = buffs, buffs_all = all,
        }
    end
    return out
end

local function entity(e)
    return e and { name = e.name, hpp = e.hpp, dist = ('%.1fy'):format(e.dist or 0) }
end

-- What the HUD points at: running, the decision about to go, else what was just
-- sent while it lands; stopped, what it would do. `member` is the party line it
-- is for: the target's, else yours (an action on you, the enemy or your pet,
-- which is then named).
local function pointer(status, g, members)
    local e = status.intent
    if status.running and not e then
        local last = status.sent[1]
        local age = last and g.now - last.at
        if age and (age < POINTED or g.casting and age < POINTED_CAST) then e = last end
    end
    if not e then return nil end
    local member = 1
    for i, p in ipairs(members) do
        if p.name == e.target then member = i end
    end
    local text = ('%s:%s'):format((e.behavior:gsub('_.*', ''):gsub('^%l', string.upper)), e.action)
    if e.target and members[member].name ~= e.target then text = ('%s -> %s'):format(text, e.target) end
    return { text = text, member = member, live = status.running }
end
```

Why the hold: while running, `status.intent` is nil during a cast (the `casting` gate), so without it the arrow would flash for a single tick. Status entries carry `target` as a name (`entry()` in `Sidekick3.lua`); pet care and at-enemy actions have no target, so they point at your own card. `pet_send` reads as `Pet:`.

`model.SECTIONS`, already in the file:

| id | title (switch label) | header | rows |
|---|---|---|---|
| follow | Follow | Follow | |
| heal | Healing | Heal | heal, emergency |
| revive | Revive | Heal | revive |
| wake | Wake sleepers | Remove | (only when a non-pet `heal` row `wakes`) |
| remove | Debuff removal | Remove | remove (spells, then items) |
| buff | Buffs | Buff | buff |
| pet | Pet | Pet | pet_heal, pet_remove, pet_send |
| recover | Recovery | Recover | recover |
| rest | Resting | Recover | |
| ui | UI / Log | UI / Log | (no switch: `cfg.ui.on` is nil) |

A section with roles but no rows is still left out, so Pet appears only for pet jobs. Every section but `ui` has `on`, and `act.section(id, on)` already writes `cfg[id].on` for any of them (follow and rest included). Its comment lists the ids.

## Step 2: rewrite `ui/window.lua`

Keep: the header comment's Ashita notes, `esc`, `text`, `tip`, `push_button`, `slider`, `checkbox`, `member_combo`, `HEAL_LINES`, `heal_members`, the heal, recover and pet setting bodies, `pick_combo`, `target_chips`, the row table, and the pcall-then-End-then-raise pattern.

Remove: `GREEN`/`RED`/`YELLOW` if unused, `HP_BAR`, `START`/`STOP`, `DISPLAYS`, `SIZES`, `page`, `choose`, `display_menu`, `size_menu`, `draw_header`, `draw_member`, `draw_party`, `draw_recent` (its list moves into UI / Log), `section_switch`, `header_section`, `tab_section`, `tab_bar`, `pages` and `draw_sections`.

Module state: `act` (this frame's) and `settings_open` (SK Settings shown; this session only).

```lua
function window.render(view, act_)
    act = act_
    local err = hud(view)                                   -- Begin, pcall(body), End; returns the error
    if settings_open then err = settings_window(view) or err end
    if err then error(err, 0) end
end
```

### HUD window

Flags: `NoTitleBar + NoResize + NoScrollbar + NoScrollWithMouse + AlwaysAutoResize + NoBackground + NoBringToFrontOnFocus`, plus `NoMove` when `view.ui.locked`. Before `Begin`, push `ImGuiStyleVar_WindowPadding {0, 0}` and `ImGuiStyleVar_WindowBorderSize 0`; `PopStyleVar(2)` straight after `Begin`, whatever it returned. ImGui keeps window positions in `Ashita/config/imgui.ini`, so there's nothing to save.

Draw everything with `imgui.GetWindowDrawList()`. Reserve space and hover areas with `SetCursorScreenPos` and `Dummy`, which leave the window draggable, and use `InvisibleButton` for the icons. `local x0, y0 = imgui.GetCursorScreenPos()` right after `Begin` is the panel's top-left.

Layout, measured off the mockup (drawn at text size 20; scale with `ui.text_size`):

| Name | Value | Mockup |
|---|---|---|
| `B`, border | 2 px black (`#000000`) | 2 |
| `PAD`, panel padding (sides, bottom) | 4 px | 4 |
| `TH`, title row height | `floor(text_size * 1.7)` | 34 |
| Icon size `S` | `floor(text_size * 1.25)`; 4 px apart, 6 px from the right, centred in the title row | 24 |
| Title text | "Sidekick3", `text_size`, black, bold (stamped twice, +1 px x), x0 + 8, centred | |
| Card height `CH` | `B + hp_height + B + mp_height + B` | 93 |
| HP fill | `(x0 + PAD + B, y + B)`, `hp_width x hp_height` | 318 x 60 |
| MP fill | `(x0 + PAD + B, y + B + hp_height + B)`, `mp_width x mp_height` | 318 x 27 |
| Between cards | `ui.gap` | 13 |
| Panel | `PW = 2*PAD + 2*B + max(hp_width, mp_width)`, `PH = TH + n*CH + (n-1)*gap + PAD` | 330 wide |
| Panel colour | `#606060` at `ui.opacity` % | |
| Empty bar | `#2E2E2E` | |

Each bar: black rect `B` px around the fill (the HP bar's bottom border is the MP bar's top), the empty colour over the fill, then `AddRectFilledMultiColor(min, max, top, top, bottom, bottom)` up to `floor(w * pct / 100 + 0.5)`.

Text. The size is in pixels: `dl:AddText(imgui.GetFont(), size, { x, y }, col, s)`, as the user's own Floaties addon does. Measure with `CalcTextSize(s)` scaled by `size / imgui.GetFontSize()`. Floor x and y. The outline is the string stamped in black at the 8 one-pixel offsets, then the fill. Draw-list text is **not** printf, so no `%` doubling.

- Name: `name_size`, at fill x + 4, its bottom on the HP fill's bottom.
- HP%: `text_size`, right-aligned at fill right - 4, top at HP fill top + 1.
- Tag (`ME`, `P1`...) at MP fill x + 4, and MP% right-aligned at - 4: `text_size`, centred on the MP fill.
- Colours: white. Name and HP% are `#F07A7A` when `p.hp == 'critical'`; tag and MP% when `p.mp == 'low'`. Away members' text is `#A0A0A0`.

Hovers (`Dummy` then `IsItemHovered`, then `SetTooltip` through `tip()`):

- The title area left of the icons: `view.job`, then `view.status.state: view.status.text`, `(dim)` if any, and `view.flags`.
- Each card: name (trust, KO, away), HP %, MP %, `dist`, then `buffs_all`. This keeps the old party table's information.

End with a `Dummy` for the bottom `PAD` so auto-resize takes it in.

Icon clicks: `'##sk3_run'` calls `act.run(not view.status.running)`; `'##sk3_cog'` toggles `settings_open`; `'##sk3_close'` calls `act.close()` and sets `settings_open = false`. Tooltips: "Start automation" or "Stop automation", "Settings", "Close (/sk3 opens it again)".

#### Icons

All drawn in a 24-unit box scaled by `k = S / 24`, using MDI's geometry. The icon colour is `#000000`, `#FFFFFF` while hovered. Cut-outs are drawn in the panel colour at full alpha. Only use draw-list calls already seen working in installed addons: `AddRectFilled`, `AddRect`, `AddRectFilledMultiColor`, `AddText`, `AddLine`, `AddCircleFilled`, `AddTriangleFilled`, `AddTriangle`. `PathFillConvex` is missing from Ashita's binding (fancycompass notes this), and `AddQuadFilled` is unverified, so build quads from two triangles.

- **close-circle**: circle at (12,12) r 10; two lines (8,8)–(16,16) and (16,8)–(8,16), thickness 2k, in the panel colour.
- **cog**: body circle r 7.5. Eight teeth at `i * 45°` (one pointing straight up), each a trapezoid from radius 6 to 10.2, 2.3 half-width at the base and 1.9 at the tip (two triangles). Hole: circle r 3.5 in the panel colour.
- **play** (stopped): circle r 10; triangle (10,7.5), (16,12), (10,16.5) in the panel colour.
- **stop** (running): circle r 10; rect (9,9)–(15,15) in the panel colour.

#### The arrow

Drawn on `imgui.GetBackgroundDrawList()`, so it sits outside the window without making the window wider; a transparent window area would block game clicks, and other windows cover it. Draw it only when `view.pointer` is set, at card `view.pointer.member`.

- Tip at `(panel right + 1, card centre y)`, pointing left. Base at `tip + AW`, with `AW = text_size * 1.75` (35 in the mockup) and half-height `AW * 0.6`.
- Live (`pointer.live`): fill `#FFE545`, an inner triangle `#FFFB5B` for the mockup's bevel, and a 1 px outline `#8E781F` (`AddTriangle`). Stopped, so a "would do": `#B4B4B4` / `#D2D2D2` / `#5A5A5A`, with the label's text in `#D0D0D0`.
- Label: `pointer.text` at base + 4, `text_size`, outlined, vertically centred.

### SK Settings window

`imgui.Begin('SK Settings', open, ImGuiWindowFlags_AlwaysAutoResize)`; the ImGui close X sets `settings_open = false`.

- **Headers.** Group `view.sections` by `header`, in order of first appearance: `CollapsingHeader(label .. '###sk3_' .. header)`, **closed by default** so the auto-size stays small. Label: the header, plus ` (off)` when it has switches and all of them are off.
- **Inside a header.** Sections are separated by `Separator`. Each starts with its switch when `s.on ~= nil`: `Checkbox(s.title .. '##sk3_on_' .. s.id)` calls `act.section`. Then the body:
  - follow: Leader combo (`member_combo(..., 'follow_target', ...)`) and the "Follow past" slider.
  - heal: the existing heal settings **without** the wake checkbox, then rows.
  - revive, buff: rows.
  - wake: the switch only.
  - remove: spell rows, then a "Items" label and the item rows (rows with `count`), as two tables.
  - pet: "Pet HP under" slider, then rows.
  - recover: the existing sliders, then rows.
  - rest: "Rest after" and "Stand past" sliders.
  - ui: see below.
- **Row tables.** Work out the choice and target columns per table, so the item table has no empty columns. Keep the existing ids (`'Protect##buff_Protect'`, `'Echo Drops (0)###remove_Echo Drops'`, `'P1##buff_Protect1'`...).
- **UI / Log.**
  - Sliders, each writing `act.set('ui.<key>', v)` with ids `'<label>##sk3_ui_<key>'`:

    | Label | Key | Range |
    |---|---|---|
    | HP bar width | hp_width | 80–600 |
    | HP bar height | hp_height | 10–120 |
    | MP bar width | mp_width | 80–600 |
    | MP bar height | mp_height | 4–80 |
    | Name font size | name_size | 8–64 |
    | Text font size | text_size | 8–48 |
    | Spacing | gap | 0–40 |
    | Background opacity | opacity | 0–100 |

  - Then "Lock position" (`ui.locked`).
  - Then "Log": "Action log" (`act.log`) and the recent list (`age`s, text, grey why; "Nothing sent yet.").
  - Last, "Japanese client".

## Step 3: tests

**`tests/ui_window_test.lua`, the fake imgui.** Add handlers:

- `GetCursorScreenPos` returns `100, 50`; `GetFontSize` returns 13; `GetFont` returns `'font'`.
- `GetColorU32(c)` returns `c`, so tests can compare colours.
- `GetWindowDrawList` and `GetBackgroundDrawList` return a fake list whose every method records `{ list, name, args }`. Its `AddText` asserts a string and records the raw text.
- `InvisibleButton` returns `clicks[label] == true`; add it to `IDS`.
- `PushStyleVar` goes in `CLOSER` and `ALWAYS`, with a `PopStyleVar(n)` handler like `PopStyleColor`'s.

**Delete:** the display-mode, tabs, groups and right-click-menu tests, and `'Wake sleepers##sk3_wake'`. `settings_open` persists between tests, so add a helper that clicks `'##sk3_cog'` when the last frame's `Begin` labels lack `'SK Settings'`.

**Add or update:**

- Both windows draw, running and stopped, with every scope closed. SK Settings appears only after the cog, and its close hides it.
- A card per member: names, `'62%'` (raw), tags and MP% drawn with AddText.
- Colours:
  - Critical HP gives a name and HP% in `#F07A7A`.
  - MP under `recover.mp` gives a tag and MP% in red.
  - A unit with `uses_mp = false` at 0% stays white.
- Arrow: `'Heal:Cure IV'` on the background list at member A's card; live colour when running, grey when stopped; none when `pointer` is nil.
- The run icon toggles `status.running` (no settings write). Close calls `act.close` (1 write) and hides SK Settings.
- Headers in order for WHM 75 / BLM 37: Follow, Heal, Remove, Buff (` (off)` with `buff.on = false`), Recover, UI / Log. Pet appears for a pet job.
- Switches write: `'Buffs##sk3_on_buff'`, `'Follow##sk3_on_follow'`, `'Wake sleepers##sk3_on_wake'`, `'Resting##sk3_on_rest'`.
- Keep the row, pick, target, slider, focus, Japanese, log and skip tests (their labels don't change).
- HUD sliders write `ui.*`; Lock position adds `NoMove` to the HUD's flags.
- The custom-UI test loops over running and stopped only.

**`tests/ui_model_test.lua`.**

- Section ids for WHM 75 / BLM 37: `{ 'follow', 'heal', 'revive', 'wake', 'remove', 'buff', 'recover', 'rest', 'ui' }`, plus the titles and headers.
- BLM 75: no wake and no revive. Check that its heal rows don't `wake`.
- In "section switches...", swap the `ui.display` / `ui.size` uses for `ui.hp_width` and a UI's own key.
- New pointer tests:
  - Stopped: the intent's text is `'Heal:Cure IV'`, `member` is A's index and `live` is false.
  - Running with no intent: sent 1 s ago gives the last send; 3 s ago and not casting gives nil; casting and 10 s ago gives the last send.
  - Target `'Carbuncle'` gives member 1 and `' -> Carbuncle'`.
  - Behavior `pet_send` reads `'Pet:'`.
- New party-MP test: `mp` is `'low'` under `recover.mp` only when `uses_mp`.
- `act.section('follow', true)` and `act.section('rest', true)` write.

## Step 4: `.luacheckrc`, README, docs

- **`.luacheckrc`.** The window test defines exactly the `ImGui*` names listed in `read_globals`.
  - Add `ImGuiWindowFlags_NoTitleBar`, `NoScrollbar`, `NoScrollWithMouse`, `NoBackground`, `NoBringToFrontOnFocus`, `NoMove`, `ImGuiStyleVar_WindowPadding` and `ImGuiStyleVar_WindowBorderSize`.
  - Drop the ones no longer used (tab bar, tab item and popup flags, `PlotHistogram`, and `TreeNodeFlags_DefaultOpen` if the headers start closed).
- **`ui/README.md`**, the custom-UI contract. Update:
  - Remove `view.wake`. Document `view.pointer` (`{ text, member, live }` or nil) and the party fields `uses_mp` and `mp` (`'ok' | 'low'`).
  - `view.ui` keys and ranges, now shared by every job pair: no `display` or `size`.
  - The new sections table (`id`, `title`, `header`, `on`; wake's condition); every section but `ui` has `on`.
  - `act.section` ids; the `act.set` paths for `ui.*` (drop `ui.display` and `ui.size`).
  - The "Settings are kept per job pair" line: `ui` is shared.
  - Note that draw-list `AddText` takes text as is.
  - The example: switch on `sec.on ~= nil`.
  - The test section: running and stopped, no layouts.
- **`docs/superpowers/plans/masterplan.md`.** Add a Status row for the HUD pivot.
- **Memory** (`sidekick3-rewrite.md`). The display and size modes were dropped by the user on 2026-10-16, and `cfg.ui` is now global. Remove the open-question line.

## Verify

```
luajit tests/run.lua        # all green
luacheck .                  # clean
```

In game (nothing here has been run in game): `/addon reload sidekick3`, `/sk3`.

- The panel is grey and the rest of the window transparent; dragging works, and doesn't once locked.
- The icons click; the cog opens and closes SK Settings.
- The bars match the mockup's gradients; critical and low-MP text turns red.
- The arrow follows the next target and is yellow while running, grey while stopped.
- The UI / Log sliders resize live, and the sizes survive a job change.
- Then check frame time with six members.

Delete this plan once it has landed, as with the healing spec.
