--[[
    The standard Sidekick3 UI, and the reference: it uses only the `view` and
    `act` every UI is given (ui/README.md), so ui/custom.lua can replace it.
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
    buttons start and stop that session and open its own SK Settings, drawn here
    from its view.
    The widget (`ui.widget`, `/sk3 widget`) is v2's floating one: the profile loaded
    and the job, then Start/Stop, the state, Settings and Track for your target. It
    shows with the HUD closed too (`view.ui.open` false), as v2's did.

    Ashita's binding: widget values are one-element tables ({ 'text' }), and
    SetTooltip takes a printf format (kit.tooltip doubles any '%'). Draw-list text
    is drawn as is.
]]--

local imgui = require('imgui')
local kit = require('ui.kit')

local window = {}

local P, S = kit.P, kit.S
local BODY, SMALL = kit.BODY, kit.SMALL

-- { label, key, min, max, help, unit } for view.ui: sizes in pixels, the opacity in %.
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
    { 'Background opacity', 'opacity', 0, 100,
        'How solid the panel behind the bars is while the mouse is over it, %. It fades out until then.', '%' },
}

local JOINED = { party = '  (in your party)', alliance = '  (in your alliance)' }  -- a tracked player's note

local act                    -- this frame's actions (another session's, while drawing its SK Settings)
local settings_open = false  -- SK Settings shown; this session only
local hud_open = true        -- last frame's view.ui.open: closing the HUD (/sk3) closes SK Settings with it
local profile_names = {}     -- per SK Settings window ('' for yours, else the session's name), this session only:
                             -- { typed = { name }, shown }, the name filled in again when the profile loaded changes
local panes = {}             -- per SK Settings window, as profile_names: { page, folded = { [section id] = true } }
local user_scale = 1         -- SK Settings' size (view.ui.scale), taken up while nothing is held

-- HUD -----------------------------------------------------------------------------

local HUD_PAD, BAR_GAP, ROUND = 8, 3, 4  -- the panel's padding, between bars, the bars' corners (pixels)
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

-- A sunken track at (x, y), w by h, `f` (0 to 1) of it filled in `color`, edged in `edge`.
local function track(dl, x, y, w, h, f, color, alpha, edge)
    local r = math.min(ROUND, math.floor(h / 2))
    kit.fill(dl, x, y, w, h, P.well, r)
    local fw = math.floor(w * f + 0.5)
    if fw > 0 then kit.fill(dl, x, y, fw, h, color, math.min(r, fw / 2), alpha) end
    kit.outline(dl, x, y, w, h, edge or P.well_edge, r)
end

-- A bar: `pct` of its track filled (eased, by `id`).
local function bar(dl, id, x, y, w, h, pct, color, alpha, edge)
    track(dl, x, y, w, h, kit.ease(id, math.min(math.max(pct, 0), 100) / 100, 12), color, alpha, edge)
end

local TIER, TIERS = 1000, 3  -- TP: a weapon skill's worth, and how many stand

-- The TP bar: a track per 1000 TP side by side, each filling once the one before is full (eased, by `id`); the one
-- still filling is drawn faint, as Floaties draws it.
local function tp_bar(dl, id, x, y, w, h, tp, alpha)
    local t = kit.ease(id, math.min(math.max(tp, 0), TIER * TIERS) / TIER, 12)  -- in tiers
    local tw = (w - (TIERS - 1) * BAR_GAP) / TIERS
    for i = 1, TIERS do
        local f = math.min(math.max(t - (i - 1), 0), 1)
        local tx = math.floor(x + (i - 1) * (tw + BAR_GAP) + 0.5)
        track(dl, tx, y, math.floor(x + i * tw + (i - 1) * BAR_GAP + 0.5) - tx, h, f, P.tp, (f < 1 and 0.5 or 1) * alpha)
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
        settings_open = false
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

-- A member's card at (x, y): the HP bar over the MP bar over the TP bar, the name on the first and the tag on the
-- second, the % of each (TP's number) only in its tooltip. A tracked player's MP and TP can't be read: their bars stay
-- empty. Critical HP edges the bar and turns the name rose; MP under the Recover line, the tag. Away, the bars fade
-- and the text greys. `id` keeps the bars' eased fills apart.
local function card(dl, ui, p, x, y, id)
    local fx, mp_top = x + HUD_PAD, y + ui.hp_height + BAR_GAP
    local fade = p.away and 0.45 or 1
    local critical = p.hp == 'critical' and not p.away
    bar(dl, 'hp.' .. id, fx, y, ui.hp_width, ui.hp_height, p.hpp, P.hp, fade, critical and P.rose or nil)
    bar(dl, 'mp.' .. id, fx, mp_top, ui.mp_width, ui.mp_height, p.mpp, P.mp, fade)
    tp_bar(dl, 'tp.' .. id, fx, mp_top + ui.mp_height + BAR_GAP, ui.tp_width, ui.tp_height, p.tp, fade)
    local font = kit.fonts.semi
    local _, nh = kit.measure(p.name, font, ui.name_size)
    kit.halo(dl, fx + 6, y + ui.hp_height - nh, p.name, p.away and P.dim or critical and P.rose or P.white, font, ui.name_size)
    local _, th = kit.measure(p.tag, font, ui.text_size)
    kit.halo(dl, fx + 6, mp_top + (ui.mp_height - th) / 2, p.tag,
        p.away and P.dim or p.mp == 'low' and P.rose or P.text2, font, ui.text_size)
end

-- An alliance member's row, its bar's top at `top`: a thin HP bar (the MP bar's height) with the tag and name on
-- it, its HP % only in its tooltip.
local function ally_row(dl, ui, p, x, top)
    local fx = x + HUD_PAD
    local critical = p.hp == 'critical' and not p.away
    bar(dl, 'ally.' .. p.name, fx, top, ui.hp_width, ui.mp_height, p.hpp, P.hp, p.away and 0.45 or 1, critical and P.rose or nil)
    local label = p.tag .. ' ' .. p.name
    local _, h = kit.measure(label, kit.fonts.semi, ui.text_size)
    kit.halo(dl, fx + 6, top + (ui.mp_height - h) / 2, label, p.away and P.dim or critical and P.rose or P.white,
        kit.fonts.semi, ui.text_size)
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
    -- Last frame's window rect is what IsWindowHovered reads. The bars stay solid.
    local chrome = kit.ease('chrome', imgui.IsWindowHovered() and 1 or 0)
    local opacity = ui.opacity / 100 * chrome
    kit.fill(dl, x0, y0, pw, ph, P.bg, 6, opacity)
    kit.outline(dl, x0, y0, pw, ph, P.border, 6, opacity)
    title_row(dl, view, ui.text_size, x0, y0, pw, th, s, chrome)
    for i, c in ipairs(cards) do
        local p, y = c.p, y0 + th + (i - 1) * (ch + ui.gap)
        card(dl, ui, p, x0, y, c.id)
        local on_icon = (p.kind == 'self' or p.session) and card_icons(view, ui, p, x0, y, s)
        imgui.SetCursorScreenPos({ x0 + HUD_PAD, y })
        imgui.Dummy({ pw - 2 * HUD_PAD, ch })
        if not on_icon then kit.tip(c.pet and pet_tip(view.pet) or member_tip(p)) end
        draw_labels(labels_at(view, c), ui.text_size, x0 + pw, y + ch / 2)
    end
    for j, p in ipairs(view.alliance) do
        local top = y0 + rows[j]
        ally_row(dl, ui, p, x0, top)
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
local STATES = { 'Stopped', 'Running', 'Asleep' }

-- The state alone, so the widget keeps its width and Track its place: the rest,
-- what it does or why it waits, is the tooltip, as the HUD title's.
local function short_status(view)
    local s = view.status
    if not s.running then return 'Stopped', P.dim end
    if view.afk.asleep then return 'Asleep', P.dim end
    return 'Running', s.dim and P.dim or P.teal
end

-- On a panel of its own, sized as SK Settings is: the profile loaded in a drop-down (its list loads one), then the
-- job; Start/Stop, the state, Settings, then Track for your target.
local function draw_widget(view)
    local p, s, t = view.profiles, view.status, view.track.target
    local dl = imgui.GetWindowDrawList()
    local x0, y0 = imgui.GetCursorScreenPos()
    local pad, gap, row, px = S(10), S(8), S(30), S(SMALL + 0.5)
    local shown = p.active or 'Default'
    local pick_w = math.min(S(200), math.max(S(110), kit.measure(shown, kit.fonts.text, px) + S(40)))
    local state, color = short_status(view)
    local state_w = 0
    for _, w in ipairs(STATES) do state_w = math.max(state_w, kit.measure(w, kit.fonts.text, px)) end
    state_w = state_w + S(12)  -- its dot
    local run, track_label = s.running and 'Stop' or 'Start', t and ('Track ' .. t)
    local top = pick_w + gap + kit.measure(view.job, kit.fonts.text, px)
    local bottom = kit.button_width(run) + gap + state_w + gap + kit.button_width('Settings')
        + (t and gap + kit.button_width(track_label) or 0)
    local pw, ph = math.ceil(pad * 2 + math.max(top, bottom)), pad * 2 + row * 2
    kit.fill(dl, x0, y0, pw, ph, P.bg, S(6))
    kit.outline(dl, x0, y0, pw, ph, P.border, S(6))

    local x, cy = x0 + pad, y0 + pad + row / 2
    local hovered = kit.dropdown('##sk3_widget_profile', x, cy, pick_w, shown, true, 1, function ()
        if imgui.Selectable('Default##sk3_widget_profile_default', p.active == nil) then act.profile(nil) end
        for i, name in ipairs(p.names) do  -- over a blank row, so a name with '##' in it shows whole
            local sx = imgui.GetCursorPosX()
            if imgui.Selectable('##sk3_widget_profile_' .. i, name == p.active) then act.profile(name) end
            imgui.SameLine(sx)
            imgui.Text(kit.esc(name))
        end
    end)
    if hovered then kit.tooltip(shown .. '\nLoad a profile. SK Settings saves them.') end
    kit.text_mid(dl, x + pick_w + gap, cy, view.job, P.text2, kit.fonts.text, px)

    x, cy = x0 + pad, cy + row
    local clicked, bw = kit.button('##sk3_widget_run', x, cy, run, s.running and 'accent' or 'ghost')
    kit.tip(run .. ' automation')
    if clicked then act.run(not s.running) end
    x = x + bw + gap
    kit.circle(dl, x + S(3), cy, S(3), s.running and color or P.faint)
    kit.text_mid(dl, x + S(12), cy, state, color, kit.fonts.text, px)
    imgui.SetCursorScreenPos({ x, cy - row / 2 })
    imgui.Dummy({ state_w, row })
    kit.tip(status_tip(view))
    x = x + state_w + gap
    clicked, bw = kit.button('##sk3_widget_settings', x, cy, 'Settings', settings_open and 'accent' or 'ghost')
    kit.tip('Open or close SK Settings')
    if clicked then settings_open = not settings_open end
    if t then
        if kit.button('##sk3_widget_track', x + bw + gap, cy, track_label, 'ghost') then act.track(t) end
        kit.tip('Heal, clear, raise and buff them too, with what reaches outside the party. This session only.')
    end
    imgui.SetCursorScreenPos({ x0, y0 + ph - 1 })
    imgui.Dummy({ pw, 1 })  -- the panel's full size, for the auto-size
end

-- SK Settings: the page's rows -----------------------------------------------------

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

local function slider(pg, label, id, path, value, min, max, help, unit)
    local cy = line(pg, label, help)
    local v, moved = kit.slider(id, pg.right - S(SLIDER_W), cy, S(SLIDER_W), value, min, max, true, pg.alpha, unit)
    if moved then act.set(path, v) end
end

local function switch(pg, label, id, on, set, help)
    local cy = line(pg, label, help)
    local v, flipped = kit.switch(id, pg.right - S(kit.SW_W), cy, on, true, pg.alpha)
    kit.tip(help)
    if flipped then set(v) end
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

-- A party member by name for setting `path`, or None ('').
local function member_pick(pg, label, id, current, names, path, help)
    pick(pg, label, label .. '##sk3_' .. id, current ~= '' and current or 'None', function ()
        if imgui.Selectable('None##sk3_' .. id .. '_none', current == '') then act.set(path, '') end
        for _, name in ipairs(names) do
            if imgui.Selectable(name .. '##sk3_' .. id .. '_' .. name, name == current) then act.set(path, name) end
        end
    end, help)
end

-- SK Settings bodies ---------------------------------------------------------------

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
    for _, l in ipairs(HEAL_LINES) do
        slider(pg, l[1], l[1] .. '##sk3_' .. l[2], 'heal.' .. l[2], h[l[2]], 1, 99, l[3], '%')
    end
    -- A heal line at or under its danger line leaves nothing between them: only danger heals go.
    if h.threshold <= h.danger then note(pg, 'Heal under is at or under Danger under: no efficient heals, only danger ones.', P.amber) end
    member_pick(pg, 'Focus', 'focus', h.focus, h.focus_names, 'heal.focus', 'Heal this member first, on its own lines.')
    for _, l in ipairs(HEAL_LINES) do
        local key = 'focus_' .. l[2]
        local label = 'Focus ' .. l[1]:lower()
        slider(pg, label, label .. '##sk3_' .. key, 'heal.' .. key, h[key], 1, 99, 'For the focus member: ' .. l[3], '%')
    end
    if h.focus_threshold <= h.focus_danger then
        note(pg, 'Focus heal under is at or under Focus danger under: the focus member gets danger heals only.', P.amber)
    end
    slider(pg, 'Cure potency +', 'Cure potency +##sk3_cure_potency', 'heal.cure_potency', h.cure_potency, 0, 50,
        'Cure potency % from gear, until a cure has been seen healing.', '%')
    slider(pg, 'Waltz potency +', 'Waltz potency +##sk3_waltz_potency', 'heal.waltz_potency', h.waltz_potency, 0, 50,
        'Waltz potency % from gear, until a waltz has been seen healing.', '%')
    slider(pg, 'Regen potency +', 'Regen potency +##sk3_regen_potency', 'heal.regen_potency', h.regen_potency, 0, 30,
        'HP per Regen tick from gear.')
    switch(pg, 'Heal the alliance', 'Heal the alliance##sk3_heal_alliance', h.alliance, function (on) act.set('heal.alliance', on) end,
        'Heal the alliance\'s other parties too, with heals that reach outside your party. Raising, waking, '
        .. 'removal and buffs look after them whatever this says, and the focus member is always healed.')
    if h.stratagems then
        switch(pg, 'Keep a stratagem for healing', 'Keep a stratagem for healing##sk3_heal_reserve', h.reserve,
            function (on) act.set('heal.reserve', on) end,
            'Buff rows never spend the last stratagem charge, so healing has one for Accession or Rapture.')
    end
    heal_members(pg, h)
end

local function draw_recover_settings(view, pg)
    local r = view.recover
    slider(pg, 'MP under', 'MP under##sk3_recover_mp', 'recover.mp', r.mp, 1, 99,
        'Recover MP under this MP % (yours; a member\'s for Devotion).', '%')
    slider(pg, 'TP under', 'TP under##sk3_recover_tp', 'recover.tp', r.tp, 0, 3000, 'In combat, get TP back under this.')
    if r.spends_tp then
        slider(pg, 'Spend TP from', 'Spend TP from##sk3_recover_min_tp', 'recover.min_tp', r.min_tp, 0, 3000,
            'Chivalry turns all your TP into MP: only from this much.')
    end
end

local function draw_pet_settings(view, pg)
    slider(pg, 'Pet HP under', 'Pet HP under##sk3_pet_heal', 'pet.heal', view.pet_heal, 1, 99, 'Heal your pet under this HP %.', '%')
end

local function draw_follow(view, pg)
    local f = view.follow
    member_pick(pg, 'Leader', 'follow_target', f.target, f.names, 'follow.target', 'Who to follow; resting stands up when they leave too.')
    slider(pg, 'Follow past', 'Follow past##sk3_follow_distance', 'follow.distance', f.distance, 1, 15, 'Yalms.', 'y')
end

local function draw_rest(view, pg)
    local r = view.rest
    slider(pg, 'Rest after', 'Rest after##sk3_rest_delay', 'rest.delay', r.delay, 1, 20, 'Seconds of nothing to do.', 's')
    slider(pg, 'Stand past', 'Stand past##sk3_rest_distance', 'rest.distance', r.distance, 1, 15, 'Yalms from the leader.', 'y')
end

local function draw_afk(view, pg)
    local a = view.afk
    slider(pg, 'Sleep after', 'Sleep after##sk3_afk_minutes', 'afk.minutes', a.minutes, 1, 60,
        'Minutes with no one in your party moving and no combat.', 'm')
    if a.asleep then note(pg, 'Asleep: move to wake.')
    elseif a.left then note(pg, ('Sleeps in %d min without movement or combat.'):format(math.ceil(a.left / 60))) end
end

local function draw_buff_settings(view, pg)
    local b = view.buff
    switch(pg, 'Hold area buffs for the group', 'Hold area buffs for the group##sk3_hold_aoe', b.hold_aoe,
        function (on) act.set('buff.hold_aoe', on) end,
        'Hold an area buff spell (Protectra, Barfira, songs) while a player in your party who lacks it is out of its '
        .. 'reach, so nobody is left out. Trusts and members in another zone never hold it.')
    if b.hold_aoe then
        switch(pg, 'Ask them to gather', 'Ask them to gather##sk3_gather', b.gather, function (on) act.set('buff.gather', on) end,
            'While one is held that someone near you lacks too, say "Gather together for <spell>" in party chat, '
                .. 'at most every 5 seconds.')
    end
    if b.shadows then
        switch(pg, 'Cast Utsusemi at one shadow', 'Cast Utsusemi at one shadow##sk3_one_shadow', b.one_shadow,
            function (on) act.set('buff.one_shadow', on) end,
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

-- What a pick shows: its choice's label, or None; a pick the job no longer has says so.
local function shown_pick(current, choices, field)
    for _, c in ipairs(choices) do
        if c.name == current then return c[field or 'label'] end
    end
    return current ~= '' and current .. ' (not available)' or 'None'
end

-- A roll for setting `path`, or None ('').
local function roll_pick(pg, label, id, current, choices, path)
    pick(pg, label, label .. '##sk3_' .. id, shown_pick(current, choices), function ()
        if imgui.Selectable('None##sk3_' .. id .. '_none', current == '') then act.set(path, '') end
        for _, c in ipairs(choices) do
            if imgui.Selectable(c.label .. '##sk3_' .. id .. '_' .. c.name, c.name == current) then act.set(path, c.name) end
            kit.tip(('Lucky %d, unlucky %d.'):format(c.lucky, c.unlucky))
        end
    end, nil, S(ROLL_W))
end

local function draw_rolls(view, pg)
    local r = view.roll
    roll_pick(pg, 'Roll 1', 'roll_first', r.first, r.choices, 'roll.first')
    if r.two then
        roll_pick(pg, 'Roll 2', 'roll_second', r.second, r.choices, 'roll.second')
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

-- A song for slot `i` of `set`, or None ('').
local function song_pick(set, i, choices, x, cy, w, alpha)
    local current, id = set.picks[i], ('sk3_song_%s_%d'):format(set.key, i)
    local path = ('song.%s_%d'):format(set.key, i)
    kit.dropdown('##' .. id, x, cy, w, shown_pick(current, choices), true, alpha, function ()
        if imgui.Selectable('None##' .. id .. '_none', current == '') then act.set(path, '') end
        for _, c in ipairs(choices) do
            if imgui.Selectable(c.label .. '##' .. id .. '_' .. c.name, c.name == current) then act.set(path, c.name) end
        end
    end)
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
                song_pick(set, it.i, m.choices, it.x, icy, box, pg.alpha)
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
        switch(pg, 'Pianissimo fast casting', 'Pianissimo fast casting##sk3_song_fast', m.fast,
            function (on) act.set('song.fast', on) end,
            'Fire Pianissimo before an area song too, for its shorter cast, and cancel it a second into the cast '
                .. 'so the song still lands on everyone near you. None is fired while Nightingale is up (its casts are '
                .. 'short already); with Pianissimo on recast the area song goes without it. A Pianissimo already up '
                .. 'goes to the next area song, or to a member\'s song while that area song can\'t go yet.')
    end
    if m.timed then
        slider(pg, 'Song Duration', 'Song Duration##sk3_song_duration', 'song.duration', m.duration, 0, 300,
            'Seconds: sing each song again this long after it landed, before it wears (0: only once it\'s gone). '
            .. 'Set it just under your songs\' real duration, gear included; doubled for a song sung under Troubadour. '
            .. 'While Nightingale and Troubadour are both up, every song sung without Troubadour is sung again.', 's')
    end
end

local function draw_geo(view, pg)
    local g = view.geo
    slider(pg, 'Recall past', 'Recall past##sk3_geo_distance', 'geo.distance', g.distance, 3, 30,
        'Yalms: Full Circle the luopan once who it is on is further than this from it, so it goes down again.', 'y')
    slider(pg, 'Keep after combat', 'Keep after combat##sk3_geo_linger', 'geo.linger', g.linger, 1, 20,
        'Seconds a debuff luopan waits once combat is over before Full Circle recalls it: a new battle target in that time keeps it.', 's')
    member_pick(pg, 'Entrust to', 'geo_entrust', g.entrust, g.names, 'geo.entrust',
        'With Entrust on, put the Indi- spell picked on this member (within 20 yalms).')
    pick(pg, 'Entrust spell', 'Entrust spell##sk3_geo_entrust_spell', g.entrust_spell ~= '' and g.entrust_spell or 'None', function ()
        if imgui.Selectable('None##sk3_geo_entrust_spell_none', g.entrust_spell == '') then act.set('geo.entrust_spell', '') end
        for _, name in ipairs(g.indi) do
            if imgui.Selectable(name .. '##sk3_geo_entrust_spell_' .. name, name == g.entrust_spell) then act.set('geo.entrust_spell', name) end
        end
    end, 'The Indi- spell Entrust puts on that member whenever they lack its aura.')
end

-- What a set's slots show of each rune.
local SHOWS = { element = 'Each rune by the element it adds to your attacks.',
                resist = 'Each rune by the element it resists.', ailments = 'Each rune by the ailments it defends against.' }

local function rune_tip(r)
    return ('%s: adds %s, resists %s, against %s.'):format(r.name, r.element, r.resist, r.ailments)
end

-- A rune for slot `i` of `set`, or None ('').
local function rune_pick(set, i, runes, x, cy, w, alpha)
    local current, id = set.picks[i], ('sk3_rune_%s_%d'):format(set.key, i)
    local path = ('rune.%s_%d'):format(set.key, i)
    local shown = shown_pick(current, runes, set.shows)
    local hovered = kit.dropdown('##' .. id, x, cy, w, shown, true, alpha, function ()
        if imgui.Selectable('None##' .. id .. '_none', current == '') then act.set(path, '') end
        for _, r in ipairs(runes) do
            if imgui.Selectable(r[set.shows] .. '##' .. id .. '_' .. r.name, r.name == current) then act.set(path, r.name) end
            kit.tip(rune_tip(r))
        end
    end)
    if hovered then kit.tooltip(shown .. '\n' .. SHOWS[set.shows]) end
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
            kit.text_right(pg.dl, pg.right, cy, set.avail, set.ready and P.teal or P.dim, kit.fonts.text, S(SMALL + 0.5), pg.alpha)
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
        local i, id, path = it.i, 'sk3_maneuver_' .. it.i, 'maneuver.slot_' .. it.i
        local icy = cy + (it.line - 1) * S(CHIP_LINE)
        local hovered = kit.dropdown('##' .. id, it.x, icy, box, shown_pick(m.picks[i], m.choices), true, pg.alpha, function ()
            if imgui.Selectable('None##' .. id .. '_none', m.picks[i] == '') then act.set(path, '') end
            for _, c in ipairs(m.choices) do
                if imgui.Selectable(c.label .. '##' .. id .. '_' .. c.name, c.name == m.picks[i]) then act.set(path, c.name) end
            end
        end)
        if hovered then kit.tooltip('The same element in two slots keeps two up.') end
    end
    local ay = cy + (extra == 0 and last.line - 1 or lines) * S(CHIP_LINE)
    kit.text_right(pg.dl, pg.right, ay, m.avail, m.ready and P.teal or P.dim, kit.fonts.text, px, pg.alpha)
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

-- SK Settings' size, % of the size for the screen: view.ui.scale, held to its slider's range.
local function ui_scale(ui) return math.min(math.max(math.floor(tonumber(ui and ui.scale) or 100), 50), 200) end

-- Another session's shows only what it sent: its HUD and log are its own.
local function draw_ui(view, pg)
    if view.session then return draw_recent(view, pg) end
    subheader(pg, 'HUD')
    for _, l in ipairs(UI_SLIDERS) do
        slider(pg, l[1], l[1] .. '##sk3_ui_' .. l[2], 'ui.' .. l[2], view.ui[l[2]], l[3], l[4], l[5], l[6])
    end
    switch(pg, 'Lock position', 'Lock position##sk3_ui_locked', view.ui.locked == true, function (on) act.set('ui.locked', on) end,
        'Keep the HUD and the widget where they are: dragging them no longer moves them.')
    switch(pg, 'Widget', 'Widget##sk3_ui_widget', view.ui.widget == true, function (on) act.set('ui.widget', on) end,
        'A small window of its own: the profile loaded (pick another to load it) and your job, then Start/Stop, '
        .. 'the state, Settings, and Track for your target. Up with the HUD closed too. Also /sk3 widget.')
    subheader(pg, 'SK SETTINGS')
    slider(pg, 'Size', 'Size##sk3_ui_scale', 'ui.scale', ui_scale(view.ui), 50, 200,
        'This window\'s size and the widget\'s, % of the size that suits your screen. Taken up once the slider is let go.', '%')
    subheader(pg, 'LOG')
    switch(pg, 'Action log', 'Action log##sk3_log', view.log, act.log, 'Print each action to chat as it is sent.')
    draw_recent(view, pg)
    subheader(pg, 'CLIENT')
    switch(pg, 'Japanese client', 'Japanese client##sk3_japanese', view.japanese, function (on) act.set('japanese', on) end,
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

    -- An item shows how many you carry, ninjutsu their tools; ### keeps its id while the count changes.
    local sx = pg.right - S(kit.SW_W)
    local on, flipped = kit.switch(n and ('%s (%d)###%s'):format(r.label, n, id) or r.label .. '##' .. id, sx, cy, r.on, true, pg.alpha)
    if flipped then act.row(r.key, on) end
    local px = S(SMALL + 0.5)
    local aw = kit.measure(r.avail, kit.fonts.text, px)
    local ax = sx - S(12) - aw
    kit.text_mid(pg.dl, ax, cy, r.avail, r.ready and P.teal or P.dim, kit.fonts.text, px, pg.alpha)
    if r.action and kit.over(ax, cy - S(10), aw, S(20)) then kit.tooltip(r.action) end
    local label = n and ('%s (%d)'):format(r.label, n) or r.label
    kit.text_mid(pg.dl, pg.lx, cy, kit.fit(label, ax - S(12) - pg.lx, kit.fonts.text, S(BODY)), r.on and P.text or P.dim,
        kit.fonts.text, S(BODY), pg.alpha)

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

-- Spells and abilities, then items (rows with a count) under a heading of their own.
local function section_rows(pg, s, has_body)
    local acts, items = {}, {}
    for _, r in ipairs(s.rows) do table.insert(r.count and items or acts, r) end
    if #acts > 0 and has_body then subheader(pg, 'ACTIONS') end
    for _, r in ipairs(acts) do family_row(pg, s.id, r) end
    if #items > 0 then
        subheader(pg, 'ITEMS')
        for _, r in ipairs(items) do family_row(pg, s.id, r) end
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

-- Whose settings these are (SK Settings, or the session's name), its job and whether it runs; then its pages, and
-- Profiles and UI / Log at the foot.
local function draw_sidebar(view, pane, pages, name, x, y, w, h)
    local dl, pad = imgui.GetWindowDrawList(), S(PAD)
    local st = view.status
    local title_px, small = S(BODY), S(SMALL)
    kit.text_mid(dl, x + pad, y + S(24), kit.fit(name or 'SK Settings', w - pad * 2, kit.fonts.semi, title_px), P.white, kit.fonts.semi, title_px)
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

-- A SK Settings window's inside, from `view`: `key` and `name` are '' and nil for yours, the session's name for
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

-- A SK Settings window, the `index`th open (each starts a little further down and right): ImGui draws none of it, the
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

-- Each window: Begin, the body under pcall, End; returns the error the body raised.
-- ponytail: an error inside a drop-down's list still leaves its popup open, which
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

local function widget(view)
    local flags = WIDGET_FLAGS + (view.ui.locked and ImGuiWindowFlags_NoMove or 0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    local shown = imgui.Begin('SK Widget', true, flags)
    imgui.PopStyleVar(2)
    local ok, err = true, nil
    if shown then ok, err = pcall(draw_widget, view) end
    imgui.End()  -- ImGui keeps where it was dragged, in imgui.ini
    if not ok then return err end
end

local function settings_window(view)
    local open = { true }
    local err = settings_shell('SK Settings', open, 0, function (x, y, side, pw, ph)
        draw_settings(view, '', nil, x, y, side, pw, ph, open)
    end)
    if not open[1] then settings_open = false end
    return err
end

-- Another session's SK Settings, from the view it published, its changes sent to it; until its first view comes, or
-- from a session running other code, a line saying so.
local function remote_window(r, index)
    local open = { true }
    local mine = act
    local err = settings_shell(('SK Settings: %s###sk3_settings_%s'):format(r.name, r.name), open, index, function (x, y, side, pw, ph)
        act = mine.remote(r.name)
        if r.view and not r.other then return draw_settings(r.view, r.name, r.name, x, y, side, pw, ph, open) end
        local dl = imgui.GetWindowDrawList()
        kit.text_mid(dl, x + S(PAD), y + S(24), kit.fit(r.name, side - S(PAD) * 2, kit.fonts.semi, S(BODY + 2)), P.white, kit.fonts.semi, S(BODY + 2))
        title_bar('SK Settings', nil, x + side + 1, y, pw - side - 1, open)
        local pg = { dl = dl, x = x + side + 1, w = pw - side - 1, y = y + S(TITLE_H) + S(14), lx = x + side + 1 + S(LEFT),
                     right = x + pw - S(PAD), alpha = 1 }
        note(pg, r.other and ('%s runs another version of Sidekick3: /addon reload sidekick3 there.'):format(r.name)
            or ('Waiting for %s\'s session...'):format(r.name))
    end)
    act = mine
    if not (open[1] and not err) then act.watch(r.name, false) end  -- a view that won't draw isn't drawn again
    return err
end

-- One frame. A Lua error raised while drawing is raised again after the windows
-- are ended, so ImGui stays balanced and Sidekick reports it.
function window.render(view, act_)
    act = act_
    if not imgui.IsAnyItemActive() then user_scale = ui_scale(view.ui) / 100 end  -- not mid-drag: the window would move under it
    kit.frame(user_scale)
    local open = view.ui.open ~= false
    if hud_open and not open then settings_open = false end
    hud_open = open
    local err
    if open then
        kit.prefix = 'hud|'
        err = hud(view)
    end
    if view.ui.widget then
        kit.prefix = 'widget|'
        err = widget(view) or err
    end
    kit.prefix = ''
    if settings_open then err = settings_window(view) or err end
    if open then
        for i, r in ipairs(view.remote or {}) do
            kit.prefix = r.name .. '|'
            err = remote_window(r, i) or err
        end
        kit.prefix = ''
    end
    if err then error(err, 0) end
end

return window
