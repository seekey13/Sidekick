--[[
    The standard Sidekick3 UI, and the reference: it uses only the `view` and
    `act` every UI is given (ui/README.md), so ui/custom.lua can replace it.
    ImGui only; it reads no game state and decides nothing.

    Two windows. Sidekick3 is a heads-up display: the party's HP and MP bars on a
    grey panel (the alliance's other parties as thin HP rows under them), the
    rest of the window transparent, with an arrow at whoever the next action is for. Its cog opens SK Settings, every setting under
    collapsing headers.

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
    { 'Text font size', 'text_size', 8, 48, 'Pixels: the title, HP %, MP % and the arrow\'s label.' },
    { 'Spacing', 'gap', 0, 40, 'Pixels between members.' },
    { 'Background opacity', 'opacity', 0, 100, '% of the grey panel behind the bars.' },
}

local SETTING_WIDTH, PICK_WIDTH, CHIP_WIDTH = 160, 170, 28
local JOINED = { party = '  (in your party)', alliance = '  (in your alliance)' }  -- a tracked player's note

local act                    -- this frame's actions
local settings_open = false  -- SK Settings shown; this session only
local profile_name = { '' }  -- the profile name typed; this session only...
local profile_shown          -- ...filled in again when the profile loaded changes

local function esc(s) return (tostring(s):gsub('%%', '%%%%')) end

local function text(s, color)
    if color then imgui.TextColored(color, esc(s)) else imgui.Text(esc(s)) end
end

-- Tooltip for the last item.
local function tip(s)
    if s and s ~= '' and imgui.IsItemHovered() then imgui.SetTooltip(esc(s)) end
end

local function push_button(colors)
    imgui.PushStyleColor(ImGuiCol_Button, colors[1])
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, colors[2])
    imgui.PushStyleColor(ImGuiCol_ButtonActive, colors[3])
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

-- An icon button s pixels square at (x, y): black, white while hovered.
local function icon(id, x, y, s, draw, help, cut)
    imgui.SetCursorScreenPos({ x, y })
    local clicked = imgui.InvisibleButton(id, { s, s })
    local hovered = imgui.IsItemHovered()
    tip(help)
    draw(imgui.GetWindowDrawList(), x, y, s / 24, u32(hovered and WHITE or BLACK), cut)
    return clicked
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

-- "Sidekick3" in bold black, then run, settings and close (icons s pixels
-- square); the hover areas.
local function title_row(dl, view, ts, x0, y0, pw, th, s, cut)
    local font, black = imgui.GetFont(), u32(BLACK)
    local _, h = measure(TITLE, ts)
    local ty = math.floor(y0 + (th - h) / 2)
    dl:AddText(font, ts, { x0 + 8, ty }, black, TITLE)
    dl:AddText(font, ts, { x0 + 9, ty }, black, TITLE)  -- bold: stamped twice

    local iy = y0 + math.floor((th - s) / 2)
    local ix = x0 + pw - 6 - 3 * s - 2 * 4  -- the first icon's left
    imgui.SetCursorScreenPos({ x0, y0 })
    imgui.Dummy({ ix - x0, th })
    tip(status_tip(view))

    local running = view.status.running
    if icon('##sk3_run', ix, iy, s, running and stop_icon or play_icon,
            running and 'Stop automation' or 'Start automation', cut) then
        act.run(not running)
    end
    if icon('##sk3_cog', ix + s + 4, iy, s, cog_icon, 'Settings', cut) then settings_open = not settings_open end
    if icon('##sk3_close', ix + 2 * (s + 4), iy, s, close_icon, 'Close (/sk3 opens it again)', cut) then
        act.close()
        settings_open = false
    end
end

-- A member's card at (x, y): the HP bar over the MP bar, sharing a border. A
-- tracked player's MP can't be read: their bar stays empty, with no %.
local function card(dl, ui, p, x, y)
    local fx, hp_top = x + PAD + B, y + B
    local mp_top = hp_top + ui.hp_height + B
    bar(dl, fx, hp_top, ui.hp_width, ui.hp_height, p.hpp, HP_TOP, HP_BOTTOM)
    bar(dl, fx, mp_top, ui.mp_width, ui.mp_height, p.mpp, MP_TOP, MP_BOTTOM)

    local hp_color = p.away and AWAY or p.hp == 'critical' and RED or WHITE
    local mp_color = p.away and AWAY or p.mp == 'low' and RED or WHITE
    local ts = ui.text_size
    local _, nh = measure(p.name, ui.name_size)
    outlined(dl, ui.name_size, fx + 4, hp_top + ui.hp_height - nh, hp_color, p.name)
    local hp = ('%d%%'):format(p.hpp)
    outlined(dl, ts, fx + ui.hp_width - 4 - measure(hp, ts), hp_top + 1, hp_color, hp)
    local mp = ('%d%%'):format(p.mpp)
    local mw, mh = measure(mp, ts)
    local my = mp_top + (ui.mp_height - mh) / 2
    outlined(dl, ts, fx + 4, my, mp_color, p.tag)
    if p.kind ~= 'tracked' then outlined(dl, ts, fx + ui.mp_width - 4 - mw, my, mp_color, mp) end
end

-- An alliance member's row, its bar's top at `top`: a thin HP bar (the MP bar's
-- height) with the tag and name on it and the HP % at its end.
local function ally_row(dl, ui, p, x, top)
    local fx, ts = x + PAD + B, ui.text_size
    bar(dl, fx, top, ui.hp_width, ui.mp_height, p.hpp, HP_TOP, HP_BOTTOM)
    local color = p.away and AWAY or p.hp == 'critical' and RED or WHITE
    local label, hp = p.tag .. ' ' .. p.name, ('%d%%'):format(p.hpp)
    local _, h = measure(label, ts)
    local ty = top + (ui.mp_height - h) / 2
    outlined(dl, ts, fx + 4, ty, color, label)
    outlined(dl, ts, fx + ui.hp_width - 4 - measure(hp, ts), ty, color, hp)
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
                        math.ceil(8 + measure(TITLE, ui.text_size) + 8 + 3 * s + 2 * 4 + 6))  -- the title row fits
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
        imgui.SetCursorScreenPos({ x0 + PAD, y })
        imgui.Dummy({ pw - 2 * PAD, ch })
        tip(member_tip(p))
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

-- SK Settings bodies ---------------------------------------------------------------

-- Sliders write as they move; Sidekick saves once let go.
local function slider(label, path, value, min, max, help)
    local v = { value }
    imgui.PushItemWidth(SETTING_WIDTH)
    if imgui.SliderInt(label, v, min, max) then act.set(path, v[1]) end
    imgui.PopItemWidth()
    tip(help)
end

local function checkbox(label, on, set, help)
    local v = { on }
    if imgui.Checkbox(label, v) then set(v[1]) end
    tip(help)
end

-- A party member by name for setting `path`, or None ('').
local function member_combo(label, id, current, names, path, help)
    imgui.PushItemWidth(SETTING_WIDTH)
    if imgui.BeginCombo(label .. '##sk3_' .. id, current ~= '' and current or 'None') then
        if imgui.Selectable('None##sk3_' .. id .. '_none', current == '') then act.set(path, '') end
        for _, name in ipairs(names) do
            if imgui.Selectable(name .. '##sk3_' .. id .. '_' .. name, name == current) then act.set(path, name) end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    tip(help)
end

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
        local v = { m.healed }
        if imgui.Checkbox(m.name .. '##sk3_heal_' .. m.name, v) then act.skip(m.name) end
        tip('Untick to never heal them for their own sake; an area heal may still land on them.')
    end
end

local function draw_heal_settings(view)
    local h = view.heal
    for _, l in ipairs(HEAL_LINES) do
        slider(l[1] .. '##sk3_' .. l[2], 'heal.' .. l[2], h[l[2]], 1, 99, l[3])
    end
    member_combo('Focus', 'focus', h.focus, h.focus_names, 'heal.focus', 'Heal this member first, on its own lines.')
    for _, l in ipairs(HEAL_LINES) do
        local key = 'focus_' .. l[2]
        slider('Focus ' .. l[1]:lower() .. '##sk3_' .. key, 'heal.' .. key, h[key], 1, 99, 'For the focus member: ' .. l[3])
    end
    slider('Cure potency +##sk3_cure_potency', 'heal.cure_potency', h.cure_potency, 0, 50,
        'Cure potency % from gear, until a cure has been seen healing.')
    slider('Waltz potency +##sk3_waltz_potency', 'heal.waltz_potency', h.waltz_potency, 0, 50,
        'Waltz potency % from gear, until a waltz has been seen healing.')
    slider('Regen potency +##sk3_regen_potency', 'heal.regen_potency', h.regen_potency, 0, 30,
        'HP per Regen tick from gear.')
    checkbox('Heal the alliance##sk3_heal_alliance', h.alliance, function (on) act.set('heal.alliance', on) end,
        'Heal the alliance\'s other parties too, with heals that reach outside your party. Raising, waking, '
        .. 'removal and buffs look after them whatever this says, and the focus member is always healed.')
    if h.stratagems then
        checkbox('Keep a stratagem for healing##sk3_heal_reserve', h.reserve, function (on) act.set('heal.reserve', on) end,
            'Buff rows never spend the last stratagem charge, so healing has one for Accession or Rapture.')
    end
    heal_members(h)
    imgui.Separator()
end

local function draw_recover_settings(view)
    local r = view.recover
    slider('MP under##sk3_recover_mp', 'recover.mp', r.mp, 1, 99,
        'Recover MP under this MP % (yours; a member\'s for Devotion).')
    slider('TP under##sk3_recover_tp', 'recover.tp', r.tp, 0, 3000, 'In combat, get TP back under this.')
    if r.spends_tp then
        slider('Spend TP from##sk3_recover_min_tp', 'recover.min_tp', r.min_tp, 0, 3000,
            'Chivalry turns all your TP into MP: only from this much.')
    end
    imgui.Separator()
end

local function draw_pet_settings(view)
    slider('Pet HP under##sk3_pet_heal', 'pet.heal', view.pet_heal, 1, 99, 'Heal your pet under this HP %.')
    imgui.Separator()
end

local function draw_follow(view)
    local f = view.follow
    member_combo('Leader', 'follow_target', f.target, f.names, 'follow.target', 'Who to follow; resting stands up when they leave too.')
    slider('Follow past##sk3_follow_distance', 'follow.distance', f.distance, 1, 15, 'Yalms.')
end

local function draw_rest(view)
    local r = view.rest
    slider('Rest after##sk3_rest_delay', 'rest.delay', r.delay, 1, 20, 'Seconds of nothing to do.')
    slider('Stand past##sk3_rest_distance', 'rest.distance', r.distance, 1, 15, 'Yalms from the leader.')
end

local function draw_buff_settings(view)
    local b = view.buff
    checkbox('Hold area buffs for the group##sk3_hold_aoe', b.hold_aoe, function (on) act.set('buff.hold_aoe', on) end,
        'Hold an area buff spell (Protectra, Barfira, songs) while a player in your party who lacks it is out of its '
        .. 'reach, so nobody is left out. Trusts and members in another zone never hold it.')
    if b.hold_aoe then
        checkbox('Ask them to gather##sk3_gather', b.gather, function (on) act.set('buff.gather', on) end,
            'While one is held that someone near you lacks too, say "Gather together for <spell>" in party chat, '
                .. 'at most every 5 seconds.')
    end
    imgui.Separator()
end

local RISKS = {
    lowest = 'Lowest: banks lucky, and never doubles once a die could bust (6 or more).',
    medium = 'Medium: banks lucky, chases it while it is one die away, and doubles off unlucky up to 8.',
    highest = 'Highest: 11 or nothing. Rolls past lucky, and doubles at 6-10 while Fold is ready to undo a Bust; '
        .. 'without Fold, plays as Medium.',
}

-- A roll for setting `path`, or None (''). A pick the job no longer has says so.
local function roll_combo(label, id, current, choices, path)
    local shown = current ~= '' and current .. ' (not available)' or 'None'
    for _, c in ipairs(choices) do
        if c.name == current then shown = c.label end
    end
    imgui.PushItemWidth(PICK_WIDTH + SETTING_WIDTH / 2)
    if imgui.BeginCombo(label .. '##sk3_' .. id, shown) then
        if imgui.Selectable('None##sk3_' .. id .. '_none', current == '') then act.set(path, '') end
        for _, c in ipairs(choices) do
            if imgui.Selectable(c.label .. '##sk3_' .. id .. '_' .. c.name, c.name == current) then act.set(path, c.name) end
            tip(('Lucky %d, unlucky %d.'):format(c.lucky, c.unlucky))
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
end

local function draw_rolls(view)
    local r = view.roll
    roll_combo('Roll 1', 'roll_first', r.first, r.choices, 'roll.first')
    if r.two then
        roll_combo('Roll 2', 'roll_second', r.second, r.choices, 'roll.second')
        if r.second ~= '' and r.second == r.first then text('Roll 2 is Roll 1: one roll kept up', GREY) end
    else
        text('Roll 2: Corsair main job only', GREY)
    end
    imgui.PushItemWidth(SETTING_WIDTH)
    if imgui.BeginCombo('Risk##sk3_roll_risk', (r.risk:gsub('^%l', string.upper))) then
        for _, risk in ipairs(r.risks) do
            if imgui.Selectable(risk:gsub('^%l', string.upper) .. '##sk3_roll_risk_' .. risk, risk == r.risk) then
                act.set('roll.risk', risk)
            end
            tip(RISKS[risk])
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
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

-- An Indi- spell for Entrust, or None ('').
local function indi_combo(current, names)
    imgui.PushItemWidth(PICK_WIDTH + SETTING_WIDTH / 2)
    if imgui.BeginCombo('Entrust spell##sk3_geo_entrust_spell', current ~= '' and current or 'None') then
        if imgui.Selectable('None##sk3_geo_entrust_spell_none', current == '') then act.set('geo.entrust_spell', '') end
        for _, name in ipairs(names) do
            if imgui.Selectable(name .. '##sk3_geo_entrust_spell_' .. name, name == current) then act.set('geo.entrust_spell', name) end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    tip('The Indi- spell Entrust puts on that member whenever they lack its aura.')
end

local function draw_geo(view)
    local g = view.geo
    slider('Recall past##sk3_geo_distance', 'geo.distance', g.distance, 3, 30,
        'Yalms: Full Circle the luopan once who it is on is further than this from it, so it goes down again.')
    slider('Keep after combat##sk3_geo_linger', 'geo.linger', g.linger, 1, 20,
        'Seconds a debuff luopan waits once combat is over before Full Circle recalls it: a new battle target in that time keeps it.')
    member_combo('Entrust to', 'geo_entrust', g.entrust, g.names, 'geo.entrust',
        'With Entrust on, put the Indi- spell picked on this member (within 20 yalms).')
    indi_combo(g.entrust_spell, g.indi)
    imgui.Separator()
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
                text(('%s %s'):format(p.tag, p.name) .. note, p.away and GREY or nil)
                tip(p.away and (p.kind == 'tracked' and 'Out of range.' or 'In another zone.') or nil)
            end
        end
    end
    local t = view.track.target
    if t then
        if imgui.Button(('Track %s##sk3_track'):format(t)) then act.track(t) end
        tip('Heal, clear, raise and buff them too, with what reaches outside the party. This session only.')
    else
        text('Target a player outside your alliance to track them, or /sk3 track Name.', GREY)
    end
end

local function has_name(names, name)
    for _, n in ipairs(names) do if n == name then return true end end
    return false
end

-- The name to save under, Save / Save as / New / Delete, then every profile:
-- a click loads it (Default, the working copy as it was before one was loaded).
local function draw_profiles(view)
    local p = view.profiles
    local active = p.active or ''
    if active ~= profile_shown then profile_name[1], profile_shown = active, active end
    imgui.PushItemWidth(SETTING_WIDTH)
    imgui.InputText('Name##sk3_profile_name', profile_name, 64)
    imgui.PopItemWidth()
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
    local taken = typed ~= p.active and has_name(p.names, typed)
    if taken then text(('%s exists: Save as replaces it.'):format(typed), GREY) end
    if imgui.Selectable('Default##sk3_profile_default', p.active == nil) then act.profile(nil) end
    tip('The working copy: your settings as they were before a profile was loaded.')
    -- A name is drawn over a blank row, not as its label: ImGui would cut a
    -- name at '##' and take an id from its '###'.
    for i, name in ipairs(p.names) do
        local x = imgui.GetCursorPosX()
        if imgui.Selectable('##sk3_profile_' .. i, name == p.active) then act.profile(name) end
        imgui.SameLine(x)
        text(name)
    end
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

local function draw_ui(view)
    for _, l in ipairs(UI_SLIDERS) do
        slider(l[1] .. '##sk3_ui_' .. l[2], 'ui.' .. l[2], view.ui[l[2]], l[3], l[4], l[5])
    end
    checkbox('Lock position##sk3_ui_locked', view.ui.locked == true, function (on) act.set('ui.locked', on) end,
        'Keep the HUD where it is: dragging it no longer moves it.')
    imgui.Separator()
    checkbox('Action log##sk3_log', view.log, act.log, 'Print each action to chat as it is sent.')
    draw_recent(view)
    imgui.Separator()
    checkbox('Japanese client##sk3_japanese', view.japanese, function (on) act.set('japanese', on) end,
        'Send spell, ability and item names in Japanese, on every job.')
end

-- Rows ------------------------------------------------------------------------------

local function pick_combo(r, id)
    imgui.PushItemWidth(PICK_WIDTH)
    if imgui.BeginCombo('##pick_' .. id, r.choice) then
        for _, c in ipairs(r.choices) do
            if imgui.Selectable(c.label, c.name == r.pick) then act.pick(r.key, c.name) end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
end

-- ME, P1-P5, T1...; B0-B5 and C0-C5 each on a line of their own. An empty
-- slot can't be picked, but a picked one can still be cleared.
local function target_chips(r, id)
    for i, t in ipairs(r.targets) do
        if i > 1 and not t.wrap then imgui.SameLine(0, 2) end
        local disabled = not t.present and not t.on
        local colors = disabled and CHIP_EMPTY or not t.on and CHIP_OFF
        if colors then push_button(colors) end
        if disabled then imgui.PushStyleColor(ImGuiCol_Text, GREY) end
        if imgui.Button(t.label .. '##' .. id .. t.slot, { CHIP_WIDTH, 0 }) and not disabled then
            act.target(r.key, t.slot)
        end
        if colors then imgui.PopStyleColor(disabled and 4 or 3) end
        tip(t.name or 'empty slot')
    end
end

-- Stratagems fired before the row's spell: Pen, Cel, Acc...
local function mod_chips(r, id)
    for i, m in ipairs(r.mods) do
        if i > 1 then imgui.SameLine(0, 2) end
        if not m.on then push_button(CHIP_OFF) end
        if imgui.Button(m.label .. '##' .. id .. '_mod_' .. m.name, { CHIP_WIDTH, 0 }) then act.mod(r.key, m.name) end
        if not m.on then imgui.PopStyleColor(3) end
        tip(m.note and ('%s first: %s'):format(m.name, m.note) or m.name)
    end
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
    if not imgui.BeginTable(table_id, columns, ImGuiTableFlags_SizingFixedFit) then return end
    for _, r in ipairs(rows) do
        local id = section_id .. '_' .. r.key
        imgui.TableNextRow()
        imgui.TableNextColumn()
        local v = { r.on }
        -- An item shows how many you carry; ### keeps its id while the count changes.
        local label = r.count and ('%s (%d)###%s'):format(r.label, r.count, id) or r.label .. '##' .. id
        if imgui.Checkbox(label, v) then act.row(r.key, v[1]) end
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
    imgui.EndTable()
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
    geo = 'Keep a luopan down: the Geo row\'s on its target, or the Geo debuff\'s on your battle target in combat. '
        .. 'Full Circle recalls it when its target leaves it, and a debuff\'s after combat.',
    pet = 'Look after your pet, and send it in, with the rows that are on.',
    recover = 'Get MP and TP back with the rows that are on.',
    rest = 'Rest for MP out of combat once nothing else has happened for a while; stand at full MP.',
}

local BODIES = {
    follow = draw_follow, heal = draw_heal_settings, recover = draw_recover_settings, buff = draw_buff_settings,
    roll = draw_rolls, geo = draw_geo,
    pet = draw_pet_settings, rest = draw_rest, track = draw_track, ui = draw_ui, profile = draw_profiles,
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
        -- '##' in a header's label would end what it shows.
        if h == 'Profiles' and view.profiles.active then note = ': ' .. view.profiles.active:gsub('#+', '#') end
        if imgui.CollapsingHeader(h .. note .. '###sk3_' .. h) then
            for i, s in ipairs(of[h]) do
                if i > 1 then imgui.Separator() end
                draw_section(view, s)
            end
        end
    end
end

-- Windows ---------------------------------------------------------------------------

-- Each window: Begin, the body under pcall, End; returns the error the body raised.
-- ponytail: an error inside a table or combo still leaves that scope open, which
-- ImGui asserts on; unwind tracked scopes (as v2's abort_sections does) if one shows up.
local function hud(view)
    local flags = HUD_FLAGS + (view.ui.locked and ImGuiWindowFlags_NoMove or 0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    local shown = imgui.Begin('Sidekick3', true, flags)
    imgui.PopStyleVar(2)
    local ok, err = true, nil
    if shown then ok, err = pcall(draw_hud, view) end
    imgui.End()  -- ImGui keeps where it was dragged, in imgui.ini
    if not ok then return err end
end

local function settings_window(view)
    local open = { true }
    local ok, err = true, nil
    if imgui.Begin('SK Settings', open, ImGuiWindowFlags_AlwaysAutoResize) then
        ok, err = pcall(draw_settings, view)
    end
    imgui.End()
    if not open[1] then settings_open = false end
    if not ok then return err end
end

-- One frame. A Lua error raised while drawing is raised again after the windows
-- are ended, so ImGui stays balanced and Sidekick reports it.
function window.render(view, act_)
    act = act_
    local err = hud(view)
    if settings_open then err = settings_window(view) or err end
    if err then error(err, 0) end
end

return window
