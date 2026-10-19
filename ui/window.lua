--[[
    The standard Sidekick3 UI, and the reference: it uses only the `view` and
    `act` every UI is given (ui/README.md), so ui/custom.lua can replace it.
    ImGui only; it reads no game state and decides nothing.

    Two windows. Sidekick3 is a heads-up display: the party's HP and MP bars on a
    grey panel (the alliance's other parties as thin HP rows under them), the
    rest of the window transparent, with an arrow at whoever the next action is for. Your own card's
    HP bar carries the run icon and the cog, which opens SK Settings, every setting under collapsing headers.
    So does the card of a player who is another Sidekick session on this PC: its icons
    start and stop that session and open its own SK Settings, drawn here from its view.
    The widget (`ui.widget`, `/sk3 widget`) is a third, v2's floating one: the profile
    loaded and the job, then Start/Stop, the status, Settings and Track for your target.
    It shows with the HUD closed too (`view.ui.open` false), as v2's did.

    Ashita's binding (as v2 found it): widget values are one-element tables
    ({ true }, { 75 }), and Text, TextColored and SetTooltip take a printf
    format, so any '%' shown goes through text() / tip(), which double it.
    Draw-list AddText takes its text as is.
]]--

local imgui = require('imgui')

local window = {}

local function rgb(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

local GREEN = { 0.6, 1.0, 0.6, 1.0 }
local GREY = { 0.55, 0.55, 0.55, 1.0 }
local CHIP_OFF = { { 0.3, 0.3, 0.3, 1.0 }, { 0.4, 0.4, 0.4, 1.0 }, { 0.5, 0.5, 0.5, 1.0 } }
local CHIP_EMPTY = { { 0.2, 0.2, 0.2, 1.0 }, { 0.2, 0.2, 0.2, 1.0 }, { 0.2, 0.2, 0.2, 1.0 } }

-- The HUD, to the user's mockup.
local WHITE, BLACK = rgb(0xFF, 0xFF, 0xFF), rgb(0x00, 0x00, 0x00)
local RED = rgb(0xF0, 0x7A, 0x7A)      -- text under the critical HP line or the Recover MP line
local AWAY = rgb(0xA0, 0xA0, 0xA0)     -- text for a member in another zone
local EMPTY = rgb(0x2E, 0x2E, 0x2E)
local HP_TOP, HP_BOTTOM = rgb(0xFF, 0x90, 0x90), rgb(0xE3, 0x74, 0x76)
local MP_TOP, MP_BOTTOM = rgb(0xD1, 0xD1, 0x8E), rgb(0xBA, 0xBF, 0x74)
local PANEL = { 0x60, 0x60, 0x60 }     -- at view.ui.opacity
-- The arrow: running, it points at what is going; stopped, at what it would do.
local LIVE = { fill = rgb(0xFF, 0xE5, 0x45), bevel = rgb(0xFF, 0xFB, 0x5B), edge = rgb(0x8E, 0x78, 0x1F), text = WHITE }
local WOULD = { fill = rgb(0xB4, 0xB4, 0xB4), bevel = rgb(0xD2, 0xD2, 0xD2), edge = rgb(0x5A, 0x5A, 0x5A), text = rgb(0xD0, 0xD0, 0xD0) }

local B, PAD = 2, 4                    -- bar border, panel padding (sides and bottom), in pixels
local TITLE = 'Sidekick3'
local AROUND = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }
local SEGMENTS = 32                    -- an icon's circles

local WIDGET_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_AlwaysAutoResize
    + ImGuiWindowFlags_NoScrollbar

local HUD_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoBringToFrontOnFocus

-- { label, key, min, max, help } for view.ui: sizes in pixels, the opacity in %.
local UI_SLIDERS = {
    { 'HP bar width', 'hp_width', 80, 600, 'Pixels.' },
    { 'HP bar height', 'hp_height', 10, 120, 'Pixels.' },
    { 'MP bar width', 'mp_width', 80, 600, 'Pixels.' },
    { 'MP bar height', 'mp_height', 4, 80, 'Pixels.' },
    { 'Name font size', 'name_size', 8, 64, 'Pixels.' },
    { 'Text font size', 'text_size', 8, 48, 'Pixels: the title, the tags, the alliance\'s names and the arrow\'s label; '
        .. 'the icons follow it, as far as the HP bar fits them.' },
    { 'Spacing', 'gap', 0, 40, 'Pixels between members.' },
    { 'Background opacity', 'opacity', 0, 100, '% of the grey panel behind the bars.' },
}

local SETTING_WIDTH, PICK_WIDTH, CHIP_WIDTH, RUNE_WIDTH, MANEUVER_WIDTH = 160, 170, 28, 130, 90
local JOINED = { party = '  (in your party)', alliance = '  (in your alliance)' }  -- a tracked player's note

local act                    -- this frame's actions (another session's, while drawing its SK Settings)
local settings_open = false  -- SK Settings shown; this session only
local hud_open = true        -- last frame's view.ui.open: closing the HUD (/sk3) closes SK Settings with it
local profile_names = {}     -- per SK Settings window ('' for yours, else the session's name), this session only:
                             -- { typed = { name }, shown }, the name filled in again when the profile loaded changes

local function esc(s) return (tostring(s):gsub('%%', '%%%%')) end

-- A profile's name in a label: '##' would end what it shows, and so would a '#'
-- left just before the '###' of the id, so one at the end is kept apart.
local function shown_name(name)
    local s = name:gsub('#+', '#')
    return s:sub(-1) == '#' and s .. ' ' or s
end

local function text(s, color)
    if color then imgui.TextColored(color, esc(s)) else imgui.Text(esc(s)) end
end

-- Tooltip for the last item.
local function tip(s)
    if s and s ~= '' and imgui.IsItemHovered() then imgui.SetTooltip(esc(s)) end
end

-- The closers of the ImGui scopes open now, innermost last. A Lua error raised
-- inside a table, combo or popup leaves it open, which ImGui asserts on at End:
-- the window unwinds them all before it ends. Item widths pushed are tracked
-- too, so every push is popped whatever happens.
local scopes = {}

-- Track a scope its opener reports `opened`; returns `opened`.
local function begin(opened, close)
    if opened then scopes[#scopes + 1] = close end
    return opened
end

local function finish() table.remove(scopes)() end

local function unwind()
    while scopes[1] do finish() end
end

-- A button in `colors` (nil: the default), its text grey when `dim`; whether it was clicked.
local function button(label, colors, dim, size)
    if colors then
        imgui.PushStyleColor(ImGuiCol_Button, colors[1])
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, colors[2])
        imgui.PushStyleColor(ImGuiCol_ButtonActive, colors[3])
    end
    if dim then imgui.PushStyleColor(ImGuiCol_Text, GREY) end
    local clicked
    if size then clicked = imgui.Button(label, size) else clicked = imgui.Button(label) end
    local pushed = (colors and 3 or 0) + (dim and 1 or 0)
    if pushed > 0 then imgui.PopStyleColor(pushed) end
    return clicked
end

-- HUD drawing ------------------------------------------------------------------------

local function u32(c) return imgui.GetColorU32(c) end

-- `s` as drawn at `size` pixels: CalcTextSize measures at the UI font's size.
local function measure(s, size)
    local w, h = imgui.CalcTextSize(s)
    local k = size / imgui.GetFontSize()
    return w * k, h * k
end

-- AddText draws a fill and nothing else: the outline is the string stamped in
-- black a pixel out each way, underneath. Whole pixels, so it doesn't shimmer.
local function outlined(dl, size, x, y, color, s)
    local font, black = imgui.GetFont(), u32(BLACK)
    x, y = math.floor(x), math.floor(y)
    for _, o in ipairs(AROUND) do dl:AddText(font, size, { x + o[1], y + o[2] }, black, s) end
    dl:AddText(font, size, { x, y }, u32(color), s)
end

-- A filled triangle, wound clockwise on screen as ImGui's anti-aliasing expects.
local function tri(dl, a, b, c, col)
    if (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) < 0 then b, c = c, b end
    dl:AddTriangleFilled(a, b, c, col)
end

-- A bar's fill at (x, y), w by h, `pct` of it in the top-to-bottom gradient,
-- inside a black border B wide.
local function bar(dl, x, y, w, h, pct, top, bottom)
    dl:AddRectFilled({ x - B, y - B }, { x + w + B, y + h + B }, u32(BLACK))
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(EMPTY))
    local fill = math.floor(w * math.min(math.max(pct, 0), 100) / 100 + 0.5)
    if fill > 0 then
        top, bottom = u32(top), u32(bottom)
        dl:AddRectFilledMultiColor({ x, y }, { x + fill, y + h }, top, top, bottom, bottom)
    end
end

-- Icons: MDI's geometry in a 24-unit box at (x, y), k pixels a unit. `cut` is
-- the panel colour, for the shapes cut out of them. ---------------------------------

local function at(x, y, k, px, py) return { x + px * k, y + py * k } end

local function disc(dl, x, y, k, col) dl:AddCircleFilled(at(x, y, k, 12, 12), 10 * k, col, SEGMENTS) end

local function close_icon(dl, x, y, k, col, cut)
    disc(dl, x, y, k, col)
    dl:AddLine(at(x, y, k, 8, 8), at(x, y, k, 16, 16), cut, 2 * k)
    dl:AddLine(at(x, y, k, 16, 8), at(x, y, k, 8, 16), cut, 2 * k)
end

local function play_icon(dl, x, y, k, col, cut)
    disc(dl, x, y, k, col)
    tri(dl, at(x, y, k, 10, 7.5), at(x, y, k, 16, 12), at(x, y, k, 10, 16.5), cut)
end

local function stop_icon(dl, x, y, k, col, cut)
    disc(dl, x, y, k, col)
    dl:AddRectFilled(at(x, y, k, 9, 9), at(x, y, k, 15, 15), cut)
end

-- Eight teeth, one pointing straight up: trapezoids from radius 6 to 10.2.
local function cog_icon(dl, x, y, k, col, cut)
    local cx, cy = x + 12 * k, y + 12 * k
    dl:AddCircleFilled({ cx, cy }, 7.5 * k, col, SEGMENTS)
    for i = 0, 7 do
        local a = i * math.pi / 4
        local dx, dy = math.sin(a), -math.cos(a)  -- outward
        local function p(r, w) return { cx + (dx * r - dy * w) * k, cy + (dy * r + dx * w) * k } end
        local b1, b2, t1, t2 = p(6, -2.3), p(6, 2.3), p(10.2, -1.9), p(10.2, 1.9)
        tri(dl, b1, b2, t2, col)
        tri(dl, b1, t2, t1, col)
    end
    dl:AddCircleFilled({ cx, cy }, 3.5 * k, cut, SEGMENTS)
end

-- An icon button s pixels square at (x, y): black, white while hovered. Also
-- returns whether it's hovered.
local function icon(id, x, y, s, draw, help, cut)
    imgui.SetCursorScreenPos({ x, y })
    local clicked = imgui.InvisibleButton(id, { s, s })
    local hovered = imgui.IsItemHovered()
    tip(help)
    draw(imgui.GetWindowDrawList(), x, y, s / 24, u32(hovered and WHITE or BLACK), cut)
    return clicked, hovered
end

-- HUD -----------------------------------------------------------------------------

-- The title's tooltip: the job, what automation is doing, and what may hold it up.
local function status_tip(view)
    local s = view.status
    local lines = { view.job, ('%s: %s'):format(s.state, s.text) }
    if view.profiles.active then lines[1] = ('%s  (profile %s)'):format(view.job, view.profiles.active) end
    if s.dim then lines[#lines + 1] = ('(%s)'):format(s.dim) end
    if #view.flags > 0 then lines[#lines + 1] = '[' .. table.concat(view.flags, '] [') .. ']' end
    for _, e in ipairs({ { 'Target', view.bt }, { 'Pet', view.pet } }) do
        if e[2] then lines[#lines + 1] = ('%s: %s  %d%%  %s'):format(e[1], e[2].name, e[2].hpp, e[2].dist) end
    end
    return table.concat(lines, '\n')
end

local function member_tip(p)
    local notes = {}
    if p.kind == 'trust' or p.kind == 'tracked' or p.kind == 'alliance' then notes[#notes + 1] = p.kind end
    if p.job then notes[#notes + 1] = p.job end
    if not (p.alive or p.away) then notes[#notes + 1] = 'KO' end
    if p.away then notes[#notes + 1] = 'away' end
    local line = ('HP %d%%'):format(p.hpp) .. (p.uses_mp and ('  MP %d%%'):format(p.mpp) or '')
    if p.dist ~= '' and not p.away then line = line .. '  ' .. p.dist end
    local lines = { #notes > 0 and ('%s (%s)'):format(p.name, table.concat(notes, ', ')) or p.name, line }
    if p.buffs_all ~= '' then lines[#lines + 1] = p.buffs_all end
    return table.concat(lines, '\n')
end

-- "Sidekick3" in bold black, then close (an icon s pixels square); the hover areas.
local function title_row(dl, view, ts, x0, y0, pw, th, s, cut)
    local font, black = imgui.GetFont(), u32(BLACK)
    local _, h = measure(TITLE, ts)
    local ty = math.floor(y0 + (th - h) / 2)
    dl:AddText(font, ts, { x0 + 8, ty }, black, TITLE)
    dl:AddText(font, ts, { x0 + 9, ty }, black, TITLE)  -- bold: stamped twice

    local iy = y0 + math.floor((th - s) / 2)
    local ix = x0 + pw - 6 - s  -- the icon's left
    imgui.SetCursorScreenPos({ x0, y0 })
    imgui.Dummy({ ix - x0, th })
    tip(status_tip(view))

    if icon('##sk3_close', ix, iy, s, close_icon, 'Close (/sk3 opens it again)', cut) then
        act.close()
        settings_open = false
    end
end

-- Run and settings at the top right of the HP bar of your card, or of another
-- session's, s pixels square (at most what the bar fits), each cut in the bar's
-- colour under it. Returns whether one is hovered, so the card's own tooltip gives way.
local function card_icons(view, ui, p, x, y, s)
    local fx, hp_top = x + PAD + B, y + B
    s = math.min(s, ui.hp_height - 4, math.floor((ui.hp_width - 8) / 2))
    local filled = fx + math.floor(ui.hp_width * math.min(math.max(p.hpp, 0), 100) / 100 + 0.5)
    local iy, cog_x = hp_top + 2, fx + ui.hp_width - 2 - s
    local run_x = cog_x - 4 - s
    local function cut(ix) return u32(ix + s / 2 < filled and HP_TOP or EMPTY) end

    local remote = p.session
    local running = remote and remote.running or not remote and view.status.running
    local id, whose = remote and ('_' .. remote.name) or '', remote and (remote.name .. '\'s ') or ''
    local clicked, over_run = icon('##sk3_run' .. id, run_x, iy, s, running and stop_icon or play_icon,
        (running and 'Stop ' or 'Start ') .. whose .. 'automation', cut(run_x))
    if clicked then (remote and act.remote(remote.name) or act).run(not running) end
    local cog, over_cog = icon('##sk3_cog' .. id, cog_x, iy, s, cog_icon, remote and ('Settings for ' .. remote.name) or 'Settings',
        cut(cog_x))
    if cog and remote then act.watch(remote.name, not remote.open)
    elseif cog then settings_open = not settings_open end
    return over_run or over_cog
end

-- A member's card at (x, y): the HP bar over the MP bar, sharing a border, the
-- % of each only in its tooltip. A tracked player's MP can't be read: their bar stays empty.
local function card(dl, ui, p, x, y)
    local fx, hp_top = x + PAD + B, y + B
    local mp_top = hp_top + ui.hp_height + B
    bar(dl, fx, hp_top, ui.hp_width, ui.hp_height, p.hpp, HP_TOP, HP_BOTTOM)
    bar(dl, fx, mp_top, ui.mp_width, ui.mp_height, p.mpp, MP_TOP, MP_BOTTOM)

    local hp_color = p.away and AWAY or p.hp == 'critical' and RED or WHITE
    local mp_color = p.away and AWAY or p.mp == 'low' and RED or WHITE
    local _, nh = measure(p.name, ui.name_size)
    outlined(dl, ui.name_size, fx + 4, hp_top + ui.hp_height - nh, hp_color, p.name)
    local _, th = measure(p.tag, ui.text_size)
    outlined(dl, ui.text_size, fx + 4, mp_top + (ui.mp_height - th) / 2, mp_color, p.tag)
end

-- An alliance member's row, its bar's top at `top`: a thin HP bar (the MP bar's
-- height) with the tag and name on it, its HP % only in its tooltip.
local function ally_row(dl, ui, p, x, top)
    local fx, ts = x + PAD + B, ui.text_size
    bar(dl, fx, top, ui.hp_width, ui.mp_height, p.hpp, HP_TOP, HP_BOTTOM)
    local color = p.away and AWAY or p.hp == 'critical' and RED or WHITE
    local label = p.tag .. ' ' .. p.name
    local _, h = measure(label, ts)
    outlined(dl, ts, fx + 4, top + (ui.mp_height - h) / 2, color, label)
end

-- The arrow left of the label, its tip just right of the panel at `cy`. On the
-- background list: it sits outside the window without widening it, as a
-- transparent window area would block the game's clicks.
local function arrow(ptr, ts, right, cy)
    local dl = imgui.GetBackgroundDrawList()
    local c = ptr.live and LIVE or WOULD
    local aw = ts * 1.75
    local ah = aw * 0.6
    local point, top, bottom = { right + 1, cy }, { right + 1 + aw, cy - ah }, { right + 1 + aw, cy + ah }
    tri(dl, point, top, bottom, u32(c.fill))
    local mx = right + 1 + aw * 2 / 3  -- the bevel: the same shape, smaller, about its centre
    local function inner(q) return { mx + (q[1] - mx) * 0.55, cy + (q[2] - cy) * 0.55 } end
    tri(dl, inner(point), inner(top), inner(bottom), u32(c.bevel))
    dl:AddTriangle(point, top, bottom, u32(c.edge), 1)
    local _, h = measure(ptr.text, ts)
    outlined(dl, ts, right + 1 + aw + 4, cy - h / 2, c.text, ptr.text)
end

-- view.ui's sizes, each held to its slider's range: nothing checks a value edited
-- by hand or set by a custom UI, and ImGui asserts on a zero-size button.
local function hud_sizes(ui)
    local out = {}
    for _, l in ipairs(UI_SLIDERS) do
        out[l[2]] = math.min(math.max(math.floor(tonumber(ui[l[2]]) or l[3]), l[3]), l[4])
    end
    return out
end

local function draw_hud(view)
    local ui = hud_sizes(view.ui)
    local dl = imgui.GetWindowDrawList()
    local x0, y0 = imgui.GetCursorScreenPos()
    local th, s = math.floor(ui.text_size * 1.7), math.floor(ui.text_size * 1.25)
    local pw = math.max(2 * PAD + 2 * B + math.max(ui.hp_width, ui.mp_width),
                        math.ceil(8 + measure(TITLE, ui.text_size) + 8 + s + 6))  -- the title row fits
    local ch = B + ui.hp_height + B + ui.mp_height + B
    local n = #view.party
    -- Under the cards, the alliance's rows: B0-B5, then C0-C5, each party after a
    -- gap. Rows share their borders, as a card's two bars do; `rows` holds each bar's top.
    local below, rows, last = th + n * ch + math.max(n - 1, 0) * ui.gap, {}, nil
    for j, p in ipairs(view.alliance) do
        local party = p.tag:sub(1, 1)
        if party ~= last then below = below + ui.gap + B end
        rows[j], last = below, party
        below = below + ui.mp_height + B
    end
    local ph = below + PAD

    dl:AddRectFilled({ x0, y0 }, { x0 + pw, y0 + ph }, u32(rgb(PANEL[1], PANEL[2], PANEL[3], ui.opacity / 100)))
    title_row(dl, view, ui.text_size, x0, y0, pw, th, s, u32(rgb(PANEL[1], PANEL[2], PANEL[3])))
    for i, p in ipairs(view.party) do
        local y = y0 + th + (i - 1) * (ch + ui.gap)
        card(dl, ui, p, x0, y)
        local on_icon = (p.kind == 'self' or p.session) and card_icons(view, ui, p, x0, y, s)
        imgui.SetCursorScreenPos({ x0 + PAD, y })
        imgui.Dummy({ pw - 2 * PAD, ch })
        if not on_icon then tip(member_tip(p)) end
        if view.pointer and view.pointer.member == i then arrow(view.pointer, ui.text_size, x0 + pw, y + ch / 2) end
    end
    for j, p in ipairs(view.alliance) do
        local top = y0 + rows[j]
        ally_row(dl, ui, p, x0, top)
        imgui.SetCursorScreenPos({ x0 + PAD, top - B })
        imgui.Dummy({ pw - 2 * PAD, ui.mp_height + B })
        tip(member_tip(p))
        if view.pointer and view.pointer.ally == j then arrow(view.pointer, ui.text_size, x0 + pw, top + ui.mp_height / 2) end
    end
    imgui.SetCursorScreenPos({ x0, y0 + ph - PAD })
    imgui.Dummy({ pw, PAD })  -- the bottom padding, and the panel's full width, for the auto-size
end

-- The widget ------------------------------------------------------------------------

-- The state alone, so the widget keeps its width and Track its place: the rest,
-- what it does or why it waits, is the tooltip, as the HUD title's.
local function short_status(view)
    local s = view.status
    if not s.running then return 'Stopped', GREY end
    if view.afk.asleep then return 'Asleep', GREY end
    return 'Running', s.dim and GREY or GREEN
end

-- Every profile, Default first, as Selectables: a click loads one. A name is drawn
-- over a blank row, not as its label: ImGui would cut a name at '##' and take an id from its '###'.
local function profile_list(p, id, default_help)
    if imgui.Selectable('Default##' .. id .. '_default', p.active == nil) then act.profile(nil) end
    tip(default_help)
    for i, name in ipairs(p.names) do
        local x = imgui.GetCursorPosX()
        if imgui.Selectable('##' .. id .. '_' .. i, name == p.active) then act.profile(name) end
        imgui.SameLine(x)
        text(name)
    end
end

local TRACK_HELP = 'Heal, clear, raise and buff them too, with what reaches outside the party. This session only.'

-- The profile loaded as a button (a click lists them to load), then the job;
-- Start/Stop, the status, Settings, then Track for your target.
local function draw_widget(view)
    local p = view.profiles
    if imgui.Button((p.active and shown_name(p.active) or 'Default') .. '###sk3_widget_profile') then imgui.OpenPopup('##sk3_widget_profiles') end
    tip('Load a profile. SK Settings saves them.')
    if begin(imgui.BeginPopup('##sk3_widget_profiles'), imgui.EndPopup) then
        profile_list(p, 'sk3_widget_profile')
        finish()
    end
    imgui.SameLine()
    imgui.AlignTextToFramePadding()  -- else it sits at the top of the button row
    text(view.job)

    local s = view.status
    if imgui.Button((s.running and 'Stop' or 'Start') .. '###sk3_widget_run') then act.run(not s.running) end
    tip((s.running and 'Stop' or 'Start') .. ' automation')
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    local line, color = short_status(view)
    text(line, color)
    tip(status_tip(view))
    imgui.SameLine()
    if imgui.Button('Settings##sk3_widget_settings') then settings_open = not settings_open end
    tip('Open or close SK Settings')
    local t = view.track.target
    if t then
        imgui.SameLine()
        if imgui.Button(('Track %s###sk3_widget_track'):format(t)) then act.track(t) end
        tip(TRACK_HELP)
    end
end

-- SK Settings controls --------------------------------------------------------------

-- The widget id of setting `path`: 'heal.danger' -> '##sk3_heal_danger'.
local function id_of(path) return '##sk3_' .. path:gsub('%.', '_') end

-- Sliders write as they move; Sidekick saves once let go.
local function slider(label, path, value, min, max, help)
    local v = { value }
    imgui.PushItemWidth(SETTING_WIDTH)
    begin(true, imgui.PopItemWidth)
    if imgui.SliderInt(label .. id_of(path), v, min, max) then act.set(path, v[1]) end
    finish()
    tip(help)
end

local function checkbox(label, on, set, help)
    local v = { on }
    if imgui.Checkbox(label, v) then set(v[1]) end
    tip(help)
end

-- A checkbox for setting `path`.
local function toggle(label, path, on, help)
    checkbox(label .. id_of(path), on, function (v) act.set(path, v) end, help)
end

-- A combo for setting `path`: None ('') unless `o.required`, then `choices`
-- ({ name, label }), each tipped with o.tip(choice) when given. A pick no longer
-- among them (one the job lacks) says so, unless `o.free`: a name typed in chat
-- or of someone not here yet shows as it is. `o.width` defaults to SETTING_WIDTH.
local function combo(label, path, current, choices, o)
    o = o or {}
    local id = id_of(path)
    local shown = current == '' and 'None' or o.free and current or current .. ' (not available)'
    for _, c in ipairs(choices) do
        if c.name == current then shown = c.label end
    end
    imgui.PushItemWidth(o.width or SETTING_WIDTH)
    begin(true, imgui.PopItemWidth)
    if begin(imgui.BeginCombo(label .. id, shown), imgui.EndCombo) then
        if not o.required and imgui.Selectable('None' .. id .. '_none', current == '') then act.set(path, '') end
        for _, c in ipairs(choices) do
            if imgui.Selectable(c.label .. id .. '_' .. c.name, c.name == current) then act.set(path, c.name) end
            if o.tip then tip(o.tip(c)) end
        end
        finish()
    end
    finish()
end

-- Names as combo choices.
local function plain(names)
    local out = {}
    for i, name in ipairs(names) do out[i] = { name = name, label = name } end
    return out
end

local WIDE = PICK_WIDTH + SETTING_WIDTH / 2  -- a combo of spell names

-- SK Settings bodies ---------------------------------------------------------------

local HEAL_LINES = {
    { 'Danger under', 'danger', 'Over this HP %, heal with the most HP for the MP or TP. Under it, heal fastest, and wait for a heal nearly ready.' },
    { 'Critical under', 'critical', 'Under this HP %, boost the heal first (Divine Seal) or save them (Martyr).' },
}

-- Who healing looks after: unticked members are never healed for their own sake.
-- Each of the alliance's other parties starts a line.
local function heal_members(h)
    if #h.members == 0 then return end
    text('Heal:')
    for _, m in ipairs(h.members) do
        if not m.wrap then imgui.SameLine() end
        checkbox(m.name .. '##sk3_heal_' .. m.name, m.healed, function () act.skip(m.name, m.healed) end,
            'Untick to never heal them for their own sake; an area heal may still land on them.')
    end
end

local function draw_heal_settings(view)
    local h = view.heal
    for _, l in ipairs(HEAL_LINES) do slider(l[1], 'heal.' .. l[2], h[l[2]], 1, 99, l[3]) end
    combo('Focus', 'heal.focus', h.focus, plain(h.focus_names), { free = true })
    tip('Heal this member first, on its own lines.')
    for _, l in ipairs(HEAL_LINES) do
        local key = 'focus_' .. l[2]
        slider('Focus ' .. l[1]:lower(), 'heal.' .. key, h[key], 1, 99, 'For the focus member: ' .. l[3])
    end
    slider('Cure potency +', 'heal.cure_potency', h.cure_potency, 0, 50, 'Cure potency % from gear, until a cure has been seen healing.')
    slider('Waltz potency +', 'heal.waltz_potency', h.waltz_potency, 0, 50, 'Waltz potency % from gear, until a waltz has been seen healing.')
    slider('Regen potency +', 'heal.regen_potency', h.regen_potency, 0, 30, 'HP per Regen tick from gear.')
    toggle('Heal the alliance', 'heal.alliance', h.alliance,
        'Heal the alliance\'s other parties too, with heals that reach outside your party. Raising, waking, '
        .. 'removal and buffs look after them whatever this says, and the focus member is always healed.')
    if h.stratagems then
        toggle('Keep a stratagem for healing', 'heal.reserve', h.reserve,
            'Buff rows never spend the last stratagem charge, so healing has one for Accession or Rapture.')
    end
    heal_members(h)
    imgui.Separator()
end

local function draw_recover_settings(view)
    local r = view.recover
    slider('MP under', 'recover.mp', r.mp, 1, 99, 'Recover MP under this MP % (yours; a member\'s for Devotion).')
    slider('TP under', 'recover.tp', r.tp, 0, 3000, 'In combat, get TP back under this.')
    if r.spends_tp then
        slider('Spend TP from', 'recover.min_tp', r.min_tp, 0, 3000, 'Chivalry turns all your TP into MP: only from this much.')
    end
    imgui.Separator()
end

local function draw_pet_settings(view)
    slider('Pet HP under', 'pet.heal', view.pet_heal, 1, 99, 'Heal your pet under this HP %.')
    imgui.Separator()
end

local function draw_follow(view)
    local f = view.follow
    combo('Leader', 'follow.target', f.target, plain(f.names), { free = true })
    tip('Who to follow; resting stands up when they leave too.')
    slider('Follow past', 'follow.distance', f.distance, 1, 15, 'Yalms.')
end

local function draw_rest(view)
    local r = view.rest
    slider('Rest after', 'rest.delay', r.delay, 1, 20, 'Seconds of nothing to do.')
    slider('Stand past', 'rest.distance', r.distance, 1, 15, 'Yalms from the leader.')
end

local function draw_afk(view)
    local a = view.afk
    slider('Sleep after', 'afk.minutes', a.minutes, 1, 60, 'Minutes with no one in your party moving and no combat.')
    if a.asleep then text('Asleep: move to wake.', GREY)
    elseif a.left then text(('Sleeps in %d min without movement or combat.'):format(math.ceil(a.left / 60)), GREY) end
end

local function draw_buff_settings(view)
    local b = view.buff
    toggle('Hold area buffs for the group', 'buff.hold_aoe', b.hold_aoe,
        'Hold an area buff spell (Protectra, Barfira, songs) while a player in your party who lacks it is out of its '
        .. 'reach, so nobody is left out. Trusts and members in another zone never hold it.')
    if b.hold_aoe then
        toggle('Ask them to gather', 'buff.gather', b.gather,
            'While one is held that someone near you lacks too, say "Gather together for <spell>" in party chat, '
                .. 'at most every 5 seconds.')
    end
    if b.shadows then
        toggle('Cast Utsusemi at one shadow', 'buff.one_shadow', b.one_shadow,
            'Recast Utsusemi while its last shadow is up, not only once it is gone. For Ichi, which cannot replace '
                .. 'Ni\'s shadows, that shadow is cancelled a second into the cast, so the new ones land.')
    end
    imgui.Separator()
end

local RISKS = {
    lowest = 'Lowest: banks lucky, and never doubles once a die could bust (6 or more).',
    medium = 'Medium: banks lucky, chases it while it is one die away, and doubles off unlucky up to 8.',
    highest = 'Highest: 11 or nothing. Rolls past lucky, and doubles at 6-10 while Fold is ready to undo a Bust; '
        .. 'without Fold, plays as Medium.',
}

local function capital(s) return (s:gsub('^%l', string.upper)) end

local function draw_rolls(view)
    local r = view.roll
    local function lucky(c) return ('Lucky %d, unlucky %d.'):format(c.lucky, c.unlucky) end
    combo('Roll 1', 'roll.first', r.first, r.choices, { width = WIDE, tip = lucky })
    if r.two then
        combo('Roll 2', 'roll.second', r.second, r.choices, { width = WIDE, tip = lucky })
        if r.second ~= '' and r.second == r.first then text('Roll 2 is Roll 1: one roll kept up', GREY) end
    else
        text('Roll 2: Corsair main job only', GREY)
    end
    local risks = {}
    for i, risk in ipairs(r.risks) do risks[i] = { name = risk, label = capital(risk) } end
    combo('Risk', 'roll.risk', r.risk, risks, { required = true, tip = function (c) return RISKS[c.name] end })
    tip('How far Double-Up chases a total. Every risk doubles at 5 or under (Lowest and Medium bank a lucky '
        .. 'there), never at 11, and turns 10 into 11 with Snake Eye. '
        .. 'Fold clears a Bust whenever it is ready.')
    local l = r.last
    if l then
        local word = l.bust and ' (Bust)' or l.total == l.lucky and ' (lucky)' or l.total == 11 and ' (11)'
            or l.total == l.unlucky and ' (unlucky)' or ''
        text(('Last: %s %d%s'):format(l.name, l.total, word))
    end
end

-- A set's combos (view.song.sets[i], view.rune.sets[i]), one per slot of `n`, each
-- in a table column and tipped with `help`; `o` as combo's.
local function slot_combos(section, set, n, choices, o, help)
    for i = 1, n do
        imgui.TableNextColumn()
        combo('', ('%s.%s_%d'):format(section, set.key, i), set.picks[i], choices, o)
        tip(help)
    end
end

local SONG_HELP = {
    area = 'Sung as they are, on you and everyone in your party near you, whenever someone there lacks one. '
        .. 'A member with songs of their own picked keeps only the slots those leave.',
}

-- BRD: a line per target, Area first, then each party slot that is filled or has a
-- pick; a combo per song slot. A slot with no one in it says so.
local function draw_songs(view)
    local m = view.song
    if not begin(imgui.BeginTable('##sk3_songs', 2 + m.slots, ImGuiTableFlags_SizingFixedFit), imgui.EndTable) then return end
    for _, set in ipairs(m.sets) do
        local picked = false
        for i = 1, m.slots do picked = picked or set.picks[i] ~= '' end
        if set.key == 'area' or set.present or picked then
            imgui.TableNextRow()
            imgui.TableNextColumn()
            local dim = set.key ~= 'area' and not (set.present and m.pianissimo)
            text(set.label, dim and GREY or nil)
            tip(SONG_HELP[set.key] or ('Sung on %s alone, through Pianissimo, whenever they lack one.')
                :format(set.name or 'whoever is in this party slot'))
            slot_combos('song', set, m.slots, m.choices, { width = WIDE })
            imgui.TableNextColumn()
            if set.key ~= 'area' then text(set.name or 'no one', GREY) end
        end
    end
    finish()
    if m.pianissimo then
        text('Pianissimo: ' .. m.avail, m.ready and GREEN or GREY)
    else
        text('Songs on one member need Pianissimo (Bard 20)', GREY)
    end
    tip('Two songs of one kind (Victory and Advancing March) stand side by side; a song picked twice is one. '
        .. 'While an area song is owed, the songs on one member wait: it would push them out.')
    if m.pianissimo then
        toggle('Pianissimo fast casting', 'song.fast', m.fast,
            'Fire Pianissimo before an area song too, for its shorter cast, and cancel it a second into the cast '
                .. 'so the song still lands on everyone near you. None is fired while Nightingale is up (its casts are '
                .. 'short already); with Pianissimo on recast the area song goes without it. A Pianissimo already up '
                .. 'goes to the next area song, or to a member\'s song while that area song can\'t go yet.')
    end
    if m.timed then
        slider('Song Duration', 'song.duration', m.duration, 0, 300,
            'Seconds: sing each song again this long after it landed, before it wears (0: only once it\'s gone). '
            .. 'Set it just under your songs\' real duration, gear included; doubled for a song sung under Troubadour. '
            .. 'While Nightingale and Troubadour are both up, every song sung without Troubadour is sung again.')
    end
end

local function draw_geo(view)
    local g = view.geo
    slider('Recall past', 'geo.distance', g.distance, 3, 30,
        'Yalms: Full Circle the luopan once who it is on is further than this from it, so it goes down again.')
    slider('Keep after combat', 'geo.linger', g.linger, 1, 20,
        'Seconds a debuff luopan waits once combat is over before Full Circle recalls it: a new battle target in that time keeps it.')
    combo('Entrust to', 'geo.entrust', g.entrust, plain(g.names), { free = true })
    tip('With Entrust on, put the Indi- spell picked on this member (within 20 yalms).')
    combo('Entrust spell', 'geo.entrust_spell', g.entrust_spell, plain(g.indi), { width = WIDE, free = true })
    tip('The Indi- spell Entrust puts on that member whenever they lack its aura.')
    imgui.Separator()
end

-- What a set's slots show of each rune.
local SHOWS = { element = 'Each rune by the element it adds to your attacks.',
                resist = 'Each rune by the element it resists.', ailments = 'Each rune by the ailments it defends against.' }

local function rune_tip(c)
    local r = c.rune
    return ('%s: adds %s, resists %s, against %s.'):format(r.name, r.element, r.resist, r.ailments)
end

-- A line per set: Idle, then each ward with its switch; a combo per rune slot (each
-- rune by what the set shows of it), then whether it's ready.
local function draw_runes(view)
    local r = view.rune
    if not begin(imgui.BeginTable('##sk3_runes', 2 + r.slots, ImGuiTableFlags_SizingFixedFit), imgui.EndTable) then return end
    for _, set in ipairs(r.sets) do
        imgui.TableNextRow()
        imgui.TableNextColumn()
        if set.ward then
            checkbox(set.label .. '##sk3_rune_' .. set.key, set.on, function (on) act.row(set.ward, on) end,
                ('Once %s is ready, its runes take the slots, then it fires in combat.'):format(set.ward))
        else
            text(set.label)
            tip('The runes kept up the rest of the time.')
        end
        local choices = {}
        for i, rune in ipairs(r.runes) do choices[i] = { name = rune.name, label = rune[set.shows], rune = rune } end
        slot_combos('rune', set, r.slots, choices, { width = RUNE_WIDTH, tip = rune_tip }, SHOWS[set.shows])
        imgui.TableNextColumn()
        if set.ward then text(set.avail, set.ready and GREEN or GREY) end
    end
    finish()
    imgui.Separator()
end

-- PUP: a combo per maneuver slot, by element (None for ''), then whether they can go.
local function draw_maneuvers(view)
    local m = view.maneuver
    if not begin(imgui.BeginTable('##sk3_maneuvers', 1 + #m.picks, ImGuiTableFlags_SizingFixedFit), imgui.EndTable) then return end
    imgui.TableNextRow()
    for i, current in ipairs(m.picks) do
        imgui.TableNextColumn()
        combo('', 'maneuver.slot_' .. i, current, m.choices, { width = MANEUVER_WIDTH })
        tip('The same element in two slots keeps two up.')
    end
    imgui.TableNextColumn()
    text(m.avail, m.ready and GREEN or GREY)
    finish()
end

-- Each tracked player with its Untrack button (one who joined your party or
-- alliance too), then Track for your target.
local function draw_track(view)
    for _, list in ipairs({ view.party, view.alliance }) do
        for _, p in ipairs(list) do
            if p.tracked then
                if imgui.Button('Untrack##sk3_untrack_' .. p.name) then act.untrack(p.name) end
                imgui.SameLine()
                local note = JOINED[p.kind] or p.job and ('  ' .. p.job) or ''
                if p.shared and not JOINED[p.kind] then note = note .. '  (from ' .. p.shared .. ')' end
                text(('%s %s'):format(p.tag, p.name) .. note, p.away and GREY or nil)
                local where = p.away and (p.kind == 'tracked' and 'Out of range.' or 'In another zone.') or nil
                local from = p.shared and ('Tracked while %s\'s session lists them; Untrack keeps them off until tracked again.'):format(p.shared)
                tip(where and from and (where .. '\n' .. from) or where or from)
            end
        end
    end
    local t = view.track.target
    if t then
        if imgui.Button(('Track %s##sk3_track'):format(t)) then act.track(t) end
        tip(TRACK_HELP)
    else
        text(view.session and ('Target a player outside the alliance in %s\'s game to track them there.'):format(view.session)
            or 'Target a player outside your alliance to track them, or /sk3 track Name.', GREY)
    end
end

-- The name to save under, Save / Save as / New / Delete, then every profile:
-- a click loads it (Default, the working copy as it was before one was loaded).
local function draw_profiles(view)
    local p = view.profiles
    local active = p.active or ''
    local state = profile_names[view.session or '']
    if not state then state = { typed = { '' } }; profile_names[view.session or ''] = state end
    local profile_name = state.typed
    if active ~= state.shown then profile_name[1], state.shown = active, active end
    imgui.PushItemWidth(SETTING_WIDTH)
    begin(true, imgui.PopItemWidth)
    imgui.InputText('Name##sk3_profile_name', profile_name, 64)
    finish()
    tip('A name for Save or Save as. Each job pair has its own profiles.')
    local typed = profile_name[1]:match('^%s*(.-)%s*$')
    if imgui.Button('Save##sk3_profile_save') then act.save_profile(typed) end
    tip('Save the settings as they are now under this name. With a profile loaded and the name changed, '
        .. 'rename that profile instead. Never over another profile: Save as replaces one.')
    imgui.SameLine()
    if imgui.Button('Save as##sk3_profile_save_as') then act.save_profile(typed, true) end
    tip('Save the settings as they are now under this name, over any profile already named so.')
    imgui.SameLine()
    if imgui.Button('New##sk3_profile_new') then
        act.new_profile()
        profile_name[1] = ''
    end
    tip('Every setting back to its default, on Default. Saved profiles are kept.')
    if p.active then
        imgui.SameLine()
        if imgui.Button('Delete##sk3_profile_delete') then act.delete_profile(p.active) end
        tip(('Delete %s, and go back to Default.'):format(p.active))
    end
    local taken = false
    for _, name in ipairs(p.names) do taken = taken or name == typed and typed ~= p.active end
    if taken then text(('%s exists: Save as replaces it.'):format(typed), GREY) end
    profile_list(p, 'sk3_profile', 'The working copy: your settings as they were before a profile was loaded.')
    text('Changes save to the settings in use; to a profile only with Save.', GREY)
end

local function draw_recent(view)
    if #view.recent == 0 then text('Nothing sent yet.', GREY) end
    for _, r in ipairs(view.recent) do
        text(('%3ds'):format(r.age), GREY)
        imgui.SameLine()
        text(r.text)
        imgui.SameLine()
        text(r.why, GREY)
    end
end

-- Another session's shows only what it sent: its HUD and log are its own.
local function draw_ui(view)
    if view.session then return draw_recent(view) end
    for _, l in ipairs(UI_SLIDERS) do slider(l[1], 'ui.' .. l[2], view.ui[l[2]], l[3], l[4], l[5]) end
    toggle('Lock position', 'ui.locked', view.ui.locked == true,
        'Keep the HUD and the widget where they are: dragging them no longer moves them.')
    toggle('Widget', 'ui.widget', view.ui.widget == true,
        'A small window of its own: the profile loaded (a click loads another) and your job, then Start/Stop, '
        .. 'the status, Settings, and Track for your target. Also /sk3 widget.')
    imgui.Separator()
    checkbox('Action log##sk3_log', view.log, act.log, 'Print each action to chat as it is sent.')
    draw_recent(view)
    imgui.Separator()
    toggle('Japanese client', 'japanese', view.japanese, 'Send spell, ability and item names in Japanese, on every job.')
end

-- Rows ------------------------------------------------------------------------------

local function pick_combo(r, id)
    imgui.PushItemWidth(PICK_WIDTH)
    begin(true, imgui.PopItemWidth)
    if begin(imgui.BeginCombo('##pick_' .. id, r.choice), imgui.EndCombo) then
        for _, c in ipairs(r.choices) do
            if imgui.Selectable(c.label, c.name == r.pick) then act.pick(r.key, c.name) end
        end
        finish()
    end
    finish()
end

-- ME, P1-P5, T1...; B0-B5 and C0-C5 each on a line of their own. An empty
-- slot can't be picked, but a picked one can still be cleared.
local function target_chips(r, id)
    for i, t in ipairs(r.targets) do
        if i > 1 and not t.wrap then imgui.SameLine(0, 2) end
        local disabled = not t.present and not t.on
        local colors = disabled and CHIP_EMPTY or not t.on and CHIP_OFF or nil
        if button(t.label .. '##' .. id .. t.slot, colors, disabled, { CHIP_WIDTH, 0 }) and not disabled then
            act.target(r.key, t.slot, not t.on)
        end
        tip(t.name or 'empty slot')
    end
end

-- Modifiers fired before the row's spell (Pen, Cel, Acc, Emb...), then Hold: wait for them.
local function mod_chips(r, id)
    local any = false
    for i, m in ipairs(r.mods) do
        if i > 1 then imgui.SameLine(0, 2) end
        if button(m.label .. '##' .. id .. '_mod_' .. m.name, not m.on and CHIP_OFF or nil, false, { CHIP_WIDTH, 0 }) then
            act.mod(r.key, m.name, not m.on)
        end
        tip(m.note and ('%s first: %s'):format(m.name, m.note) or m.name)
        any = any or m.on
    end
    -- With none on, it waits for nothing: dimmed, but kept and still clickable.
    imgui.SameLine(0, 2)
    if button('Hold##' .. id .. '_hold', not any and CHIP_EMPTY or not r.hold and CHIP_OFF or nil, not any) then
        act.hold(r.key, not r.hold)
    end
    tip('Wait while a modifier picked here can\'t go with the spell (on recast, too few charges, the wrong Arts, '
        .. 'Accession unable to spread it, or short of MP for it); otherwise the spell goes without it.'
        .. (any and '' or '\nNo modifier is on here: it waits for nothing.'))
end

-- One row per settings key: [x] Name (note) | pick | ME P1-P5 | Pen Acc | ready or why not.
-- The pick, target and modifier columns are there only when some row in this table has them.
local function draw_rows(table_id, section_id, rows)
    local choices, targets, mods = false, false, false
    for _, r in ipairs(rows) do
        choices = choices or r.choices ~= nil
        targets = targets or r.targets ~= nil
        mods = mods or r.mods ~= nil
    end
    local columns = 2 + (choices and 1 or 0) + (targets and 1 or 0) + (mods and 1 or 0)
    if not begin(imgui.BeginTable(table_id, columns, ImGuiTableFlags_SizingFixedFit), imgui.EndTable) then return end
    for _, r in ipairs(rows) do
        local id = section_id .. '_' .. r.key
        imgui.TableNextRow()
        imgui.TableNextColumn()
        -- An item shows how many you carry, ninjutsu their tools; ### keeps its id while the count changes.
        local n = r.count or r.tools
        checkbox(n and ('%s (%d)###%s'):format(r.label, n, id) or r.label .. '##' .. id, r.on,
            function (on) act.row(r.key, on) end)
        if choices then
            imgui.TableNextColumn()
            if r.choices then pick_combo(r, id) end
        end
        if targets then
            imgui.TableNextColumn()
            if r.targets then target_chips(r, id) end
        end
        if mods then
            imgui.TableNextColumn()
            if r.mods then mod_chips(r, id) end
        end
        imgui.TableNextColumn()
        text(r.avail, r.ready and GREEN or GREY)
        tip(r.action)
    end
    finish()
end

-- Spells and abilities, then items (rows with a count) in a table of their own.
local function section_rows(s)
    local acts, items = {}, {}
    for _, r in ipairs(s.rows) do table.insert(r.count and items or acts, r) end
    if #acts > 0 then draw_rows('##sk3_rows_' .. s.id, s.id, acts) end
    if #items > 0 then
        text('Items')
        draw_rows('##sk3_rows_' .. s.id .. '_items', s.id, items)
    end
end

-- SK Settings -----------------------------------------------------------------------

local SWITCH_HELP = {
    follow = 'Follow the leader once they are further away than the distance.',
    heal = 'Heal the party with the rows that are on.',
    revive = 'Raise fallen members with the rows that are on.',
    wake = 'Wake a sleeping member with a cure or waltz that is on under Heal; an area one for two or more.',
    remove = 'Remove debuffs with the rows that are on.',
    buff = 'Keep the buffs that are on up on their targets.',
    roll = 'Keep the rolls picked up, and Double-Up the last one by the risk picked. Held for the group with '
        .. 'Hold area buffs, as an area buff.',
    song = 'Keep the songs picked up: the area ones on everyone near you, then each member\'s own through Pianissimo. '
        .. 'Held for the group with Hold area buffs, as an area buff.',
    geo = 'Keep a luopan down: the Geo row\'s on its target, or the Geo debuff\'s on your battle target in combat. '
        .. 'Full Circle recalls it when its target leaves it, and a debuff\'s after combat.',
    rune = 'Keep the runes picked up: a ward\'s set once it is ready, then the ward in combat; the Idle set the rest '
        .. 'of the time. Lunge and Swipe are yours: the runes go back up after.',
    pet = 'Look after your pet, and send it in, with the rows that are on.',
    maneuver = 'Keep the maneuvers picked up on you while your automaton is out (none under Overload).',
    recover = 'Get MP and TP back with the rows that are on.',
    rest = 'Rest for MP out of combat once nothing else has happened for a while; stand at full MP.',
    afk = 'While running, pause automation once no one in your party has moved and there has been no combat for '
        .. 'a while; your own movement wakes it (a pull doesn\'t), and so does the leader leaving with Follow on. '
        .. 'Nothing is stopped or saved.',
}

local BODIES = {
    follow = draw_follow, heal = draw_heal_settings, recover = draw_recover_settings, buff = draw_buff_settings,
    roll = draw_rolls, song = draw_songs, geo = draw_geo, rune = draw_runes, maneuver = draw_maneuvers,
    pet = draw_pet_settings, rest = draw_rest, afk = draw_afk, track = draw_track, ui = draw_ui, profile = draw_profiles,
}

-- Its switch, its settings, then its rows.
local function draw_section(view, s)
    if s.on ~= nil then
        checkbox(s.title .. '##sk3_on_' .. s.id, s.on, function (on) act.section(s.id, on) end, SWITCH_HELP[s.id])
    end
    if BODIES[s.id] then BODIES[s.id](view) end
    if s.rows then section_rows(s) end
end

-- A collapsing header per `header`, in the order the sections come, closed at
-- first so the window starts small. One whose switches are all off says so.
local function draw_settings(view)
    local headers, of = {}, {}
    for _, s in ipairs(view.sections) do
        if not of[s.header] then of[s.header] = {}; headers[#headers + 1] = s.header end
        table.insert(of[s.header], s)
    end
    for _, h in ipairs(headers) do
        local switches, on = false, false
        for _, s in ipairs(of[h]) do
            if s.on ~= nil then switches, on = true, on or s.on end
        end
        local note = switches and not on and ' (off)' or ''
        if h == 'Profiles' and view.profiles.active then note = ': ' .. shown_name(view.profiles.active) end
        if imgui.CollapsingHeader(h .. note .. '###sk3_' .. h) then
            for i, s in ipairs(of[h]) do
                if i > 1 then imgui.Separator() end
                draw_section(view, s)
            end
        end
    end
end

-- Another session's SK Settings, from the view it published, its changes sent to
-- it; until its first view comes, a line saying so.
local function draw_remote(r)
    if r.other then
        return text(('%s runs another version of Sidekick3: /addon reload sidekick3 there.'):format(r.name), GREY)
    end
    if not r.view then return text(('Waiting for %s\'s session...'):format(r.name), GREY) end
    text(('%s  %s'):format(r.view.job, r.view.status.state), r.view.status.running and GREEN or GREY)
    tip('Changes here are sent to that session, which applies them within a second or so.')
    imgui.Separator()
    draw_settings(r.view)
end

-- Windows ---------------------------------------------------------------------------

-- One window: Begin (then `vars` style vars pushed for it popped), body(arg) under
-- pcall while it's shown, End. Returns the error the body raised, its scopes closed.
local function draw_window(title, open, flags, body, arg, vars)
    local ok, err = true, nil
    local shown = imgui.Begin(title, open, flags)
    if vars then imgui.PopStyleVar(vars) end
    if shown then ok, err = pcall(body, arg) end
    if not ok then unwind() end
    imgui.End()  -- ImGui keeps where it was dragged, in imgui.ini
    return err
end

local function locked(view) return view.ui.locked and ImGuiWindowFlags_NoMove or 0 end

local function hud(view)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    return draw_window('Sidekick3', true, HUD_FLAGS + locked(view), draw_hud, view, 2)
end

local function settings_window(view)
    local open = { true }
    local err = draw_window('SK Settings', open, ImGuiWindowFlags_AlwaysAutoResize, draw_settings, view)
    if not open[1] then settings_open = false end
    return err
end

local function remote_window(r)
    local open, mine = { true }, act
    act = mine.remote(r.name)
    local err = draw_window(('SK Settings: %s###sk3_settings_%s'):format(r.name, r.name), open,
        ImGuiWindowFlags_AlwaysAutoResize, draw_remote, r)
    act = mine
    if err or not open[1] then act.watch(r.name, false) end  -- a view that won't draw isn't drawn again
    return err
end

-- One frame. A Lua error raised while drawing is raised again after the windows
-- are ended, so ImGui stays balanced and Sidekick reports it.
function window.render(view, act_)
    act = act_
    local open = view.ui.open ~= false
    if hud_open and not open then settings_open = false end
    hud_open = open
    local err
    if open then err = hud(view) end
    if view.ui.widget then
        err = draw_window('SK Widget', true, WIDGET_FLAGS + locked(view), draw_widget, view) or err
    end
    if settings_open then err = settings_window(view) or err end
    if open then
        for _, r in ipairs(view.remote or {}) do err = remote_window(r) or err end
    end
    if err then error(err, 0) end
end

return window
