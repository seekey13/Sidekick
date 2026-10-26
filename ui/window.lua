--[[
    The standard Sidekick3 UI, and the reference: it uses only the `view` and
    `act` every UI is given (ui/README.md), so ui/custom.lua can replace it, and
    takes each setting's range from ui/model.lua's REMOTE_SET, which holds it once.
    ImGui only; it reads no game state and decides nothing. Everything is drawn
    on ImGui's draw lists in ui/kit.lua's look (docs/vana-ui-style.md), and SK
    Settings' sidebar and page layout follow VanaCore's addons/vanacore/vana/vana.lua
    (Copyright (C) 2026 Vekien, GPL-3.0-or-later). The HUD's panel, frame, title
    and close fade out until the mouse is over the window, as Tracker's do; the
    bars stay. Section headers are Tracker's: Segoe semibold italic, small capitals.

    Three kinds of window. Sidekick3 is a heads-up display: the party's HP, MP and TP
    bars on a dark panel, your pet's under yours (the alliance's other parties as
    thin HP rows under them), with a label pointing at whoever the next action is
    for, and one at whoever another Sidekick session on this PC acts on, as it
    goes. Your own card's HP bar carries the run button and the cog, which opens SK
    Settings: a page per group of sections, listed down its left, each section
    under a heading with its switch.
    So does the card of a player who is another Sidekick session on this PC: its
    buttons start and stop that session and open its own Sidekick Settings, drawn here
    from its view.
    The widget (`ui.widget`, `/sk3 widget`) is one row: each character (yours, then
    each other session's) in a pill, green running and red stopped, holding its name,
    its run button and its cog, `ui.widget_size` pixels high (blue while something holds it); right-click a name to load one of its profiles. It shows with the HUD
    closed too (`view.ui.open` false), as v2's did.

    Ashita's binding: widget values are one-element tables ({ 'text' }), and Text
    takes a printf format (kit.esc doubles any '%'). Draw-list text and kit.tooltip's
    are drawn as is.
]]--

local imgui = require('imgui')
local kit = require('ui.kit')
local LIMITS = require('ui.model').REMOTE_SET  -- each setting's range, as a session takes it from another

local window = {}

local P, S = kit.P, kit.S
local BODY, SMALL = kit.BODY, kit.SMALL

-- { label, key, min, max, help, unit } for view.ui: sizes in pixels.
local UI_SLIDERS = {
    { 'HP bar width', 'hp_width', 80, 600, 'Pixels.', 'px' },
    { 'HP bar height', 'hp_height', 10, 120, 'Pixels.', 'px' },
    { 'MP bar width', 'mp_width', 80, 600, 'Pixels.', 'px' },
    { 'MP bar height', 'mp_height', 4, 80, 'Pixels.', 'px' },
    { 'TP bar width', 'tp_width', 80, 600, 'Pixels: its three parts, 1000 TP each, together.', 'px' },
    { 'TP bar height', 'tp_height', 4, 80, 'Pixels.', 'px' },
    { 'Name font size', 'name_size', 8, 64, 'Pixels.', 'px' },
    { 'Text font size', 'text_size', 8, 48, 'Pixels: the title, the tags, the alliance\'s names and the action labels; '
        .. 'the buttons follow it, as far as the HP bar fits them.', 'px' },
    { 'Spacing', 'gap', 0, 40, 'Pixels between members.', 'px' },
}

local JOINED = { party = '  (in your party)', alliance = '  (in your alliance)' }  -- a tracked player's note

local act                    -- this frame's actions (another session's, while drawing its Sidekick Settings)
local settings_open = false  -- Sidekick Settings shown; this session only
local hud_open = true        -- last frame's view.ui.open: closing the HUD (/sk3) closes Sidekick Settings with it,
                             -- unless the widget is up
local profile_names = {}     -- per Sidekick Settings window ('' for yours, else the session's name), this session only:
                             -- { typed = { name }, shown }, the name filled in again when the profile loaded changes
local panes = {}             -- per Sidekick Settings window, as profile_names: { page, folded = { [section id] = true } }
local user_scale = 1         -- Sidekick Settings' size (view.ui.scale), taken up while nothing is held

-- HUD -----------------------------------------------------------------------------

local HUD_PAD, BAR_GAP, ROUND = 8, 3, 4  -- the panel's padding, between bars, the bars' corners (pixels)
local BAR_FILL = 0.7                     -- the fill lets the game show through, as the reference bar
local BAR_TRACK_A = 0.7                  -- bar background stays at 70%: gray hovered, black while not
local BAR_EDGE = 1                       -- the stroke around each bar
local BAR_EDGE_A = 0.7                   -- that stroke is black at 70%, and it does not fade with the panel
local BAR_OFF = '#0c0c0c'                -- the background while the pointer is off the panel; the stroke is always this
local TITLE = 'Sidekick3'

local HUD_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoBringToFrontOnFocus

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
        .. (p.kind ~= 'tracked' and ('  TP %d'):format(p.tp) or '')  -- a tracked player's can't be read
    if p.dist ~= '' and not p.away then line = line .. '  ' .. p.dist end
    local lines = { #notes > 0 and ('%s (%s)'):format(p.name, table.concat(notes, ', ')) or p.name, line }
    if p.buffs_all ~= '' then lines[#lines + 1] = p.buffs_all end
    return table.concat(lines, '\n')
end

local function pet_tip(pet)
    return ('%s (pet)\nHP %d%%  MP %d%%  TP %d  %s'):format(pet.name, pet.hpp, pet.mpp, pet.tp, pet.dist)
end

-- A track at (x, y), w by h, `f` (0 to 1) of it filled in `color`. The whole bar has a
-- background at 70% that does not fade with the panel: gray while the pointer is over
-- it (`chrome` 1), near-black while not. A 1px stroke in that same near-black, at 70%, sits on the edge.
-- The fill is at 70% too.
local function track(dl, x, y, w, h, f, color, alpha, chrome)
    local r = math.min(ROUND, math.floor(h / 2))
    kit.fill(dl, x, y, w, h, kit.mix(BAR_OFF, P.track, chrome), r, BAR_TRACK_A)
    local fw = math.max(0, math.min(w, math.floor(w * f + 0.5)))
    if fw > 0 then
        kit.fill(dl, x, y, fw, h, color, math.min(r, fw / 2), alpha * BAR_FILL, fw < w and kit.LEFT_CORNERS or nil)
    end
    kit.outline(dl, x, y, w, h, BAR_OFF, r, BAR_EDGE_A, BAR_EDGE)
end

-- A bar: `pct` of its track filled (eased, by `id`).
local function bar(dl, id, x, y, w, h, pct, color, alpha, chrome)
    track(dl, x, y, w, h, kit.ease(id, math.min(math.max(pct, 0), 100) / 100, 12), color, alpha, chrome)
end

local TIER, TIERS = 1000, 3  -- TP: a weapon skill's worth, and how many stand

-- The TP bar: a track per 1000 TP side by side, each filling once the one before is full (eased, by `id`); the one
-- still filling is drawn faint, as Floaties draws it.
local function tp_bar(dl, id, x, y, w, h, tp, alpha, chrome)
    local t = kit.ease(id, math.min(math.max(tp, 0), TIER * TIERS) / TIER, 12)  -- in tiers
    local tw = (w - (TIERS - 1) * BAR_GAP) / TIERS
    for i = 1, TIERS do
        local f = math.min(math.max(t - (i - 1), 0), 1)
        local tx = math.floor(x + (i - 1) * (tw + BAR_GAP) + 0.5)
        track(dl, tx, y, math.floor(x + i * tw + (i - 1) * BAR_GAP + 0.5) - tx, h, f, P.tp,
            (f < 1 and 0.5 or 1) * alpha, chrome)
    end
end

-- A round button s across at (x, y): `lit` (running, its settings shown) fills it in the accent. Returns clicked,
-- hovered.
local function disc_button(id, x, y, s, glyph, lit, help)
    local hovered, clicked = kit.hit(id, x, y, s, s)
    kit.tip(help)
    local dl = imgui.GetWindowDrawList()
    local disc = lit and (hovered and P.accent2 or P.accent) or (hovered and P.accent_lo or P.well)
    kit.circle(dl, x + s / 2, y + s / 2, s / 2, disc)
    kit.icon(dl, glyph, x + s / 2, y + s / 2, s * 0.62, lit and P.ink or P.text, 1, disc)
    return clicked, hovered
end

-- Tracker's close: an X, dim until the pointer is on it, then rose. No disc behind it.
local function close_mark(id, cx, cy, box, alpha)
    local hovered, clicked = kit.hit(id, cx - box / 2, cy - box / 2, box, box)
    kit.icon(imgui.GetWindowDrawList(), 'close', cx, cy, box * 0.72, hovered and P.rose or P.dim, alpha)
    return clicked, hovered
end

-- "Sidekick3", then close (s pixels across); the title's hover area says what automation is doing.
-- Both fade with the panel (`chrome`).
local function title_row(dl, view, ts, x0, y0, pw, th, s, chrome)
    local font = kit.fonts.semi
    local _, h = kit.measure(TITLE, font, ts)
    kit.halo(dl, x0 + HUD_PAD, y0 + (th - h) / 2, TITLE, P.white, font, ts, chrome)
    local cx, cy = x0 + pw - HUD_PAD - s / 2, y0 + th / 2
    imgui.SetCursorScreenPos({ x0, y0 })
    imgui.Dummy({ cx - s / 2 - x0, th })
    kit.tip(status_tip(view))
    local clicked = close_mark('##sk3_close', cx, cy, s, chrome)
    kit.tip('Close (/sk3 opens it again)')
    if clicked then
        act.close()
        if not view.ui.widget then settings_open = false end  -- the widget's cogs keep them
    end
end

-- Run and the cog at the top right of the HP bar of your card, or of another session's, s pixels across (at most
-- what the bar fits). Returns whether one is hovered, so the card's own tooltip gives way.
local function card_icons(view, ui, p, x, y, s)
    local fx = x + HUD_PAD
    s = math.min(s, ui.hp_height - 4, math.floor((ui.hp_width - 8) / 2))
    local iy, cog_x = y + 2, fx + ui.hp_width - 2 - s
    local run_x = cog_x - 4 - s
    local remote = p.session
    local running = remote and remote.running or not remote and view.status.running
    local shown = remote and remote.open or not remote and settings_open
    local id, whose = remote and ('_' .. remote.name) or '', remote and (remote.name .. '\'s ') or ''
    local clicked, over_run = disc_button('##sk3_run' .. id, run_x, iy, s, running and 'stop' or 'play', running,
        (running and 'Stop ' or 'Start ') .. whose .. 'automation')
    if clicked then (remote and act.remote(remote.name) or act).run(not running) end
    local cog, over_cog = disc_button('##sk3_cog' .. id, cog_x, iy, s, 'cog', shown,
        remote and ('Settings for ' .. remote.name) or 'Settings')
    if cog and remote then act.watch(remote.name, not remote.open)
    elseif cog then settings_open = not settings_open end
    return over_run or over_cog
end

-- The name on an HP bar. Over 75% it stays white; at 75% it turns yellow, at 50% orange and at 25% red.
-- Away, it greys with the bars.
local function name_color(p)
    if p.away then return P.dim end
    local hpp = p.hpp or 100
    if hpp <= 25 then return P.red end
    if hpp <= 50 then return P.orange end
    if hpp <= 75 then return P.yellow end
    return P.white
end

-- A member's card at (x, y): the HP bar over the MP bar over the TP bar, the name on the first and the tag on the
-- second, the % of each (TP's number) only in its tooltip. A tracked player's MP and TP can't be read: their bars stay
-- empty. The name turns yellow at 75% HP, orange at 50% and red at 25%; MP under the Recover line turns the tag
-- rose. Away, the bars fade and the text greys. `id` keeps the bars' eased fills apart.
local function card(dl, ui, p, x, y, id, chrome)
    local fx, mp_top = x + HUD_PAD, y + ui.hp_height + BAR_GAP
    local fade = p.away and 0.45 or 1
    bar(dl, 'hp.' .. id, fx, y, ui.hp_width, ui.hp_height, p.hpp, P.hp, fade, chrome)
    bar(dl, 'mp.' .. id, fx, mp_top, ui.mp_width, ui.mp_height, p.mpp, P.mp, fade, chrome)
    tp_bar(dl, 'tp.' .. id, fx, mp_top + ui.mp_height + BAR_GAP, ui.tp_width, ui.tp_height, p.tp, fade, chrome)
    local font = kit.fonts.semi
    local _, nh = kit.measure(p.name, font, ui.name_size)
    kit.halo(dl, fx + 6, y + ui.hp_height - nh, p.name, name_color(p), font, ui.name_size)
    local _, th = kit.measure(p.tag, font, ui.text_size)
    kit.halo(dl, fx + 6, mp_top + (ui.mp_height - th) / 2, p.tag,
        p.away and P.dim or p.mp == 'low' and P.rose or P.text2, font, ui.text_size)
end

-- An alliance member's row, its bar's top at `top`: a thin HP bar (the MP bar's height) with the tag and name on
-- it, coloured as a card's name is, its HP % only in its tooltip.
local function ally_row(dl, ui, p, x, top, chrome)
    local fx = x + HUD_PAD
    bar(dl, 'ally.' .. p.name, fx, top, ui.hp_width, ui.mp_height, p.hpp, P.hp, p.away and 0.45 or 1, chrome)
    local label = p.tag .. ' ' .. p.name
    local _, h = kit.measure(label, kit.fonts.semi, ui.text_size)
    kit.halo(dl, fx + 6, top + (ui.mp_height - h) / 2, label, name_color(p), kit.fonts.semi, ui.text_size)
end

-- Labels in pills side by side, the first's point just right of the panel at `cy`: this session's amber while running
-- (what goes), grey while stopped (what would); another session's blue, after its name on a darker part. On the
-- background list: they sit outside the window without widening it, as a transparent window area would block the
-- game's clicks.
local function draw_labels(list, ts, right, cy)
    if not list[1] then return end
    local dl = imgui.GetBackgroundDrawList()
    local font = kit.fonts.semi
    local h, pad = math.floor(ts * 1.6), math.floor(ts * 0.6)
    local x = right + 2 + math.floor(h * 0.45)  -- the first pill's left, after its point
    for i, l in ipairs(list) do
        local who = l.session
        local nw = who and kit.measure(who, font, ts) + pad * 2 or 0  -- the name's part
        local w = nw + kit.measure(l.text, font, ts) + pad * 2
        local color = who and P.accent or l.live and P.amber or P.seg
        kit.fill(dl, x, cy - h / 2 + 2, w, h, '#000000', h / 2, 0.3)  -- its shadow
        if i == 1 then kit.tri(dl, { right + 2, cy }, { x + h / 4, cy - h * 0.32 }, { x + h / 4, cy + h * 0.32 }, color) end
        kit.fill(dl, x, cy - h / 2, w, h, color, h / 2)
        if who then
            kit.fill(dl, x, cy - h / 2, nw, h, P.accent_lo, h / 2, 1, kit.LEFT_CORNERS)
            kit.text_mid(dl, x + pad, cy, who, P.white, font, ts)
        end
        kit.text_mid(dl, x + nw + pad, cy, l.text, (who or l.live) and P.ink or P.text2, font, ts)
        x = x + w + math.floor(h * 0.3)
    end
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

-- The cards from the top: each party line's (`member`, its index) and, under yours, your pet's (`pet`), drawn from a
-- line of the same shape tagged PET; `id` keeps their eased fills apart.
local function cards_of(view)
    local out = {}
    for i, p in ipairs(view.party) do
        out[#out + 1] = { p = p, id = p.name, member = i }
        local pet = i == 1 and view.pet
        if pet then
            out[#out + 1] = { p = { name = pet.name, tag = 'PET', hpp = pet.hpp, mpp = pet.mpp, tp = pet.tp },
                              id = 'pet.' .. pet.name, pet = true }
        end
    end
    return out
end

-- Whether the arrow points at card `c`: your pet's for its own actions, else the member's.
local function pointed(view, c)
    local ptr = view.pointer
    if not ptr then return false end
    local to_pet = ptr.pet == true and view.pet ~= nil
    if c.pet then return to_pet end
    return not to_pet and ptr.member == c.member
end

-- The labels at card `c`, or at the alliance's row `j`: this session's first, then each other session's there.
local function labels_at(view, c, j)
    local ptr, out = view.pointer, {}
    if c and pointed(view, c) or j and ptr and ptr.ally == j then out[1] = ptr end
    for _, o in ipairs(view.others) do
        if c and not c.pet and o.member == c.member or j and o.ally == j then out[#out + 1] = o end
    end
    return out
end

local function draw_hud(view)
    local ui = hud_sizes(view.ui)
    local dl = imgui.GetWindowDrawList()
    local x0, y0 = imgui.GetCursorScreenPos()
    local th, s = math.floor(ui.text_size * 1.8), math.floor(ui.text_size * 1.25)
    local pw = math.max(2 * HUD_PAD + math.max(ui.hp_width, ui.mp_width, ui.tp_width),
                        math.ceil(HUD_PAD + kit.measure(TITLE, kit.fonts.semi, ui.text_size) + 8 + s + HUD_PAD))  -- the title row fits
    local ch = ui.hp_height + BAR_GAP + ui.mp_height + BAR_GAP + ui.tp_height
    local cards = cards_of(view)
    local n = #cards
    -- Under the cards, the alliance's rows: B0-B5, then C0-C5, each party after a gap; `rows` holds each bar's top.
    local below, rows, last = th + n * ch + math.max(n - 1, 0) * ui.gap, {}, nil
    for j, p in ipairs(view.alliance) do
        local party = p.tag:sub(1, 1)
        below = below + (party ~= last and math.max(ui.gap, BAR_GAP) or BAR_GAP)
        rows[j], last = below, party
        below = below + ui.mp_height
    end
    local ph = below + HUD_PAD
    -- The panel is solid while the mouse is over the window (last frame's rect, as IsWindowHovered reads it) and gone
    -- off it. The bars stay.
    local chrome = kit.ease('chrome', imgui.IsWindowHovered() and 1 or 0)
    kit.fill(dl, x0, y0, pw, ph, P.bg, 6, chrome)
    kit.outline(dl, x0, y0, pw, ph, P.border, 6, chrome)
    title_row(dl, view, ui.text_size, x0, y0, pw, th, s, chrome)
    for i, c in ipairs(cards) do
        local p, y = c.p, y0 + th + (i - 1) * (ch + ui.gap)
        card(dl, ui, p, x0, y, c.id, chrome)
        local on_icon = (p.kind == 'self' or p.session) and card_icons(view, ui, p, x0, y, s)
        imgui.SetCursorScreenPos({ x0 + HUD_PAD, y })
        imgui.Dummy({ pw - 2 * HUD_PAD, ch })
        if not on_icon then kit.tip(c.pet and pet_tip(view.pet) or member_tip(p)) end
        draw_labels(labels_at(view, c), ui.text_size, x0 + pw, y + ch / 2)
    end
    for j, p in ipairs(view.alliance) do
        local top = y0 + rows[j]
        ally_row(dl, ui, p, x0, top, chrome)
        imgui.SetCursorScreenPos({ x0 + HUD_PAD, top })
        imgui.Dummy({ pw - 2 * HUD_PAD, ui.mp_height })
        kit.tip(member_tip(p))
        draw_labels(labels_at(view, nil, j), ui.text_size, x0 + pw, top + ui.mp_height / 2)
    end
    imgui.SetCursorScreenPos({ x0, y0 + ph - HUD_PAD })
    imgui.Dummy({ pw, HUD_PAD })  -- the bottom padding, and the panel's full width, for the auto-size
end

-- The widget ------------------------------------------------------------------------

local WIDGET_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_AlwaysAutoResize
    + ImGuiWindowFlags_NoScrollbar + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_NoBackground
local WIDGET_SIZES = { 10, 48 }  -- view.ui.widget_size's range: its text and icons' height, in pixels

local function widget_size(ui)
    return math.min(math.max(math.floor(tonumber(ui and ui.widget_size) or 16), WIDGET_SIZES[1]), WIDGET_SIZES[2])
end

-- The characters the widget shows: you, then every other Sidekick session on this PC (view.sessions, by name: from
-- their files, so a zone leaves them as they were). { name, running, halted, shown (its Sidekick Settings), profiles
-- (nil while unknown), remote (nil for yours) }.
local function characters(view)
    local me = view.party[1]
    local out = { { name = me and me.name or 'You', running = view.status.running, halted = view.status.halted,
                    shown = settings_open, profiles = view.profiles } }
    for _, r in ipairs(view.sessions or {}) do
        out[#out + 1] = { name = r.name, running = r.running, halted = r.halted, shown = r.open, profiles = r.profiles,
                          remote = r }
    end
    return out
end

-- A character's act: yours, or the session's, made only when it's used.
local function act_of(c) return c.remote and act.remote(c.name) or act end

-- A character's profiles, right-clicking its name: Default, then each saved; a click loads it there.
local function profile_menu(c, id, px)
    kit.popup(id, px, function ()
        local p = c.profiles
        if imgui.Selectable('Default' .. id .. '_default', p.active == nil) then act_of(c).profile(nil) end
        for i, name in ipairs(p.names or {}) do  -- over a blank row, so a name with '##' in it shows whole
            local sx = imgui.GetCursorPosX()
            if imgui.Selectable(id .. '_' .. i, name == p.active) then act_of(c).profile(name) end
            imgui.SameLine(sx)
            imgui.Text(kit.esc(name))
        end
    end)
end

-- One row on a panel of its own: each character in a pill, green while running (blue while something holds it: AFK
-- sleep, a mount, a zone...) and red while stopped, holding its
-- name, its run button and its cog, `ui.widget_size` pixels high. Right-click a name for its profiles; hover it for
-- what it's doing.
local function draw_widget(view)
    local dl = imgui.GetWindowDrawList()
    local x0, y0 = imgui.GetCursorScreenPos()
    local h = widget_size(view.ui)
    local function px(k) return math.floor(h * k + 0.5) end
    local pad, apart, gap = px(0.3), px(0.4), px(0.3)  -- round the pills, between them, between a pill's parts
    local edge, lead = px(0.15), px(0.45)              -- inside a pill: round its buttons, before its name
    local list, font = characters(view), kit.fonts.semi
    local pill_h = h + edge * 2
    local pw = pad * 2 - apart
    for _, c in ipairs(list) do
        c.w = math.ceil(kit.measure(c.name, font, h))
        c.pill = lead + c.w + gap + h + math.floor(gap / 2) + h + edge
        pw = pw + c.pill + apart
    end
    local ph = pill_h + pad * 2
    kit.fill(dl, x0, y0, pw, ph, P.bg, px(0.5))
    kit.outline(dl, x0, y0, pw, ph, P.border, px(0.5))

    local x, cy = x0 + pad, y0 + ph / 2
    for _, c in ipairs(list) do
        local id = c.remote and ('##sk3_widget_' .. c.name) or '##sk3_widget'
        local whose = c.remote and (c.name .. '\'s ') or ''
        kit.fill(dl, x, y0 + pad, c.pill, pill_h, c.halted and P.held or c.running and P.go or P.halt, pill_h / 2)
        local nx = x + lead
        kit.text_mid(dl, nx, cy, c.name, P.white, font, h)
        imgui.SetCursorScreenPos({ x, y0 + pad })
        imgui.Dummy({ lead + c.w, pill_h })  -- an item to hover, not a button: the widget still drags by its name
        local menu = id .. '_profiles'
        local state = c.halted and ('Halted (%s)'):format(c.halted) or c.running and 'Running' or 'Stopped'
        if imgui.IsItemHovered() then
            if not c.remote then  -- your status's tooltip names the profile already
                kit.tooltip(status_tip(view) .. '\nRight-click to load a profile.')
            elseif c.profiles then
                kit.tooltip(('%s: %s\nProfile: %s\nRight-click to load another.'):format(c.name, state,
                    c.profiles.active or 'Default'))
            else  -- its profiles never came (its file left them out)
                kit.tooltip(('%s: %s'):format(c.name, state))
            end
            if c.profiles and imgui.IsMouseClicked(1) then imgui.OpenPopup(menu) end
        end
        if c.profiles and imgui.IsPopupOpen(menu) then profile_menu(c, menu, h) end  -- the row's size, not Settings'
        local bx = nx + c.w + gap
        local clicked = disc_button(id .. '_run', bx, cy - h / 2, h, c.running and 'stop' or 'play', false,
            (c.running and 'Stop ' or 'Start ') .. whose .. 'automation')  -- the pill says which
        if clicked then act_of(c).run(not c.running) end
        bx = bx + h + math.floor(gap / 2)
        local cog = disc_button(id .. '_cog', bx, cy - h / 2, h, 'cog', c.shown,
            c.remote and ('Settings for ' .. c.name) or 'Open or close Sidekick Settings')
        if cog and c.remote then act.watch(c.name, not c.shown)
        elseif cog then settings_open = not settings_open end
        x = x + c.pill + apart
    end
    imgui.SetCursorScreenPos({ x0, y0 + ph - 1 })
    imgui.Dummy({ pw, 1 })  -- the panel's full size, for the auto-size
end

-- Sidekick Settings: the page's rows -----------------------------------------------------

-- Fixed for every job. 390 is the narrowest page that still holds a slider beside
-- "Focus danger under" and the longest roll name ("Companion's Roll (Pet Regain
-- & Regen)") beside "Roll 1". Song, rune and maneuver picks have their own widths
-- below and wrap onto the next line; the window does not grow to fit a job.
local SIDE_W, PAGE_W, WIN_H, MARGIN = 160, 390, 580, 6  -- unscaled, as every size from here
local TITLE_H, HEAD_H, ROW_H, NAV_H, CHIP_LINE = 44, 28, 30, 28, 26
local LEFT, PAD, GUTTER, LABEL_W = 24, 18, 12, 120
local SLIDER_W, PICK_W, ROLL_W, RUNE_W, MANEUVER_W, SONG_W, CHIP_W = 180, 220, 286, 168, 90, 248, 30
local FOOT = { Profiles = true, ['UI / Log'] = true }  -- set apart at the foot of the list of pages

--[[ pg: where a page's rows go, from top to bottom: { dl, x, w, y (the next row's top), lx (where labels start),
     right (where controls end), alpha (0.55 under a section switched off) }. ]]--

-- A line `h` tall (ROW_H unless given): the band under the mouse, `label` at the left, `help` over the label's half.
-- Returns its first line's middle.
local function line(pg, label, help, h, color)
    h = h or S(ROW_H)
    local y = pg.y
    pg.y = y + h
    if kit.over(pg.x + S(4), y, pg.w - S(8), h) then kit.fill(pg.dl, pg.x + S(4), y, pg.w - S(8), h, P.hover, S(3), 0.8) end
    local cy = y + math.min(h, S(ROW_H)) / 2
    if label then kit.text_mid(pg.dl, pg.lx, cy, label, color or P.text, kit.fonts.text, S(BODY), pg.alpha) end
    if help and kit.over(pg.x, y, pg.w / 2, h) then kit.tooltip(help) end
    return cy
end

-- A control's id from its label and the setting it sets: 'Rest after##sk3_rest_delay'.
local function id_of(label, path) return label .. '##sk3_' .. path:gsub('%.', '_') end

-- A slider for setting `path` (`value`), over its range in LIMITS unless `range` ({ min, max }) is given.
local function slider(pg, label, path, value, help, unit, range)
    local cy = line(pg, label, help)
    local r = range or LIMITS[path]
    local v, moved = kit.slider(id_of(label, path), pg.right - S(SLIDER_W), cy, S(SLIDER_W), value, r[1], r[2], true, pg.alpha, unit)
    if moved then act.set(path, v) end
end

-- A switch: `set(on)` when flipped, else setting `path` (also its id).
local function switch(pg, label, path, on, help, set)
    local cy = line(pg, label, help)
    local v, flipped = kit.switch(id_of(label, path), pg.right - S(kit.SW_W), cy, on, true, pg.alpha)
    kit.tip(help)
    if flipped then (set or function (x) act.set(path, x) end)(v) end
end

-- A drop-down at the right of a labelled line; `body` lists its choices.
local function pick(pg, label, id, shown, body, help, w)
    local cy = line(pg, label, help)
    w = w or S(PICK_W)
    kit.dropdown(id, pg.right - w, cy, w, shown, true, pg.alpha, body)
end

-- Text across the page, wrapped.
local function note(pg, s, color)
    local px = S(SMALL + 0.5)
    for _, l in ipairs(kit.wrap(s, kit.fonts.text, px, pg.right - pg.lx)) do
        kit.text_mid(pg.dl, pg.lx, pg.y + S(11), l, color or P.dim, kit.fonts.text, px, pg.alpha)
        pg.y = pg.y + S(22)
    end
end

-- Whether something can go now, ending at `right`: 'ready' in teal, else why not, dim.
local function readiness(pg, right, cy, avail, ready)
    kit.text_right(pg.dl, right, cy, avail, ready and P.teal or P.dim, kit.fonts.text, S(SMALL + 0.5), pg.alpha)
end

-- A group's heading inside a section: Tracker's small capitals, a line after.
local function subheader(pg, s)
    pg.y = pg.y + S(8)
    local cy = pg.y + S(12)
    local font, px, spacing = kit.fonts.semi_italic, S(SMALL), math.max(1, S(1.2))
    local title = string.upper(s)
    local tw = kit.text_spaced(pg.dl, pg.lx, cy, title, P.teal, font, px, spacing, pg.alpha)
    local tx = pg.lx + tw + S(10)
    if pg.right > tx then kit.line(pg.dl, tx, cy, pg.right, cy, P.teal, 0.35 * pg.alpha) end
    pg.y = pg.y + S(26)
end

-- Lays `items` ({ w, wrap, pre }) out in lines from x0 to right, `gap` apart, each getting .x and .line (from 1):
-- one with `wrap` starts a line, `pre` adds room before one that doesn't. Returns the number of lines.
local function flow(items, x0, right, gap)
    local x, n = x0, 1
    for i, it in ipairs(items) do
        if i > 1 and (it.wrap or x + (it.pre or 0) + it.w > right) then x, n = x0, n + 1
        elseif i > 1 then x = x + (it.pre or 0) end
        it.x, it.line = x, n
        x = x + it.w + gap
    end
    return n
end

-- What a pick shows: its choice's `field` (label), or None; a pick the job no longer has says so
-- (a name, as one who isn't here now, doesn't).
local function shown_pick(current, choices, field)
    for _, c in ipairs(choices) do
        if c.name == current then return c[field or 'label'] end
    end
    return current ~= '' and current .. (choices.names and '' or ' (not available)') or 'None'
end

-- A drop-down's list for setting `path`: None (''), then each of `choices` ({ name, label }) by its
-- `field` (label), `current` ticked, each with the tooltip `tip(choice)` gives; `id` keeps their ids apart.
local function options(id, path, current, choices, field, tip)
    return function ()
        if imgui.Selectable('None##' .. id .. '_none', current == '') then act.set(path, '') end
        for _, c in ipairs(choices) do
            if imgui.Selectable(c[field or 'label'] .. '##' .. id .. '_' .. c.name, c.name == current) then act.set(path, c.name) end
            if tip then kit.tip(tip(c)) end
        end
    end
end

-- Names as choices.
local function named(names)
    local out = { names = true }
    for i, n in ipairs(names) do out[i] = { name = n, label = n } end
    return out
end

-- A labelled line's drop-down for setting `path` (None for ''), `w` wide (PICK_W).
local function choice(pg, label, id, path, current, choices, help, w, tip)
    pick(pg, label, label .. '##sk3_' .. id, shown_pick(current, choices), options('sk3_' .. id, path, current, choices, nil, tip),
        help, w)
end

-- A slot's drop-down at (x, cy), `w` wide, for setting `path`. Returns whether it's hovered.
local function slot_pick(id, path, current, choices, x, cy, w, alpha, field, tip)
    return kit.dropdown('##' .. id, x, cy, w, shown_pick(current, choices, field), true, alpha,
        options(id, path, current, choices, field, tip))
end

-- Sidekick Settings bodies ---------------------------------------------------------------

local HEAL_LINES = {
    { 'Heal under', 'threshold', 'Under this HP %, heal with the most HP for the MP or TP. Over it, missing HP is left be.' },
    { 'Danger under', 'danger', 'Under this HP %, heal fastest instead, and wait for a heal nearly ready.' },
    { 'Critical under', 'critical', 'Under this HP %, boost the heal first (Divine Seal) or save them (Martyr).' },
}
local HEAL_TIP = 'Untick to never heal them for their own sake; an area heal may still land on them.'

-- Who healing looks after, a chip each: one switched off is never healed for its own sake. Each of the alliance's
-- other parties starts a line.
local function heal_members(pg, h)
    if #h.members == 0 then return end
    local items = {}
    for i, m in ipairs(h.members) do items[i] = { w = kit.chip_width(m.name), wrap = m.wrap } end
    local lines = flow(items, pg.lx + S(LABEL_W), pg.right, S(4))
    local cy = line(pg, 'Heal', HEAL_TIP, S(ROW_H) + (lines - 1) * S(CHIP_LINE))
    for i, m in ipairs(h.members) do
        local it = items[i]
        if kit.chip(m.name .. '##sk3_heal_' .. m.name, it.x, cy + (it.line - 1) * S(CHIP_LINE), it.w, m.name,
                m.healed and 'on' or 'off', true, pg.alpha) then
            act.skip(m.name, m.healed)
        end
        kit.tip(HEAL_TIP)
    end
end

local function draw_heal_settings(view, pg)
    local h = view.heal
    for _, l in ipairs(HEAL_LINES) do slider(pg, l[1], 'heal.' .. l[2], h[l[2]], l[3], '%') end
    -- A heal line at or under its danger line leaves nothing between them: only danger heals go.
    if h.threshold <= h.danger then note(pg, 'Heal under is at or under Danger under: no efficient heals, only danger ones.', P.amber) end
    choice(pg, 'Focus', 'focus', 'heal.focus', h.focus, named(h.focus_names), 'Heal this member first, on its own lines.')
    for _, l in ipairs(HEAL_LINES) do
        slider(pg, 'Focus ' .. l[1]:lower(), 'heal.focus_' .. l[2], h['focus_' .. l[2]], 'For the focus member: ' .. l[3], '%')
    end
    if h.focus_threshold <= h.focus_danger then
        note(pg, 'Focus heal under is at or under Focus danger under: the focus member gets danger heals only.', P.amber)
    end
    slider(pg, 'Cure potency +', 'heal.cure_potency', h.cure_potency, 'Cure potency % from gear, until a cure has been seen healing.', '%')
    slider(pg, 'Waltz potency +', 'heal.waltz_potency', h.waltz_potency, 'Waltz potency % from gear, until a waltz has been seen healing.', '%')
    slider(pg, 'Regen potency +', 'heal.regen_potency', h.regen_potency, 'HP per Regen tick from gear.')
    switch(pg, 'Heal the alliance', 'heal.alliance', h.alliance,
        'Heal the alliance\'s other parties too, with heals that reach outside your party. Raising, waking, '
        .. 'removal and buffs look after them whatever this says, and the focus member is always healed.')
    if h.stratagems then
        switch(pg, 'Keep a stratagem for healing', 'heal.reserve', h.reserve,
            'Buff rows never spend the last stratagem charge, so healing has one for Accession or Rapture.')
    end
    heal_members(pg, h)
end

local function draw_recover_settings(view, pg)
    local r = view.recover
    slider(pg, 'MP under', 'recover.mp', r.mp, 'Recover MP under this MP % (yours; a member\'s for Devotion).', '%')
    slider(pg, 'TP under', 'recover.tp', r.tp, 'In combat, get TP back under this.')
    if r.spends_tp then
        slider(pg, 'Spend TP from', 'recover.min_tp', r.min_tp, 'Chivalry turns all your TP into MP: only from this much.')
    end
end

local function draw_pet_settings(view, pg)
    slider(pg, 'Pet HP under', 'pet.heal', view.pet_heal, 'Heal your pet under this HP %.', '%')
end

local function draw_follow(view, pg)
    local f = view.follow
    choice(pg, 'Leader', 'follow_target', 'follow.target', f.target, named(f.names), 'Who to follow; resting stands up when they leave too.')
    slider(pg, 'Follow past', 'follow.distance', f.distance, 'Yalms.', 'y')
end

local function draw_rest(view, pg)
    local r = view.rest
    slider(pg, 'Rest after', 'rest.delay', r.delay, 'Seconds of nothing to do.', 's')
    slider(pg, 'Stand past', 'rest.distance', r.distance, 'Yalms from the leader.', 'y')
end

local function draw_afk(view, pg)
    local a = view.afk
    slider(pg, 'Sleep after', 'afk.minutes', a.minutes, 'Minutes with no one in your party moving and no combat.', 'm')
    if a.asleep then note(pg, 'Asleep: move to wake.')
    elseif a.left then note(pg, ('Sleeps in %d min without movement or combat.'):format(math.ceil(a.left / 60))) end
end

local function draw_buff_settings(view, pg)
    local b = view.buff
    switch(pg, 'Hold area buffs for the group', 'buff.hold_aoe', b.hold_aoe,
        'Hold an area buff spell (Protectra, Barfira, songs) while a player in your party who lacks it is out of its '
        .. 'reach, so nobody is left out. Trusts and members in another zone never hold it.')
    if b.hold_aoe then
        switch(pg, 'Ask them to gather', 'buff.gather', b.gather,
            'While one is held that someone near you lacks too, say "Gather together for <spell>" in party chat, '
                .. 'at most every 5 seconds.')
    end
    if b.shadows then
        switch(pg, 'Cast Utsusemi at one shadow', 'buff.one_shadow', b.one_shadow,
            'Recast Utsusemi while its last shadow is up, not only once it is gone. For Ichi, which cannot replace '
                .. 'Ni\'s shadows, that shadow is cancelled a second into the cast, so the new ones land.')
    end
end

local RISKS = {
    lowest = 'Lowest: banks lucky, and never doubles once a die could bust (6 or more).',
    medium = 'Medium: banks lucky, chases it while it is one die away, and doubles off unlucky up to 8.',
    highest = 'Highest: 11 or nothing. Rolls past lucky, and doubles at 6-10 while Fold is ready to undo a Bust; '
        .. 'without Fold, plays as Medium.',
}
local RISK_HELP = 'How far Double-Up chases a total. Every risk doubles at 5 or under (Lowest and Medium bank a lucky '
    .. 'there), never at 11, and turns 10 into 11 with Snake Eye. Fold clears a Bust whenever it is ready.'

local function lucky(c) return ('Lucky %d, unlucky %d.'):format(c.lucky, c.unlucky) end

local function draw_rolls(view, pg)
    local r = view.roll
    choice(pg, 'Roll 1', 'roll_first', 'roll.first', r.first, r.choices, nil, S(ROLL_W), lucky)
    if r.two then
        choice(pg, 'Roll 2', 'roll_second', 'roll.second', r.second, r.choices, nil, S(ROLL_W), lucky)
        if r.second ~= '' and r.second == r.first then note(pg, 'Roll 2 is Roll 1: one roll kept up') end
    else
        note(pg, 'Roll 2: Corsair main job only')
    end
    local labels, ids, index = {}, {}, 0
    for i, risk in ipairs(r.risks) do
        labels[i] = (risk:gsub('^%l', string.upper))
        ids[i] = labels[i] .. '##sk3_roll_risk_' .. risk
        if risk == r.risk then index = i end
    end
    local cy = line(pg, 'Risk', RISK_HELP)
    local px = S(BODY - 1)
    local picked, moved, over = kit.segments(ids, pg.right - kit.segments_width(labels, px), cy, labels, index, true, pg.alpha, px)
    if over then kit.tooltip(RISKS[r.risks[over]]) end
    if moved then act.set('roll.risk', r.risks[picked]) end
    local l = r.last
    if l then
        local word = l.bust and ' (Bust)' or l.total == l.lucky and ' (lucky)' or l.total == 11 and ' (11)'
            or l.total == l.unlucky and ' (unlucky)' or ''
        note(pg, ('Last: %s %d%s'):format(l.name, l.total, word), l.bust and P.rose or P.text2)
    end
end

local SONG_HELP = {
    area = 'Sung as they are, on you and everyone in your party near you, whenever someone there lacks one. '
        .. 'A member with songs of their own picked keeps only the slots those leave.',
}
local SONGS_TIP = 'Two songs of one kind (Victory and Advancing March) stand side by side; a song picked twice is one. '
    .. 'While an area song is owed, the songs on one member wait: it would push them out.'

-- BRD: a line per target, Area first, then each party slot that is filled or has a pick; a drop-down per song slot.
-- The drop-downs are SONG_W, wide enough for the longest song, and wrap. A member's name sits on the label line.
local function draw_songs(view, pg)
    local m = view.song
    local col, gap, box = S(56), S(6), S(SONG_W)
    for _, set in ipairs(m.sets) do
        local picked = false
        for i = 1, m.slots do picked = picked or set.picks[i] ~= '' end
        if set.key == 'area' or set.present or picked then
            local dim = set.key ~= 'area' and not (set.present and m.pianissimo)
            local name = set.key ~= 'area' and (set.name or 'no one') or nil
            local items = {}
            for i = 1, m.slots do items[i] = { w = box, i = i } end
            local lines = flow(items, pg.lx + col, pg.right, gap)
            -- A name shares the label line, so the picks start on the next one.
            local h = S(ROW_H) + (lines - (name and 0 or 1)) * S(CHIP_LINE)
            local cy = line(pg, set.label, SONG_HELP[set.key] or ('Sung on %s alone, through Pianissimo, whenever they lack one.')
                :format(set.name or 'whoever is in this party slot'), h, dim and P.dim or P.text)
            for _, it in ipairs(items) do
                local icy = cy + (it.line - (name and 0 or 1)) * S(CHIP_LINE)
                slot_pick(('sk3_song_%s_%d'):format(set.key, it.i), ('song.%s_%d'):format(set.key, it.i), set.picks[it.i],
                    m.choices, it.x, icy, box, pg.alpha)
            end
            if name then
                local px = S(SMALL + 0.5)
                kit.text_right(pg.dl, pg.right, cy, kit.fit(name, pg.right - pg.lx - col, kit.fonts.text, px),
                    P.dim, kit.fonts.text, px, pg.alpha)
            end
        end
    end
    local y = pg.y
    if m.pianissimo then
        note(pg, 'Pianissimo: ' .. m.avail, m.ready and P.teal or P.dim)
    else
        note(pg, 'Songs on one member need Pianissimo (Bard 20)', P.dim)
    end
    if kit.over(pg.x, y, pg.w, pg.y - y) then kit.tooltip(SONGS_TIP) end
    if m.pianissimo then
        switch(pg, 'Pianissimo fast casting', 'song.fast', m.fast,
            'Fire Pianissimo before an area song too, for its shorter cast, and cancel it a second into the cast '
                .. 'so the song still lands on everyone near you. None is fired while Nightingale is up (its casts are '
                .. 'short already); with Pianissimo on recast the area song goes without it. A Pianissimo already up '
                .. 'goes to the next area song, or to a member\'s song while that area song can\'t go yet.')
    end
    if m.timed then
        slider(pg, 'Song Duration', 'song.duration', m.duration,
            'Seconds: sing each song again this long after it landed, before it wears (0: only once it\'s gone). '
            .. 'Set it just under your songs\' real duration, gear included; doubled for a song sung under Troubadour. '
            .. 'While Nightingale and Troubadour are both up, every song sung without Troubadour is sung again.', 's')
    end
end

local function draw_geo(view, pg)
    local g = view.geo
    slider(pg, 'Recall past', 'geo.distance', g.distance,
        'Yalms: Full Circle the luopan once who it is on is further than this from it, so it goes down again.', 'y')
    slider(pg, 'Keep after combat', 'geo.linger', g.linger,
        'Seconds a debuff luopan waits once combat is over before Full Circle recalls it: a new battle target in that time keeps it.', 's')
    choice(pg, 'Entrust to', 'geo_entrust', 'geo.entrust', g.entrust, named(g.names),
        'With Entrust on, put the Indi- spell picked on this member (within 20 yalms).')
    choice(pg, 'Entrust spell', 'geo_entrust_spell', 'geo.entrust_spell', g.entrust_spell, named(g.indi),
        'The Indi- spell Entrust puts on that member whenever they lack its aura.')
end

-- What a set's slots show of each rune.
local SHOWS = { element = 'Each rune by the element it adds to your attacks.',
                resist = 'Each rune by the element it resists.', ailments = 'Each rune by the ailments it defends against.' }

local function rune_tip(r)
    return ('%s: adds %s, resists %s, against %s.'):format(r.name, r.element, r.resist, r.ailments)
end

-- A rune for slot `i` of `set`, or None ('').
local function rune_pick(set, i, runes, x, cy, w, alpha)
    local current = set.picks[i]
    if slot_pick(('sk3_rune_%s_%d'):format(set.key, i), ('rune.%s_%d'):format(set.key, i), current, runes, x, cy, w, alpha,
            set.shows, rune_tip) then
        kit.tooltip(shown_pick(current, runes, set.shows) .. '\n' .. SHOWS[set.shows])
    end
end

-- A line per set: Idle, then each ward with its switch and whether it's ready. The rune picks are RUNE_W
-- (the longest ailment list) and wrap under that line.
local function draw_runes(view, pg)
    local r = view.rune
    local gap, box = S(6), S(RUNE_W)
    for _, set in ipairs(r.sets) do
        local items = {}
        for i = 1, r.slots do items[i] = { w = box, i = i } end
        local lines = flow(items, pg.lx, pg.right, gap)
        local help = set.ward and ('Once %s is ready, its runes take the slots, then it fires in combat.'):format(set.ward)
            or 'The runes kept up the rest of the time.'
        local cy = line(pg, set.ward and nil or set.label, help, S(ROW_H) + lines * S(CHIP_LINE))
        if set.ward then
            local on, flipped = kit.switch(set.label .. '##sk3_rune_' .. set.key, pg.lx, cy, set.on, true, pg.alpha)
            kit.tip(help)
            if flipped then act.row(set.ward, on) end
            kit.text_mid(pg.dl, pg.lx + S(kit.SW_W) + S(8), cy, set.label, set.on and P.text or P.dim, kit.fonts.text, S(BODY), pg.alpha)
            readiness(pg, pg.right, cy, set.avail, set.ready)
        end
        for _, it in ipairs(items) do rune_pick(set, it.i, r.runes, it.x, cy + it.line * S(CHIP_LINE), box, pg.alpha) end
    end
end

-- PUP: a drop-down per maneuver slot, by element (None for ''), MANEUVER_W wide so "Thunder" fits. They wrap.
-- Whether they can go sits on the last line when it fits beside them, and on a line of its own when it doesn't.
local function draw_maneuvers(view, pg)
    local m = view.maneuver
    local gap, box, px = S(6), S(MANEUVER_W), S(SMALL + 0.5)
    local items = {}
    for i = 1, #m.picks do items[i] = { w = box, i = i } end
    local lines = flow(items, pg.lx, pg.right, gap)
    local avail_w = kit.measure(m.avail or '', kit.fonts.text, px)
    local last = items[#items]
    local beside = last and pg.right - (last.x + last.w + S(10)) or 0
    local extra = (beside >= avail_w) and 0 or 1
    local cy = line(pg, nil, nil, S(ROW_H) + (lines - 1 + extra) * S(CHIP_LINE))
    for _, it in ipairs(items) do
        local i = it.i
        if slot_pick('sk3_maneuver_' .. i, 'maneuver.slot_' .. i, m.picks[i], m.choices, it.x, cy + (it.line - 1) * S(CHIP_LINE),
                box, pg.alpha) then
            kit.tooltip('The same element in two slots keeps two up.')
        end
    end
    readiness(pg, pg.right, cy + (extra == 0 and last.line - 1 or lines) * S(CHIP_LINE), m.avail, m.ready)
end

-- Each tracked player with its Untrack button (one who joined your party or alliance too), then Track for your
-- target.
local function draw_track(view, pg)
    local px = S(BODY)
    for _, list in ipairs({ view.party, view.alliance }) do
        for _, p in ipairs(list) do
            if p.tracked then
                local cy = line(pg, nil, nil)
                local bw = kit.button_width('Untrack')
                if kit.button('Untrack##sk3_untrack_' .. p.name, pg.right - bw, cy, 'Untrack', 'ghost', true, pg.alpha) then
                    act.untrack(p.name)
                end
                local s = ('%s %s'):format(p.tag, p.name) .. (JOINED[p.kind] or p.job and ('  ' .. p.job) or '')
                if p.shared and not JOINED[p.kind] then s = s .. '  (from ' .. p.shared .. ')' end
                local room = pg.right - bw - S(12) - pg.lx
                kit.text_mid(pg.dl, pg.lx, cy, kit.fit(s, room, kit.fonts.text, px), p.away and P.dim or P.text, kit.fonts.text, px, pg.alpha)
                local where = p.away and (p.kind == 'tracked' and 'Out of range.' or 'In another zone.') or nil
                local from = p.shared and ('Tracked while %s\'s session lists them; Untrack keeps them off until tracked again.'):format(p.shared)
                local help = where and from and (where .. '\n' .. from) or where or from
                if help and kit.over(pg.lx, cy - S(ROW_H) / 2, room, S(ROW_H)) then kit.tooltip(help) end
            end
        end
    end
    local t = view.track.target
    if t then
        local cy = line(pg, nil, nil)
        if kit.button(('Track %s##sk3_track'):format(t), pg.lx, cy, 'Track ' .. t, 'accent', true, pg.alpha) then act.track(t) end
        kit.tip('Heal, clear, raise and buff them too, with what reaches outside the party. This session only.')
    else
        note(pg, view.session and ('Target a player outside the alliance in %s\'s game to track them there.'):format(view.session)
            or 'Target a player outside your alliance to track them, or /sk3 track Name.')
    end
end

local function has_name(names, name)
    for _, n in ipairs(names) do if n == name then return true end end
    return false
end

-- A profile's line in the list: lit when it's the one in use. Returns clicked.
local function profile_item(pg, id, name, on, help)
    local ih = S(28)
    local x, y, w = pg.x + S(4), pg.y, pg.w - S(8)
    pg.y = y + ih
    local hovered, clicked = kit.hit(id, x, y, w, ih)
    kit.tip(help)
    local t = kit.ease(id, on and 1 or 0, 20)
    if t > 0.01 then
        kit.fill(pg.dl, x, y, w, ih, P.accent_bg, S(3), 0.9 * t)
        kit.fill(pg.dl, x, y + S(5), S(2), ih - S(10), P.accent, S(1), t)
    end
    if hovered and not on then kit.fill(pg.dl, x, y, w, ih, P.hover, S(3), 0.8) end
    kit.text_mid(pg.dl, pg.lx, y + ih / 2, name, on and P.white or P.text, kit.fonts.text, S(BODY))
    return clicked
end

-- The name to save under, Save / Save as / New / Delete, then every profile: a click loads it (Default, the working
-- copy as it was before one was loaded).
local function draw_profiles(view, pg)
    local p = view.profiles
    local active = p.active or ''
    local state = profile_names[view.session or '']
    if not state then state = { typed = { '' } }; profile_names[view.session or ''] = state end
    local profile_name = state.typed
    if active ~= state.shown then profile_name[1], state.shown = active, active end
    local cy = line(pg, 'Name', 'A name for Save or Save as. Each job pair has its own profiles.')
    local fw = S(260)
    kit.input('##sk3_profile_name', pg.right - fw, cy, fw, profile_name, 64, 'Name to save under')
    local typed = profile_name[1]:match('^%s*(.-)%s*$')
    local buttons = {
        { 'Save', 'save', 'accent', 'Save the settings as they are now under this name. With a profile loaded and the name changed, '
            .. 'rename that profile instead. Never over another profile: Save as replaces one.' },
        { 'Save as', 'save_as', 'ghost', 'Save the settings as they are now under this name, over any profile already named so.' },
        { 'New', 'new', 'ghost', 'Every setting back to its default, on Default. Saved profiles are kept.' },
    }
    if p.active then buttons[#buttons + 1] = { 'Delete', 'delete', 'danger', ('Delete %s, and go back to Default.'):format(p.active) } end
    local by = line(pg, nil, nil, S(ROW_H) + S(4))
    local bx = pg.right - (#buttons - 1) * S(6)
    for _, b in ipairs(buttons) do bx = bx - kit.button_width(b[1]) end
    for _, b in ipairs(buttons) do
        local clicked, bw = kit.button(b[1] .. '##sk3_profile_' .. b[2], bx, by, b[1], b[3], true, pg.alpha)
        kit.tip(b[4])
        if clicked then
            if b[2] == 'save' then act.save_profile(typed)
            elseif b[2] == 'save_as' then act.save_profile(typed, true)
            elseif b[2] == 'new' then
                act.new_profile()
                profile_name[1] = ''
            else act.delete_profile(p.active) end
        end
        bx = bx + bw + S(6)
    end
    if typed ~= p.active and has_name(p.names, typed) then note(pg, ('%s exists: Save as replaces it.'):format(typed), P.amber) end
    subheader(pg, 'SAVED')
    if profile_item(pg, 'Default##sk3_profile_default', 'Default', p.active == nil,
            'The working copy: your settings as they were before a profile was loaded.') then
        act.profile(nil)
    end
    -- (drawn on the draw list, a name with '##' in it is shown whole)
    for i, name in ipairs(p.names) do
        if profile_item(pg, '##sk3_profile_' .. i, name, name == p.active) then act.profile(name) end
    end
    pg.y = pg.y + S(6)
    note(pg, 'Changes save to the settings in use; to a profile only with Save.', P.faint)
end

local function draw_recent(view, pg)
    if #view.recent == 0 then return note(pg, 'Nothing sent yet.') end
    local px = S(SMALL + 0.5)
    for _, r in ipairs(view.recent) do
        local cy = line(pg, nil, nil, S(24))
        kit.text_right(pg.dl, pg.lx + S(30), cy, ('%ds'):format(r.age), P.faint, kit.fonts.text, px, pg.alpha)
        local tx = pg.lx + S(40)
        kit.text_mid(pg.dl, tx, cy, r.text, P.text, kit.fonts.text, px, pg.alpha)
        local wx = tx + kit.measure(r.text, kit.fonts.text, px) + S(10)
        if pg.right - wx > S(30) then
            kit.text_mid(pg.dl, wx, cy, kit.fit(r.why, pg.right - wx, kit.fonts.text, px), P.dim, kit.fonts.text, px, pg.alpha)
        end
    end
end

-- Sidekick Settings' size, % of the size for the screen: view.ui.scale, held to its slider's range.
local function ui_scale(ui) return math.min(math.max(math.floor(tonumber(ui and ui.scale) or 100), 50), 200) end

-- Another session's shows only what it sent: its HUD is its own.
local function draw_ui(view, pg)
    if view.session then return draw_recent(view, pg) end
    subheader(pg, 'HUD')
    for _, l in ipairs(UI_SLIDERS) do
        slider(pg, l[1], 'ui.' .. l[2], view.ui[l[2]], l[5], l[6], { l[3], l[4] })
    end
    switch(pg, 'Lock position', 'ui.locked', view.ui.locked == true,
        'Keep the HUD and the widget where they are: dragging them no longer moves them.')
    switch(pg, 'Widget', 'ui.widget', view.ui.widget == true,
        'One row of its own: each character\'s name (yours, then each other Sidekick session\'s), its Start/Stop and its '
        .. 'Settings. Right-click a name to load a profile. Up with the HUD closed too. Also /sk3 widget.')
    slider(pg, 'Widget size', 'ui.widget_size', widget_size(view.ui), 'Pixels: the widget\'s text and icons\' height.',
        'px', WIDGET_SIZES)
    subheader(pg, 'Sidekick Settings')
    slider(pg, 'Size', 'ui.scale', ui_scale(view.ui),
        'This window\'s size, % of the size that suits your screen. Taken up once the slider is let go.', '%', { 50, 200 })
    subheader(pg, 'LOG')
    draw_recent(view, pg)
    subheader(pg, 'CLIENT')
    switch(pg, 'Japanese client', 'japanese', view.japanese,
        'Send spell, ability and item names in Japanese, on every job.')
end

-- Rows ------------------------------------------------------------------------------

local HOLD_TIP = 'Wait while a modifier picked here can\'t go with the spell (on recast, too few charges, the wrong Arts, '
    .. 'Accession unable to spread it, or short of MP for it); otherwise the spell goes without it.'

-- One row per settings key: its name (and how many you carry), ready or why not, its switch; under them, when it has
-- any, its pick, its targets (ME, P1-P5, T1...; B0-B5 and C0-C5 each on a line of their own) and its modifiers fired
-- before its spell (Pen, Cel, Acc, Emb...), then Hold: wait for them.
local function family_row(pg, sid, r)
    local id = sid .. '_' .. r.key
    local n = r.count or r.tools
    local items = {}
    if r.choices then items[#items + 1] = { w = S(PICK_W), kind = 'pick' } end
    for _, t in ipairs(r.targets or {}) do items[#items + 1] = { w = S(CHIP_W), kind = 'target', t = t, wrap = t.wrap } end
    for i, m in ipairs(r.mods or {}) do items[#items + 1] = { w = kit.chip_width(m.label), kind = 'mod', m = m, pre = i == 1 and S(8) or nil } end
    if r.mods then items[#items + 1] = { w = kit.chip_width('Hold'), kind = 'hold' } end
    local lines = #items > 0 and flow(items, pg.lx + S(14), pg.right, S(4)) or 0
    local cy = line(pg, nil, nil, S(ROW_H) + lines * S(CHIP_LINE) + (lines > 0 and S(4) or 0))
    -- A debuff nothing ticked removes is greyed out, its switch kept as it is.
    local usable = r.usable ~= false
    local alpha = usable and pg.alpha or pg.alpha * 0.45

    -- An item shows how many you carry, ninjutsu their tools; ### keeps its id while the count changes.
    local sx = pg.right - S(kit.SW_W)
    local on, flipped = kit.switch(n and ('%s (%d)###%s'):format(r.label, n, id) or r.label .. '##' .. id, sx, cy, r.on, usable, alpha)
    if flipped then (r.debuff and act.debuff or act.row)(r.key, on) end
    local px = S(SMALL + 0.5)
    local aw = kit.measure(r.avail, kit.fonts.text, px)
    local ax = sx - S(12) - aw
    readiness(pg, sx - S(12), cy, r.avail, r.ready)
    if r.action and kit.over(ax, cy - S(10), aw, S(20)) then
        kit.tooltip(r.debuff and r.action ~= '' and 'Removed by ' .. r.action or r.action)
    end
    local label = n and ('%s (%d)'):format(r.label, n) or r.label
    kit.text_mid(pg.dl, pg.lx, cy, kit.fit(label, ax - S(12) - pg.lx, kit.fonts.text, S(BODY)), r.on and usable and P.text or P.dim,
        kit.fonts.text, S(BODY), alpha)

    local any = false
    for _, m in ipairs(r.mods or {}) do any = any or m.on end
    local top = cy + S(ROW_H) / 2 + S(CHIP_LINE) / 2 - S(2)  -- the first line of chips' middle
    for _, it in ipairs(items) do
        local icy = top + (it.line - 1) * S(CHIP_LINE)
        if it.kind == 'pick' then
            kit.dropdown('##pick_' .. id, it.x, icy, it.w, r.choice, true, pg.alpha, function ()
                for _, c in ipairs(r.choices) do
                    if imgui.Selectable(c.label, c.name == r.pick) then act.pick(r.key, c.name) end
                end
            end)
        elseif it.kind == 'target' then
            -- An empty slot can't be picked, but a picked one can still be cleared.
            local t = it.t
            local empty = not t.present and not t.on
            if kit.chip(t.label .. '##' .. id .. t.slot, it.x, icy, it.w, t.label, empty and 'empty' or t.on and 'on' or 'off',
                    not empty, pg.alpha) then
                act.target(r.key, t.slot, not t.on)
            end
            kit.tip(t.name or 'empty slot')
        elseif it.kind == 'mod' then
            local m = it.m
            if kit.chip(m.label .. '##' .. id .. '_mod_' .. m.name, it.x, icy, it.w, m.label, m.on and 'on' or 'off', true, pg.alpha) then
                act.mod(r.key, m.name, not m.on)
            end
            kit.tip(m.note and ('%s first: %s'):format(m.name, m.note) or m.name)
        else
            -- With no modifier on, it waits for nothing: an outline, but kept and still clickable.
            if kit.chip('Hold##' .. id .. '_hold', it.x, icy, it.w, 'Hold', not any and 'empty' or r.hold and 'held' or 'off', true, pg.alpha) then
                act.hold(r.key, not r.hold)
            end
            kit.tip(HOLD_TIP .. (any and '' or '\nNo modifier is on here: it waits for nothing.'))
        end
    end
end

local REMOVER_TIP = 'Untick to never use it: the debuffs only it removes are greyed out below.'

-- Debuff removal's spells and abilities, a chip each to tick.
local function remover_chips(pg, sid, removers)
    local items = {}
    for i, r in ipairs(removers) do items[i] = { w = kit.chip_width(r.label) } end
    local lines = flow(items, pg.lx, pg.right, S(4))
    local cy = line(pg, nil, nil, S(ROW_H) + (lines - 1) * S(CHIP_LINE))
    for i, r in ipairs(removers) do
        local it = items[i]
        if kit.chip(r.label .. '##' .. sid .. '_with_' .. r.key, it.x, cy + (it.line - 1) * S(CHIP_LINE), it.w, r.label,
                r.on and 'on' or 'off', true, pg.alpha) then
            act.row(r.key, not r.on)
        end
        kit.tip(('%s: %s\n%s'):format(r.action or r.label, r.avail, REMOVER_TIP))
    end
end

-- Spells and abilities, then items (rows with a count) under a heading of their own. Debuff removal's spells and
-- abilities are chips to tick, then its debuffs.
local function section_rows(pg, s, has_body)
    local removers, acts, items = {}, {}, {}
    for _, r in ipairs(s.rows) do table.insert(r.remover and removers or r.count and items or acts, r) end
    if #removers > 0 then
        subheader(pg, 'REMOVE WITH')
        remover_chips(pg, s.id, removers)
    end
    if #acts > 0 and (has_body or acts[1].debuff) then subheader(pg, acts[1].debuff and 'DEBUFFS' or 'ACTIONS') end
    for _, r in ipairs(acts) do family_row(pg, s.id, r) end
    if #items > 0 then
        subheader(pg, 'ITEMS')
        for _, r in ipairs(items) do family_row(pg, s.id, r) end
    end
end

-- Sidekick Settings -----------------------------------------------------------------------

local SWITCH_HELP = {
    follow = 'Follow the leader once they are further away than the distance.',
    heal = 'Heal the party with the rows that are on.',
    revive = 'Raise fallen members with the rows that are on.',
    wake = 'Wake a sleeping member with a cure or waltz that is on under Heal; an area one for two or more.',
    remove = 'Remove the debuffs that are on, with the spells, abilities and items ticked.',
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

-- A section's heading: a chevron and its title (a click folds it), a line, its switch at the end. Returns folded.
local function heading(pane, pg, s)
    local dl, cy = pg.dl, pg.y + S(HEAD_H) / 2
    local line_end = pg.right
    if s.on ~= nil then
        local on, flipped = kit.switch(s.title .. '##sk3_on_' .. s.id, line_end - S(kit.SW_W), cy, s.on, true)
        kit.tip(SWITCH_HELP[s.id])
        if flipped then act.section(s.id, on) end
        line_end = line_end - S(kit.SW_W) - S(12)
    end
    local font, px, spacing = kit.fonts.semi_italic, S(SMALL), math.max(1, S(1.2))
    local title = string.upper(s.title)
    local tw = kit.text_spaced(nil, 0, 0, title, nil, font, px, spacing)
    local hovered, clicked = kit.hit('##sk3_fold_' .. s.id, pg.x + S(2), cy - S(12), S(LEFT) - S(2) + tw + S(8), S(24))
    kit.tip(SWITCH_HELP[s.id])
    if clicked then pane.folded[s.id] = not pane.folded[s.id] or nil end
    local folded = pane.folded[s.id] == true
    kit.icon(dl, folded and 'right' or 'down', pg.x + S(GUTTER), cy, S(11), hovered and P.teal or P.faint)
    local base = s.on == false and kit.mix(P.teal, P.dim, 0.55) or P.teal
    kit.text_spaced(dl, pg.lx, cy, title, kit.mix(base, P.white, hovered and 0.25 or 0), font, px, spacing)
    local tx = pg.lx + tw + S(10)
    if line_end > tx then kit.line(dl, tx, cy, line_end, cy, P.line) end
    pg.y = pg.y + S(HEAD_H) + S(2)
    return folded
end

-- Its heading (none when the page says it already: Profiles, UI / Log), its settings, then its rows; switched off,
-- they're drawn faded, still settable.
local function draw_section(view, pane, pg, s, page)
    if not (s.on == nil and s.title == page) and heading(pane, pg, s) then return end
    pg.alpha = s.on == false and 0.55 or 1
    local body = BODIES[s.id]
    if body then body(view, pg) end
    if s.rows then section_rows(pg, s, body ~= nil) end
    pg.alpha = 1
    pg.y = pg.y + S(14)
end

-- The pages: one per `header`, in the order the sections come. `on`: a switch of one of its sections is.
local function pages_of(view)
    local pages, of = {}, {}
    for _, s in ipairs(view.sections) do
        local p = of[s.header]
        if not p then
            p = { name = s.header, sections = {} }
            of[s.header], pages[#pages + 1] = p, p
        end
        p.sections[#p.sections + 1] = s
        if s.on ~= nil then p.switches, p.on = true, p.on or s.on end
    end
    return pages
end

local function find(pages, name)
    for _, p in ipairs(pages) do if p.name == name then return p end end
end

-- The page shown first: the first of the list's top, not its foot.
local function first(pages)
    for _, p in ipairs(pages) do if not FOOT[p.name] then return p.name end end
    return pages[1] and pages[1].name
end

-- A page's line in the list: a dot, teal while one of its switches is on (a ring when all are off), its name and
-- `tag` (the profile loaded). A click shows it. Returns its height.
local function nav_item(pane, page, x, y, w, tag)
    local dl, ih = imgui.GetWindowDrawList(), S(NAV_H)
    local hovered, clicked = kit.hit('##sk3_page_' .. page.name, x, y, w, ih)
    if clicked then pane.page = page.name end
    local active = pane.page == page.name
    local t = kit.ease('nav.' .. page.name, active and 1 or 0, 20)
    if t > 0.01 then
        kit.fill(dl, x, y, w, ih, P.accent_bg, 0, 0.9 * t)
        kit.fill(dl, x, y, S(2), ih, P.accent, 0, t)
    end
    if hovered and not active then kit.fill(dl, x, y, w, ih, P.hover, 0, 0.7) end
    local cy, dx = y + ih / 2, x + S(PAD) + S(4)
    if page.switches and page.on then kit.circle(dl, dx, cy, S(3.5), P.teal)
    elseif page.switches then kit.ring(dl, dx, cy, S(3.5), P.faint) end
    if hovered and page.switches and not page.on then kit.tooltip('Every switch here is off.') end
    local nx, px = x + S(PAD) + S(16), S(BODY + 0.5)
    kit.text_mid(dl, nx, cy, page.name, active and P.white or P.text, kit.fonts.text, px)
    if tag then
        local room = x + w - S(PAD) - (nx + kit.measure(page.name, kit.fonts.text, px) + S(8))
        if room > S(20) then
            kit.text_right(dl, x + w - S(PAD), cy, kit.fit(tag, room, kit.fonts.text, S(SMALL)), P.faint, kit.fonts.text, S(SMALL))
        end
    end
    return ih
end

-- Whose settings these are (Sidekick Settings, or the session's name), its job and whether it runs; then its pages, and
-- Profiles and UI / Log at the foot.
local function draw_sidebar(view, pane, pages, name, x, y, w, h)
    local dl, pad = imgui.GetWindowDrawList(), S(PAD)
    local st = view.status
    local title_px, small = S(BODY), S(SMALL)
    kit.text_mid(dl, x + pad, y + S(24), kit.fit(name or 'Sidekick Settings', w - pad * 2, kit.fonts.semi, title_px), P.white, kit.fonts.semi, title_px)
    kit.text_mid(dl, x + pad, y + S(46), kit.fit(view.job, w - pad * 2, kit.fonts.text, small), P.dim, kit.fonts.text, small)
    kit.circle(dl, x + pad + S(3), y + S(65), S(3), st.running and P.teal or P.faint)
    kit.text_mid(dl, x + pad + S(12), y + S(65), st.state, st.running and P.teal or P.dim, kit.fonts.text, small)
    if kit.over(x, y, w, S(78)) then
        kit.tooltip(name and 'Changes here are sent to that session, which applies them within a second or so.' or status_tip(view))
    end
    local ny = y + S(86)
    kit.line(dl, x + pad, ny - S(6), x + w - pad, ny - S(6), P.border, 0.8)
    local foot = {}
    for _, p in ipairs(pages) do
        if FOOT[p.name] then foot[#foot + 1] = p else ny = ny + nav_item(pane, p, x, ny + S(2), w) end
    end
    if #foot == 0 then return end
    local fy = y + h - S(10) - #foot * S(NAV_H)
    kit.line(dl, x + pad, fy - S(26), x + w - pad, fy - S(26), P.border, 0.8)
    kit.text_mid(dl, x + pad, fy - S(12), 'SETUP', P.faint, kit.fonts.semi, S(SMALL - 1.5))
    for _, p in ipairs(foot) do
        fy = fy + nav_item(pane, p, x, fy, w, p.name == 'Profiles' and view.profiles.active or nil)
    end
end

-- A page's title line: its name, `note` after it, the close button (open[1] = false) at the right, a line under.
local function title_bar(title, note_, x, y, w, open)
    local dl = imgui.GetWindowDrawList()
    local cy = y + S(TITLE_H) / 2
    local font, px = kit.fonts.semi, S(BODY)
    kit.text_mid(dl, x + S(LEFT), cy, title, P.white, font, px)
    local box = S(21)
    local cx = x + w - S(PAD) - box / 2
    if note_ then
        local nx = x + S(LEFT) + kit.measure(title, font, px) + S(10)
        local room = cx - box / 2 - S(8) - nx
        if room > S(30) then kit.text_mid(dl, nx, cy, kit.fit(note_, room, kit.fonts.text, S(SMALL)), P.faint, kit.fonts.text, S(SMALL)) end
    end
    if close_mark('##sk3_settings_close', cx, cy, box) then open[1] = false end
    kit.tip('Close')
    kit.line(dl, x, y + S(TITLE_H), x + w, y + S(TITLE_H), P.border)
end

-- The page's sections, scrolling under its title. A Lua error inside still ends the child, then is raised.
local function draw_page(view, pane, page, x, y, w, h, open)
    title_bar(page.name, page.name == 'Profiles' and view.profiles.active and ('loaded: ' .. view.profiles.active) or nil, x, y, w, open)
    imgui.SetCursorScreenPos({ x, y + S(TITLE_H) + 1 })
    local ok, err = true, nil
    if kit.child('##sk3_pane_' .. page.name, w, h - S(TITLE_H) - 1) then
        ok, err = pcall(function ()
            local cx, cy = imgui.GetCursorScreenPos()
            local pg = { dl = imgui.GetWindowDrawList(), x = cx, w = w, y = cy + S(10), lx = cx + S(LEFT), right = cx + w - S(PAD), alpha = 1 }
            for _, s in ipairs(page.sections) do draw_section(view, pane, pg, s, page.name) end
            imgui.SetCursorScreenPos({ cx, pg.y })
            imgui.Dummy({ 1, S(10) })  -- what's drawn has no item: this one tells the child how far it scrolls
        end)
    end
    imgui.EndChild()
    if not ok then error(err, 0) end
end

-- A Sidekick Settings window's inside, from `view`: `key` and `name` are '' and nil for yours, the session's name for
-- another's.
local function draw_settings(view, key, name, x, y, side, pw, ph, open)
    local pages = pages_of(view)
    local pane = panes[key]
    if not pane then pane = { folded = {} }; panes[key] = pane end
    if not find(pages, pane.page) then pane.page = first(pages) end
    draw_sidebar(view, pane, pages, name, x, y, side, ph)
    local page = find(pages, pane.page)
    if page then draw_page(view, pane, page, x + side + 1, y, pw - side - 1, ph, open) end
end

-- Windows ---------------------------------------------------------------------------

local SETTINGS_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoNavInputs  -- NoNavInputs: Tab is the game's (target cycling), not ImGui's
local SETTINGS_COLOURS = {
    { ImGuiCol_ChildBg, { 0, 0, 0, 0 } }, { ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 } },
    { ImGuiCol_ScrollbarGrab, kit.rgba('#3A4158') }, { ImGuiCol_ScrollbarGrabHovered, kit.rgba('#4A5270') },
    { ImGuiCol_ScrollbarGrabActive, kit.rgba(P.accent_lo) },
}

-- A Sidekick Settings window, the `index`th open (each starts a little further down and right): ImGui draws none of it, the
-- panel and its sidebar are drawn here, then `body(x, y, side, pw, ph)` inside. Returns the error the body raised.
local function settings_shell(label, open, index, body)
    local m, side = S(MARGIN), S(SIDE_W)
    local pw, ph = side + S(PAGE_W), S(WIN_H)
    local sw, sh = kit.screen()
    imgui.SetNextWindowPos({ sw / 2 + index * S(36), sh / 2 + index * S(36) }, ImGuiCond_FirstUseEver, { 0.5, 0.5 })
    imgui.SetNextWindowSize({ pw + m * 2, ph + m * 2 }, ImGuiCond_Always)
    for _, c in ipairs(SETTINGS_COLOURS) do imgui.PushStyleColor(c[1], c[2]) end
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, S(6))
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, S(3))
    local ok, err = true, nil
    if imgui.Begin(label, open, SETTINGS_FLAGS) then
        local x, y = imgui.GetCursorScreenPos()
        x, y = x + m, y + m
        local dl = imgui.GetWindowDrawList()
        kit.fill(dl, x - 1, y, pw + 2, ph + 2, '#000000', S(6), 0.35)  -- its shadow
        kit.fill(dl, x, y, pw, ph, P.bg, S(5))
        kit.fill(dl, x, y, side, ph, P.side, S(5), 1, kit.LEFT_CORNERS)
        kit.line(dl, x + side, y, x + side, y + ph, P.border)
        kit.outline(dl, x, y, pw, ph, P.border, S(5))
        ok, err = pcall(body, x, y, side, pw, ph)
    end
    imgui.End()
    imgui.PopStyleVar(5)
    imgui.PopStyleColor(#SETTINGS_COLOURS)
    if not ok then return err end
end

-- The HUD or the widget: a window ImGui draws nothing of, `draw(view)` inside under pcall
-- (Begin, the body, End); returns the error the body raised.
local function panel(title, flags, draw, view)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    local shown = imgui.Begin(title, true, flags + (view.ui.locked and ImGuiWindowFlags_NoMove or 0))
    imgui.PopStyleVar(2)
    local ok, err = true, nil
    if shown then ok, err = pcall(draw, view) end
    imgui.End()  -- ImGui keeps where it was dragged, in imgui.ini
    if not ok then return err end
end

local function settings_window(view)
    local open = { true }
    local err = settings_shell('Sidekick Settings', open, 0, function (x, y, side, pw, ph)
        draw_settings(view, '', nil, x, y, side, pw, ph, open)
    end)
    if not open[1] then settings_open = false end
    return err
end

-- Another session's Sidekick Settings, from the view it published, its changes sent to it; until its first view comes, or
-- from a session running other code, a line saying so.
local function remote_window(r, index)
    local open = { true }
    local mine = act
    local err = settings_shell(('Sidekick Settings: %s###sk3_settings_%s'):format(r.name, r.name), open, index, function (x, y, side, pw, ph)
        act = mine.remote(r.name)
        if r.view and not r.other then return draw_settings(r.view, r.name, r.name, x, y, side, pw, ph, open) end
        local dl = imgui.GetWindowDrawList()
        kit.text_mid(dl, x + S(PAD), y + S(24), kit.fit(r.name, side - S(PAD) * 2, kit.fonts.semi, S(BODY + 2)), P.white, kit.fonts.semi, S(BODY + 2))
        title_bar('Sidekick Settings', nil, x + side + 1, y, pw - side - 1, open)
        local pg = { dl = dl, x = x + side + 1, w = pw - side - 1, y = y + S(TITLE_H) + S(14), lx = x + side + 1 + S(LEFT),
                     right = x + pw - S(PAD), alpha = 1 }
        note(pg, r.other and ('%s runs another version of Sidekick3: /addon reload sidekick3 there.'):format(r.name)
            or ('Waiting for %s\'s session...'):format(r.name))
    end)
    act = mine
    if not (open[1] and not err) then act.watch(r.name, false) end  -- a view that won't draw isn't drawn again
    return err
end

-- Once, at load, before any frame: Segoe UI, which ImGui 1.81 (Ashita 4.16) takes only then.
function window.load() kit.bake() end

-- One frame. A Lua error raised while drawing is raised again after the windows
-- are ended, so ImGui stays balanced and Sidekick reports it.
function window.render(view, act_)
    act = act_
    if not imgui.IsAnyItemActive() then user_scale = ui_scale(view.ui) / 100 end  -- not mid-drag: the window would move under it
    kit.frame(user_scale)
    local open = view.ui.open ~= false
    if hud_open and not open and not view.ui.widget then settings_open = false end  -- the widget's cogs keep them
    hud_open = open
    local err
    if open then
        kit.prefix = 'hud|'
        err = panel('Sidekick3', HUD_FLAGS, draw_hud, view)
    end
    if view.ui.widget then
        kit.prefix = 'widget|'
        err = panel('SK Widget', WIDGET_FLAGS, draw_widget, view) or err
    end
    kit.prefix = ''
    if settings_open then err = settings_window(view) or err end
    if open or view.ui.widget then  -- the widget's cogs open them too
        for i, r in ipairs(view.remote or {}) do
            kit.prefix = r.name .. '|'
            err = remote_window(r, i) or err
        end
        kit.prefix = ''
    end
    kit.tooltips()
    if err then error(err, 0) end
end

return window
