# The vana UI style

How VanaCore's `/vana` settings window gets its look, and how Sidekick3's `ui/kit.lua` builds its windows the same
way ([In Sidekick3](#in-sidekick3)).

It is still Dear ImGui (1.92.3). The window turns off nearly everything ImGui draws and paints every control itself on
ImGui's draw lists. ImGui is left with three jobs: taking mouse input, scrolling, and the few widgets that are hard to
redo by hand (the text box, popups, the colour picker).

**Source:** VanaCore's `addons\vanacore\vana\`. `draw.lua` holds the palette, scale, fonts, helpers and controls.
`vana.lua` holds the window, the sidebar, and the section and row layout. Line references below are to those files.

**Licence:** VanaCore is GPL-3.0-or-later, and its `LICENSING.md` says an addon that copies VanaCore's code, or is
otherwise based on it, is not an independent module. Sidekick3 is GPL-3.0-or-later too (`LICENSE`), so `ui/kit.lua`
is based on `draw.lua` in the open, with a notice in its header and in the README. The vana logo is all rights reserved
and outside the GPL: don't copy it. VanaCore's name may say what Sidekick3 is based on, never that it is VanaCore or
made or endorsed by Vekien.

**Why it works in Sidekick3:** under VanaCore, an Ashita addon's `require('imgui')` loads Ashita 4.30's `imgui.lua`.
That file forwards every call to `AshitaCore:GetGuiManager()`, and VanaCore's `compat\ashita.lua` sets that to
`vana.imgui`. So Sidekick3 has the same ImGui as vana, with `PushFont(font, size)`, `AddFontFromFileTTF`, draw lists
and `InvisibleButton`. On the stock CatsEyeXI Ashita 4.16 client (ImGui 1.81) the fonts part doesn't work; see
[In Sidekick3](#in-sidekick3).

---

## 1. The idea

- **An empty ImGui window.** No title bar, background, border, padding, item spacing or scrollbar. The panel, the
  sidebar, the outline and the shadow are filled rectangles.
- **A control is a hit box plus a drawing.** Each control puts an `InvisibleButton` where it will be, reads hovered,
  clicked and held from it, then draws itself with `AddRectFilled`, `AddCircleFilled`, `AddLine` and `AddText`. It
  takes a value and returns `(new_value, changed)`. It holds no state and reads or writes no settings.
- **Three rules apply to everything:**
  - every size goes through `S(n)`, the scale;
  - every colour comes from one palette;
  - every state change (on/off, hover, selected) is eased, never instant.
- **ImGui widgets are kept only where redrawing them isn't worth it:** `BeginChild` for scrolling, `InputTextWithHint`
  for search, `BeginPopup` + `Selectable` for dropdown lists, `ColorPicker3`, and tooltips. Each one gets the palette
  pushed onto it first.

---

## 2. Palette

One table of `#RRGGBB` strings (`draw.lua:42`). The theme is dark navy with one blue accent, and greys picked so text
can be ranked: `white` > `text` > `text2` > `dim` > `faint`.

| Token | Hex | Used for |
|---|---|---|
| `bg` | `#161822` | Page background |
| `side` | `#10121A` | Sidebar (darker than the page) |
| `border` | `#2A2E3E` | Window outline, sidebar divider, line under the title bar |
| `line` | `#242838` | Section heading hairline, sub-tab rail, status box edge |
| `well` | `#0E1017` | Sunken boxes: dropdown, segments, stepper, status box |
| `well_edge` | `#272B3C` | Their outline |
| `search` | `#080A10` | Search box: darker than the sidebar behind it |
| `search_edge` | `#3E4460` | Its outline, lighter so the box stands out |
| `hover` | `#1F2334` | Hover band behind a row or nav item |
| `white` | `#FFFFFF` | Page title, section titles, nav names |
| `text` | `#E8EAF1` | Row labels, main text |
| `text2` | `#BDC1D0` | Values, dropdown text, swatch labels |
| `dim` | `#7B8095` | Tags, unselected segments, chevrons, disabled labels |
| `faint` | `#4E536A` | Hints ("custom"), group labels, idle icons, slider ticks |
| `accent` | `#7AA2F7` | Switch on, slider fill, active nav bar, primary button |
| `accent2` | `#A9C1FF` | Pressed knob, hover tint on titles, pill text |
| `accent_lo` | `#3E5CB3` | Outline when hovered or open, pressed scrollbar, pill edge |
| `accent_bg` | `#1B2340` | Active nav item, pill fill, selected popup row |
| `teal` | `#5FD3B3` | Sub-panel headings |
| `amber` | `#E8B45C` | `*` "needs a restart", "in progress" |
| `rose` | `#EE6F78` | Close and delete, danger headings, warning boxes |
| `knob` | `#F2F3F8` | Switch and slider knobs |
| `off` | `#2B2F42` | Switch off, empty slider track |
| `seg` | `#313752` | Selected segment, keycap, secondary button |
| `ink` | `#0B1020` | Text on an `accent` fill |

Also used: popup and tooltip background `#0F1118`; scrollbar grab `#3A4158`, `#4A5270` when hovered, `accent_lo` when
held.

Colours stay hex strings until they're drawn. Two helpers convert and blend them:

```lua
-- '#RRGGBB' and an alpha to an ImU32 (0xAABBGGRR), for a draw list
local function u32(hex, alpha)
    local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
    local a = math.floor(math.max(0, math.min(1, alpha or 1)) * 255 + 0.5)
    return ((a * 256 + b) * 256 + g) * 256 + r
end

-- '#RRGGBB' and an alpha to { r, g, b, a }, for PushStyleColor
local function rgba(hex, alpha)
    return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255, alpha or 1 }
end

-- the colour t of the way from a to b (t from 0 to 1): how every eased state is coloured
local function mix(a, b, t)
    t = math.max(0, math.min(1, t))
    local out = '#'
    for i = 2, 6, 2 do
        local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
        out = out .. string.format('%02X', math.floor(x + (y - x) * t + 0.5))
    end
    return out
end
```

---

## 3. Scale

Every pixel value in this doc is unscaled. Each one goes through `S`:

```lua
local scale = 1
local function S(n) return math.floor(n * scale + 0.5) end

-- the screen's height sets the base (1440 px tall = 1.0, kept between 0.75 and 1.6), times 1.1, times the user's own
-- scale (0.5 to 3). Recomputed at most once a second, or right away when the user's scale changes.
local function set_scale(screen_h, user)
    scale = math.max(0.75, math.min(1.6, screen_h / 1440)) * 1.1 * math.max(0.5, math.min(3, user or 1))
end
```

The screen height comes from `imgui.GetIO().DisplaySize.y` (UberMap reads it the same way).

Rounding inside `S` keeps edges on whole pixels. Without it, 1 px lines blur at scales like 1.21. Font sizes pass
through `S` as well, so text and boxes always grow together.

---

## 4. Type

Segoe UI (every Windows has it) for text. Icons are Font Awesome 6, which VanaCore merges into ImGui's default font
(`fonts\imgui\`).

| Role | Face | Size | Colour |
|---|---|---|---|
| Section heading ("Shadows") | Segoe UI Bold Italic (`segoeuiz.ttf`) | 21 | `white` |
| Page title | Segoe UI Semibold (`seguisb.ttf`) | 19 | `white` |
| Row label | Segoe UI (`segoeui.ttf`) | 16 | `text` (`dim` when disabled) |
| Nav item | Segoe UI | 16.5 | `white` |
| Sub-tab | Segoe UI | 15.5 | `dim`; `white` when shown |
| Segments | Segoe UI | 15 (17 for the Low/Medium/High/Max strip) | `dim` → `text` when selected |
| Value, dropdown, button | Segoe UI | 14 | `text2` |
| Tooltip | Segoe UI | 14 | `text` |
| Sub-panel heading | Segoe UI Semibold Italic (`seguisbi.ttf`), CAPITALS, +1.2 px letter spacing | 13.5 | `teal` |
| Tag, note | Segoe UI | 13 to 13.5 | `dim` / `faint` |
| Group label ("TOOLS") | Segoe UI Semibold, CAPITALS | 12 | `faint` |
| Pill ("DX12") | Segoe UI Semibold | 11.5 | `accent2` |

In code these are `BODY = 16` and `SMALL = 13.5`, with offsets from them (`BODY + 5`, `SMALL - 1.5`).

**Loading fonts.** Add them once, on the first frame the window opens, and draw nothing that frame: ImGui can't use a
font in the frame it was added. Load them at one size (18) and choose the size at draw time with
`PushFont(font, size)`. ImGui 1.92 renders glyphs at whatever size is asked, so text stays sharp at any scale.

```lua
local fonts = { ready = false }

local function load_fonts()
    local dir = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    local function add(file, fallback)
        local f = io.open(dir .. file, 'rb')
        if f == nil then return fallback end
        f:close()
        return imgui.AddFontFromFileTTF(dir .. file, 18) or fallback
    end
    fonts.icons = imgui.GetFont()                   -- the default font, with Font Awesome merged in
    fonts.text = add('segoeui.ttf', fonts.icons)
    fonts.semi = add('seguisb.ttf', fonts.text)
    fonts.bold_italic = add('segoeuiz.ttf', fonts.semi)
    fonts.semi_italic = add('seguisbi.ttf', fonts.semi)
end

-- in render():
if not fonts.ready then
    fonts.ready = true
    pcall(load_fonts)
    return -- usable from the next frame
end
```

**Measuring.** The same labels are measured every frame, so cache `CalcTextSize` by font, size and string. Clear the
cache when the scale changes, and when it grows past a few thousand entries (live values keep adding new strings).

```lua
local measured, measured_scale, measured_n = {}, nil, 0

local function measure(str, font, size)
    if measured_scale ~= scale or measured_n > 4000 then
        measured, measured_scale, measured_n = {}, scale, 0
    end
    local key = tostring(font) .. '|' .. size .. '|' .. str
    local m = measured[key]
    if m == nil then
        imgui.PushFont(font, S(size))
        local w, h = imgui.CalcTextSize(str)
        imgui.PopFont()
        m = { w, h }
        measured[key] = m
        measured_n = measured_n + 1
    end
    return m[1], m[2]
end
```

**Centring text.** ImGui's text box is a full line, with descent included, so text centred by its box sits low.
Raise it by 6% of the line height:

```lua
local function text(dl, x, y, str, color, font, size, alpha)
    imgui.PushFont(font, S(size))
    dl:AddText({ x, y }, u32(color, alpha), str)
    imgui.PopFont()
end

-- text with its middle at cy
local function text_mid(dl, x, cy, str, color, font, size, alpha)
    local _, h = measure(str, font, size)
    text(dl, x, cy - h / 2 - math.floor(h * 0.06 + 0.5), str, color, font, size, alpha)
end
```

Right-aligned and box-centred variants are the same idea. ImGui has no letter spacing, so the spaced capitals of a
sub-panel heading are drawn one character at a time, `1.2` px apart beyond the font's own advance.

**Icons.** A Font Awesome code point (`0xF013` gear, `0xF0E2` reset, `0xF00D` close, `0xF078` down, `0xF054` right,
`0xF0C9` bars...) as three bytes of UTF-8, drawn in `fonts.icons` and centred on a point:

```lua
local function fa(cp) -- U+E000..U+F8FF
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
```

---

## 5. Layout

### The window

```
┌ 6 px margin, room for the shadow ──────────────────────────────────────────────┐
│ ┌─ sidebar 159 ─┬─ page 492 ─────────────────────────────────────────────────┐ │
│ │ ┌ Search ───┐ │ ≡  Graphics   Preset: [ None ▾ ]                        ×  │ │ title bar 36
│ │ └───────────┘ ├────────────────────────────────────────────────────────────┤ │
│ │ GROUP       ▾ │            [ Low | Medium | High | Max ]  custom           │ │ quality strip 44
│ │▌▣ Graphics  ▾ │ ▾ Shadows ─────────────────────────────────────── ↺  (●)   │ │ heading 36
│ │  │ DLSS       │   Strength                       ↺ ━━━━━━●──────    0.45   │ │ row 27
│ │  ▌ Shadows    │   Cast by                         [ All | Characters | … ] │ │ row 27
│ │  ⋮            │   …                                                        │ │
│ │ ───────────── │                                                            │ │
│ │ TOOLS         │                                                            │ │
│ │  ▥ Stats      │                                                            │ │
│ └───────────────┴────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
```

### A row

```
x    x+12   x+24                                              right−200          right   x+w
│     ▾      Label  *                                          ↺  ━━━━━●──────  0.45 │  18  │
      │      │      └ amber "needs a restart"                  └─ slider, 200 wide ──┘
   chevron  labels and titles start here                              (right-aligned)
```

Labels are left-aligned at `LEFT`. Controls are right-aligned to `right = x + w − PAD`. Each control is placed by its
right edge: a switch at `right − 32`, a slider at `right − 200`, segments at `right − their width`.

### Measurements (unscaled px)

| Part | Size |
|---|---|
| Window | 651 × 540 (sidebar 159 + page 492), plus a 6 px margin all round; corner radius 5 |
| Shadow | Black at 0.35, 1 px past the panel left and right and 2 px below, radius 6 |
| Title bar | 36 high, `border` line under it; ≡ icon centred at 15, title at 30, × at `right` |
| Quality strip | 44 high, segments centred, "custom" in `faint` 10 px after when no tier matches |
| Section heading | 36 high (its centre 2 px below the middle); rows start 2 px under it; 4 px after a section |
| Row | 27 high (39 with tick marks under a slider) |
| Sub-panel heading | 27 high, with 16 above and 8 below |
| Left margin `LEFT` | 24; chevrons centred at `GUTTER` 12 |
| Right margin `PAD` | 18 |
| Hover band | Inset 4 from both sides, radius 3, `hover` at 0.8 |
| Sidebar | Search box 30 high, 12 from the top, inset 18, radius 6; group label 18; item 25; sub-tab 22; 6 between groups |
| Scrollbar | 6 wide, rounding 3, transparent track |

---

## 6. The window shell

Turn ImGui's decoration off, zero its spacing, give it a fixed size, and draw the panel yourself. The window isn't
`NoMove`, so dragging an empty spot moves it. Controls stop that because their invisible buttons take the press.

```lua
local FLAGS = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoScrollbar,
    ImGuiWindowFlags_NoScrollWithMouse, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoBackground,
    ImGuiWindowFlags_NoNavInputs) -- NoNavInputs: Tab is the game's (target cycling), not ImGui's

local function draw_window(state)
    local io = imgui.GetIO()
    local m, pw, ph = S(6), S(651), S(540)
    imgui.SetNextWindowPos({ io.DisplaySize.x / 2, io.DisplaySize.y / 2 }, ImGuiCond_FirstUseEver, { 0.5, 0.5 })
    imgui.SetNextWindowSize({ pw + m * 2, ph + m * 2 }, ImGuiCond_Always)

    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0, 0, 0, 0 })
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 })
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, rgba('#3A4158'))
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, rgba('#4A5270'))
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, rgba(P.accent_lo))
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildBorderSize, 0)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, S(6))
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, S(3))

    local open = { true }
    if imgui.Begin('SK Settings###sk3settings', open, FLAGS) then
        local wx, wy = imgui.GetWindowPos()
        local x, y = wx + m, wy + m
        local dl = imgui.GetWindowDrawList()
        fill(dl, x - 1, y, pw + 2, ph + 2, '#000000', S(6), 0, 0.35)                 -- shadow
        fill(dl, x, y, pw, ph, P.bg, S(5))                                         -- page
        fill(dl, x, y, S(159), ph, P.side, S(5), ImDrawFlags_RoundCornersLeft)     -- sidebar
        vline(dl, x + S(159), y, y + ph, P.border)
        outline(dl, x, y, pw, ph, P.border, S(5))
        -- draw_sidebar(...), draw_page(...): pcall them (ui/README.md: an error must still reach End)
    end
    imgui.End()
    imgui.PopStyleVar(6)
    imgui.PopStyleColor(5)
end
```

The scrolling parts (the nav list, the page's sections) are each a `BeginChild` placed with `SetCursorScreenPos`.
Inside a child, `GetWindowDrawList()` returns the child's list, which ImGui clips to the child. See
[Pitfalls](#10-pitfalls) for what scrolling needs.

---

## 7. Building blocks

```lua
local function fill(dl, x, y, w, h, color, radius, corners, alpha)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(color, alpha), radius or 0, corners or 0)
end

local function outline(dl, x, y, w, h, color, radius, corners, thickness, alpha)
    dl:AddRect({ x, y }, { x + w, y + h }, u32(color, alpha), radius or 0, corners or 0, thickness or 1)
end

local function circle(dl, cx, cy, r, color, alpha)
    dl:AddCircleFilled({ cx, cy }, r, u32(color, alpha), 0)
end

-- the input half of every control: an invisible button over its box
local function hit(id, x, y, w, h)
    imgui.SetCursorScreenPos({ x, y })
    imgui.InvisibleButton(id, { math.max(1, w), math.max(1, h) })
    return imgui.IsItemHovered(), imgui.IsItemClicked(0), imgui.IsItemActive()
end

-- easing: each id moves towards its target a share of the way each frame. Call frame() once per frame first.
local anim, last, dt = {}, nil, 0

local function frame(now)
    dt = last and math.max(0, math.min(0.1, now - last)) or 0 -- capped, so a hitch doesn't make things jump
    last = now
end

local function ease(id, target, speed)
    local v = anim[id]
    if v == nil then
        v = target -- a new control starts where it should be, without animating in
    else
        v = v + (target - v) * math.min(1, dt * (speed or 18))
        if math.abs(v - target) < 0.003 then v = target end
    end
    anim[id] = v
    return v
end
```

`corners = 0` with a radius rounds all four corners. Pass `ImDrawFlags_RoundCornersLeft` and similar for some.

Tooltips use `BeginTooltip` + `TextUnformatted`, so a `%` in the text is drawn as written. They get their own padding
(9, 6), rounding 4, a 1 px border, text at 14, and `PushTextWrapPos(S(300))`. Settings rows show theirs only after
the mouse has rested **0.4 s** on the label half of the row, so moving across the window doesn't flash tooltips.

---

## 8. Controls

Every control takes `(id, position, value, enabled, ...)` and returns `(value, changed)`. It is centred vertically on
`cy`. Disabled means everything is drawn at alpha 0.4 and no input is taken.

### Switch: 32 × 17

A pill-shaped track whose colour blends `off` → `accent`, a round `knob` 2 px inside it that slides across, and a
white wash at 0.08 on hover.

```lua
local function switch(id, x, cy, on, enabled)
    local w, h = S(32), S(17)
    local y = cy - h / 2
    local hovered, clicked = hit(id, x, y, w, h)
    local changed = clicked and enabled
    if changed then on = not on end
    local t, a = ease(id, on and 1 or 0), enabled and 1 or 0.4
    local dl = imgui.GetWindowDrawList()
    fill(dl, x, y, w, h, mix(P.off, P.accent, t), h / 2, 0, a)
    if hovered and enabled then fill(dl, x, y, w, h, '#FFFFFF', h / 2, 0, 0.08) end
    local r = (h - S(4)) / 2
    circle(dl, x + S(2) + r + (w - S(4) - r * 2) * t, cy, r, P.knob, a)
    return on, changed
end
```

### Slider: 200 wide in all

From left to right: a reset icon (20), the track, an 8 px gap, the value (48, right-aligned).

- **Track:** 4 px tall and fully rounded; `off` underneath, `accent` up to the value (at least 4 px wide).
- **Knob:** a circle with radius 5.5 that eases to 6.5 on hover. Colour: `knob`, tinted halfway to `accent2` on hover,
  `accent2` while held.
- **Value:** `text2` at 14. Hovering it shows a `hover` box (radius 3); a click opens a small window to type an exact
  number.
- **Reset icon:** Font Awesome reset at size 9. `dim` when the value differs from the default, `faint` when it doesn't,
  eased to `text` on hover.
- **Tick marks** (optional): a 3 px line under the track at each named value, its name in `faint` under that; a name
  that would overlap the previous one is skipped.
- **Hit box:** from 4 px before the track to 8 px past its end, 18 tall, so the knob is still grabbable at either end.

```lua
local held = nil -- the slider being dragged

-- returns value, changed (each frame it moves), released (the drag ended: write the setting now)
local function slider(id, x, cy, value, min, max, step, enabled, shown)
    local dl = imgui.GetWindowDrawList()
    local a = enabled and 1 or 0.4
    local value_w = S(48)
    local track_w = S(200) - S(20) - value_w - S(8)
    x = x + S(20) -- after the reset icon (drawn by the caller, or here)
    local hovered, _, active = hit(id, x - S(4), cy - S(9), track_w + S(12), S(18))
    local changed, released = false, false
    if active and enabled then
        local mx = imgui.GetMousePos()
        local v = min + (max - min) * math.max(0, math.min(1, (mx - x) / track_w))
        if step and step > 0 then v = min + math.floor((v - min) / step + 0.5) * step end
        v = math.max(min, math.min(max, v))
        changed, value, held = v ~= value, v, id
    elseif held == id then
        held, released = nil, true
    end
    local f, th = math.max(0, math.min(1, (value - min) / (max - min))), S(4)
    fill(dl, x, cy - th / 2, track_w, th, P.off, th / 2, 0, a)
    if f > 0 then fill(dl, x, cy - th / 2, math.max(th, track_w * f), th, P.accent, th / 2, 0, a) end
    local lit = ease(id .. '.lit', (hovered or active) and enabled and 1 or 0)
    circle(dl, x + track_w * f, cy, S(5.5) + S(1) * lit, active and P.accent2 or mix(P.knob, P.accent2, lit * 0.5), a)
    local tw = measure(shown, fonts.text, SMALL + 0.5)
    text_mid(dl, x + track_w + S(8) + value_w - tw, cy, shown, P.text2, fonts.text, SMALL + 0.5, a)
    return value, changed, released
end
```

### Segments: "All | Characters | Environment"

A sunken `well` box (radius 4, `well_edge` outline). Inside it, each word gets 10 px either side, segments sit 1 px
apart, and the row is inset 2 px from the box. The selected segment fades in a `seg` fill (radius 3), and its text eases
`dim` → `text`. An unselected segment under the mouse gets a white wash at 0.05. Height is the text size + 7 (22 at
15 px).

```lua
local function segments_width(labels, size)
    local widths, total = {}, S(4)
    for i, label in ipairs(labels) do
        widths[i] = measure(label, fonts.text, size) + S(20)
        total = total + widths[i] + (i > 1 and S(1) or 0)
    end
    return total, widths
end

-- index: the one chosen (0 for none, e.g. a quality strip at "custom")
local function segments(id, x, cy, labels, index, enabled, size)
    size = size or BODY - 1
    local dl, a = imgui.GetWindowDrawList(), enabled and 1 or 0.4
    local h = S(size + 7)
    local y = cy - h / 2
    local total, widths = segments_width(labels, size)
    fill(dl, x, y, total, h, P.well, S(4), 0, a)
    outline(dl, x, y, total, h, P.well_edge, S(4), 0, 1, a)
    local changed, at = false, x + S(2)
    for i, label in ipairs(labels) do
        local sid, sy, sh = id .. '.' .. i, y + S(2), h - S(4)
        local hovered, clicked = hit(sid, at, sy, widths[i], sh)
        if clicked and enabled and index ~= i then index, changed = i, true end
        local t = ease(sid, index == i and 1 or 0)
        if t > 0.01 then fill(dl, at, sy, widths[i], sh, P.seg, S(3), 0, t * a) end
        if hovered and enabled and index ~= i then fill(dl, at, sy, widths[i], sh, '#FFFFFF', S(3), 0, 0.05) end
        local tw = measure(label, fonts.text, size)
        text_mid(dl, at + math.floor((widths[i] - tw) / 2), cy, label, mix(P.dim, P.text, t), fonts.text, size, a)
        at = at + widths[i] + S(1)
    end
    return index, changed
end
```

A choice shows as segments when its labels fit the row. When they don't, it falls back to a dropdown.

### Dropdown: "2048 ▾"

The box is drawn by hand and the list is a real ImGui popup.

- **Box:** 24 high, fits its text (6 px padding, then a 7.5 px chevron), right-aligned, capped at the width allowed.
  Fill `well`; outline `well_edge`, or `accent_lo` when hovered or open. Text in `text2` at 14. The chevron is `dim`
  and points up while the list is open.
- **List:** `OpenPopup` on click. It is placed 2 px under the box with its right edge aligned to the box's. It is at
  least as wide as the space allowed, at most 360 px wide and 420 px tall. Options are `Selectable` in the popup style
  below, at 15.5 px, and `{ sep = true }` entries draw a `Separator`.

```lua
local function dropdown(id, right, cy, max_w, options, value, enabled)
    local dl, a = imgui.GetWindowDrawList(), enabled and 1 or 0.4
    local h, pad = S(24), S(6)
    local shown = tostring(value)
    for _, o in ipairs(options) do if o[1] == value then shown = o[2] end end
    local bw = math.min(max_w, measure(shown, fonts.text, SMALL + 0.5) + pad * 2 + S(14))
    local bx, y = right - bw, cy - h / 2
    local hovered, clicked = hit(id, bx, y, bw, h)
    local list = id .. '.list'
    local open = imgui.IsPopupOpen(list)
    fill(dl, bx, y, bw, h, P.well, S(4), 0, a)
    outline(dl, bx, y, bw, h, (hovered or open) and enabled and P.accent_lo or P.well_edge, S(4), 0, 1, a)
    text_mid(dl, bx + pad, cy, shown, P.text2, fonts.text, SMALL + 0.5, a)
    icon_centred(dl, bx + bw - pad - S(4), cy - S(1), open and 'up' or 'down', P.dim, 7.5, a)
    if clicked and enabled then imgui.OpenPopup(list) end
    local changed = false
    imgui.SetNextWindowPos({ right - max_w, y + h + S(2) })
    imgui.SetNextWindowSizeConstraints({ max_w, 0 }, { math.max(max_w, S(360)), S(420) })
    push_popup_style()
    if imgui.BeginPopup(list) then
        imgui.PushFont(fonts.text, S(BODY - 0.5))
        for i, o in ipairs(options) do
            if o.sep then
                imgui.Separator()
            elseif imgui.Selectable(o[2] .. '##' .. i, o[1] == value) then
                if o[1] ~= value then value, changed = o[1], true end
                imgui.CloseCurrentPopup()
            end
        end
        imgui.PopFont()
        imgui.EndPopup()
    end
    pop_popup_style()
    return value, changed
end
```

**Popup style**, pushed around every popup and side window (the main window's zero padding would otherwise apply to
them):

| Colours | Style vars |
|---|---|
| `PopupBg`, `WindowBg` `#0F1118`; `Border` `border` | `WindowPadding` (10, 8); `WindowRounding` 5; `WindowBorderSize` 1 |
| `Header` `accent_bg`; `HeaderHovered` `hover`; `HeaderActive` `accent_lo` | `PopupRounding` 5; `PopupBorderSize` 1 |
| `Separator` `line`; `Text` `text`; `FrameBg` (all three states) `well` | `FramePadding` (8, 4); `FrameRounding` 4; `ItemSpacing` (8, 8) |

### Buttons: 22 high, radius 4

Width is the text width + 18 (+14 with an icon). Text and icon are centred, the icon at size 10 and the text at 14.
Hover eases at speed 22. While held, a black wash at 0.15 covers the button.

| Kind | Fill | Outline | Text |
|---|---|---|---|
| `ghost` (default) | `well` → `hover` | `well_edge` → `accent_lo` | `text2` → `text` |
| `accent` | `accent` → 60% of the way to `accent2` | white at 0.22 | `ink` |
| `secondary` | `seg` → `#3D4463` | white at 0.12 | `text` |
| `soft` / `neutral` / `danger` | `well` with 10% of the tint (20% hovered) | the tint at 0.45 (0.70 hovered) | the tint, lightened 35% on hover |

The tints are `accent` for soft, `text2` for neutral and `rose` for danger. A destructive button asks twice: the first
press turns its text red and changes it to a confirm prompt for 5 seconds.

### Small parts

| Part | Spec |
|---|---|
| Icon button (×, ↺, ≡) | 20 × 20 hit box; the icon eases from `dim` (or a given colour) to `text` (or a given hover colour). The × that closes the window hovers to `rose` |
| Pill ("DX12") | 15 high, fully rounded, text + 10 wide; `accent_bg` fill, `accent_lo` outline, `accent2` semibold text at 11.5 |
| Keycap ("Ctrl") | 18 high, radius 3, text + 10 wide, `seg` fill, semibold text at 13 |
| Meter | A slider track without a knob: 4 px tall, `off` then `accent` (or a given colour), label right-aligned in `dim` |
| Stepper ("‹ value ›") | 110 × 24 `well` box; 24 px end caps with chevrons at size 8 (`dim` → `text`), white wash at 0.07 on the hovered end |
| Colour swatch | A 16 px rounded square of the colour with a white outline at 0.15 (`accent` at 0.8 when hovered or its picker is open), then its hex in `text2`. Opens `ColorPicker3` in a window beside the main one |

---

## 9. Page patterns

### Section heading ("Shadows")

1. Chevron (down, or right when folded), size 7, in the gutter at x + 12. `faint`, `text` on hover.
2. Title at x + 24 in bold italic, 21, `white`. Hovering it eases the colour 35% towards `accent2`. When the section's
   switch is off, the title is 50% of the way to `dim`.
3. An optional tag after it, in `dim` at 13 ("7 of 31 loaded").
4. A hairline in `line` from 8 px after the title to the reset icon.
5. A reset icon (size 9, `faint` → `text`, with a "Reset Shadows to the defaults" tooltip) 24 px before the switch.
6. The section's switch at the right edge, 10 px after the line.

A click anywhere on the chevron or the title folds the section. Folded sections are saved per page and heading, so
they stay folded the next time.

### Settings row

- Label at x + 24, regular 16, `text`. It goes `dim` when disabled.
- A setting that needs a restart gets an amber semibold `*` 5 px after its label.
- The control is right-aligned at `right`.
- The hover band (see Measurements) covers the whole row.
- A dependent sub-option is drawn with a bent arrow in `faint` from the row above, its label indented 22 px and drawn
  in `dim` at 0.6.

### Sub-panel heading

Inside a section: its title in capitals, semibold italic, 13.5, letter-spaced, in `teal` (`rose` for a danger
group). After the title come an optional `dim` tag and a line in the title colour at 0.8, then an optional switch at
the end. When that switch is off, the rows under it draw at 0.55 but can still be changed.

### Boxes inside a page

| Box | Spec |
|---|---|
| Status box (read-only values) | `well` at 0.7, `line` outline, radius 5; 8 px wider than the rows on each side; a run of status rows shares one box |
| Warning | `rose` fill at 0.10 and outline at 0.30, radius 4, a 3 px `rose` bar down its left; text 15 in `text`, 20 px lines |

### Sidebar

- **Search box:** a 30 px box with two drop shadows below it (black at 0.3 offset 2, black at 0.18 offset 4). Fill
  `search`, outline `search_edge`, radius 6. A real `InputTextWithHint('##search', 'Search', ...)` sits inside it with
  its frame colours set fully transparent, so only the hand-drawn box shows. While there's text, a `rose` × at the
  right end clears it. Typing searches every page and shows the matching sections, each titled "Page ›".
- **Group label:** capitals, semibold 12, `faint` (`dim` on hover), with a chevron at the right; a click folds the
  group.
- **Item:** 25 high; icon (size 10.5) at x + 24, name at x + 37 in `white` 16.5. The active item eases in an
  `accent_bg` fill at 0.9 and a 2 px `accent` bar on the left edge, and its icon eases `faint` → `accent`. A hovered
  item gets `hover` at 0.7.
- **Sub-tabs** (a page's sections, listed under it when open): 22 high on a 1 px `line` rail running down from the
  icon. The one shown gets a 3 px `accent` pill on the rail and a `white` name; the others are `dim` (`text` on
  hover). A click shows just that section.
- **Tools** at the bottom, under a `border` line: a "TOOLS" group label, then items styled like nav items.
- **Hiding:** the ≡ in the title bar hides the sidebar. Its width eases (speed 14) and the window narrows with it. Its
  contents are drawn only while it is fully open.

---

## 10. Pitfalls

What vana had to work around. Each of these is easy to get wrong.

- **A child window doesn't know how tall drawn content is.** After drawing a scroll child's content, put the cursor at
  the bottom and add an item: `imgui.SetCursorScreenPos({ cx, bottom }); imgui.Dummy({ 1, S(6) })`. Without it, the
  child doesn't scroll.
- **Skip what's scrolled out of view.** Rows outside the child's visible top and bottom return their height without
  drawing. Long pages stay cheap that way. A row that sets state for the rows after it (a sub-panel heading's switch)
  still has to run.
- **Hit boxes must cover the whole drawing.** Where the knob overhangs the track and no invisible button covers it, a
  press there falls through to the window background and drags the window instead.
- **Hold a dragged value locally.** If the setting is written only when the drag ends, keep the dragged value in local
  state and draw that while held. Otherwise the knob snaps back to the saved value every frame.
- **ids:** every invisible button needs a unique `##id`. ImGui reads ids as C strings, so a NUL byte in a generated id
  cuts it short and two controls clash.
- **`NoNavInputs` on every window and child**, or Tab moves ImGui's focus instead of cycling game targets.
- **Fonts can't be used in the frame they're added.** Skip drawing that frame.
- **Clear the measuring cache when the scale changes**, or text is laid out with the old sizes.
- **Push the popup style around popups.** The main window's zero padding and spacing would apply to them otherwise.
- **`dt` is capped at 0.1 s.** After a hitch, animations take one big step instead of jumping to the end.
- **Text with `%`:** draw-list `AddText` and `TextUnformatted` draw it as written. In Ashita, `Text`, `TextColored`
  and `SetTooltip` treat it as a printf format (see `ui/README.md`).

---

## 11. States and motion

| State | Look |
|---|---|
| Disabled | Whole control at alpha 0.4; no input |
| Needs something missing (e.g. DX12) | Alpha 0.5 plus a pill naming the requirement |
| Parent switched off | Rows at 0.55; still editable |
| Hover | `hover` band behind rows and nav items; on controls, a white wash at 0.05 (segments), 0.07 (stepper) or 0.08 (switch) |
| Pressed | Black at 0.15 over a button; the slider knob turns `accent2` |
| Selected | `seg` fill (segments), `accent_bg` + `accent` bar (nav) |

| Animation | Ease speed |
|---|---|
| Default (switch knob, segment fill, slider knob) | 18 |
| Nav item becoming active | 20 |
| Hover tint on buttons and icons | 22 |
| Sidebar opening and closing | 14 |

The speed is how much of the remaining distance is covered per second (`dt × speed`). At 18 a change is about 95%
done in a sixth of a second.

---

## In Sidekick3

`ui/kit.lua` is this doc in code: the palette (§2, plus `hp`, `mp` and `tp` for the HUD's bars: the rose and amber
nearest the old mockup's red and yellow, and the teal), `S` and the scale (§3), the fonts and text helpers (§4), the shapes, easing and hit
boxes (§7), and the controls (§8: switch, slider, segments, drop-down, button, chip, text field). `ui/window.lua` draws
everything with it:

- **SK Settings** is the vana window. The sidebar lists a page per group of sections, Profiles and UI / Log at its foot
  under SETUP, with a teal dot (or a ring when every switch is off) where vana has an icon. Each page is a scrolling
  child, each section a heading (§9) with its switch, each setting a row: label at the left, control at the right.
  Spell and ability rows put their name, readiness and switch on one line and their pick, target chips and modifier
  chips on the lines under it.
- **The HUD** keeps its layout and the sizes set under UI / Log, in the palette: a dark rounded panel, sunken rounded
  bars whose fill eases to each new value, round buttons filled in the accent while on, and the next action's label as
  a pill (amber running, grey stopped). Each card is HP over MP over TP, your pet's card under yours; the TP bar is
  three sunken parts of 1000 TP, each solid once full and at half alpha while it fills (as Floaties draws it). Its
  text keeps a dark halo, as it sits on bars and, with the panel see-through, on the game. The panel, its frame, the
  title and the close mark fade out until the mouse is over the window (Tracker's chrome) and fade back to the
  Background opacity while it is. The bars do not fade. The close mark is Tracker's X, rose under the pointer.
  Section headers are Tracker's small capitals: Segoe semibold italic, letter-spaced.

What differs from vana:

| vana | Sidekick3 |
|---|---|
| Font Awesome icons | Icons drawn in shapes (`kit.icon`: close, play, stop, cog, the chevrons), so no font has to carry them |
| A typed number in a window beside the main one | A popup by the value (`kit.slider`) |
| Raw ImGui numbers | The constants `require('imgui')` defines, each listed in `.luacheckrc`'s `read_globals` |
| ImGui 1.92 only | 1.81 too (Ashita 4.16): ImGui's own font at every size, measured by scaling `CalcTextSize`; `BeginChild`'s border bool; 1.81's corner flags. `IMGUI_VERSION_NUM` decides |
| Sizes of §5 | `ui/window.lua`'s constants: a 390-wide page, fixed for every job, rows of 30 |
| Search, sub-tabs, presets, section resets | Not drawn: Sidekick3's pages are short, and its view has no defaults to reset to |

**Tests:** the fake ImGui in `tests/ui_window_test.lua` reports every popup open (so drop-down lists draw and their
choices can be clicked), steps `kit.clock` a second a frame (every eased value lands at once) and drags a slider
through `kit.dragged`.

**Fonts and reloads:** the Segoe UI faces are added once per addon load, and the binding has no call to take a font
back out of ImGui's atlas, so each `/addon reload sidekick3` adds them again: memory only, until the game restarts.
