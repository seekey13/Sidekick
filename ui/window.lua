--[[
    The standard Sidekick UI, and the reference: it uses only the `view` and `act`
    every UI is given (ui/README.md), so any theme in ui/ can replace it, and takes each
    setting's range from ui/model.lua's REMOTE_SET. ImGui only: it reads no game
    state and decides nothing. Everything is drawn on ImGui's draw lists in
    ui/kit.lua's look (docs/vana-ui-style.md); Sidekick Settings' sidebar and page
    layout follow VanaCore's addons/vanacore/vana/vana.lua (Copyright (C) 2026
    Vekien, GPL-3.0-or-later).

    Three windows: the HUD (Sidekick: the party's bars, a pet's under its owner's (yours,
    and another session's), with a label at whoever
    this session's next action is for and one at whoever each other session's
    latest went to; your card's run button and cog, and those of another session's
    card; at your card, while your target is a player you could track, Add Tracked,
    in a little window of its own to take the click), the widget (SK Widget,
    `ui.widget`: a pill per character with its run button and cog, then Add
    Tracked as the HUD's, up with the HUD closed too) and Sidekick Settings (a page per
    group of sections; another session's too, drawn from the view it publishes,
    its changes sent to it).

    Ashita's binding: widget values are one-element tables ({ 'text' }), and Text
    takes a printf format (kit.esc doubles any '%'). Draw-list text and
    kit.tooltip's are drawn as is.

    Its words are English, or Japanese on a Japanese client (core/lang.lua: t and
    f); ids stay English, so a control keeps its state when the language changes.
    Names the game gives (a trust's, your pet's, the mob's) are Shift-JIS on a
    Japanese client: drawn through lang.text, kept as they are for `act`.
]]--

local imgui = require('imgui')
local kit = require('ui.kit')
local lang = require('core.lang')
local LIMITS = require('ui.model').REMOTE_SET  -- each setting's range, as a session takes it from another
local util = require('core.util')

local window = {}

local P, S = kit.P, kit.S
local BODY, SMALL = kit.BODY, kit.SMALL
local t, f, game_text = lang.t, lang.f, lang.text

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
local settings_open = false  -- Sidekick Settings shown: view.ui.settings, and a cog's click from that same frame
local profile_names = {}     -- per Sidekick Settings window ('' for yours, else the session's name), this session only:
                             -- { typed = { name }, shown }, the name filled in again when the profile loaded changes
local panes = {}             -- per Sidekick Settings window: { page, folded = { [section id] = true }, debuff = slot }
local user_scale = 1         -- Sidekick Settings' size (view.ui.scale), taken up while nothing is held

-- HUD -----------------------------------------------------------------------------

local HUD_PAD, BAR_GAP, ROUND = 8, 3, 4  -- the panel's padding, between bars, the bars' corners (pixels)
local BAR_FILL = 0.7                     -- the fill lets the game show through, as the reference bar
local BAR_TRACK_A = 0.7                  -- bar background stays at 70%: gray hovered, black while not
local BAR_EDGE = 1                       -- the stroke around each bar
local BAR_EDGE_A = 0.7                   -- that stroke is black at 70%, and it does not fade with the panel
local BAR_OFF = '#0c0c0c'                -- the background while the pointer is off the panel; the stroke is always this
local PET_WELL = '#C2FFFF'               -- your pet's name over 75% HP, where a member's is white
local TITLE = 'Sidekick'

local HUD_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoBringToFrontOnFocus

-- The title's tooltip: the job, what automation is doing, and what may hold it up.
local function status_tip(view)
    local s = view.status
    local lines = { view.job, ('%s: %s'):format(t(s.state), s.text) }
    if view.profiles.active then lines[1] = f('%s  (profile %s)', view.job, view.profiles.active) end
    if s.dim then lines[#lines + 1] = ('(%s)'):format(s.dim) end
    if #view.flags > 0 then
        local flags = {}
        for i, flag in ipairs(view.flags) do flags[i] = t(flag) end
        lines[#lines + 1] = '[' .. table.concat(flags, '] [') .. ']'
    end
    for _, e in ipairs({ { 'Target', view.bt }, { 'Pet', view.pet } }) do
        if e[2] then lines[#lines + 1] = ('%s: %s  %d%%  %s'):format(t(e[1]), game_text(e[2].name), e[2].hpp, e[2].dist) end
    end
    return table.concat(lines, '\n')
end

local function member_tip(p)
    local notes = {}
    if p.kind == 'trust' or p.kind == 'tracked' or p.kind == 'alliance' then notes[#notes + 1] = t(p.kind) end
    if p.job then notes[#notes + 1] = p.job end
    if not (p.alive or p.away) then notes[#notes + 1] = t('KO') end
    if p.away then notes[#notes + 1] = t('away') end
    local line = ('HP %d%%'):format(p.hpp) .. (p.uses_mp and ('  MP %d%%'):format(p.mpp) or '')
        .. (p.kind ~= 'tracked' and ('  TP %d'):format(p.tp) or '')  -- a tracked player's can't be read
    if p.dist ~= '' and not p.away then line = line .. '  ' .. p.dist end
    local name = game_text(p.name)
    local lines = { #notes > 0 and ('%s (%s)'):format(name, lang.list(notes)) or name, line }
    if p.buffs_all ~= '' then lines[#lines + 1] = p.buffs_all end
    return table.concat(lines, '\n')
end

-- A pet's tooltip: its MP % and TP only while known (another session's, once its file names that pet), its MP %
-- only while it has MP.
local function pet_tip(pet)
    if not pet.pools then return f('%s (pet)\nHP %d%%  %s', game_text(pet.name), pet.hpp, pet.dist) end
    if not pet.uses_mp then return f('%s (pet)\nHP %d%%  TP %d  %s', game_text(pet.name), pet.hpp, pet.tp, pet.dist) end
    return f('%s (pet)\nHP %d%%  MP %d%%  TP %d  %s', game_text(pet.name), pet.hpp, pet.mpp, pet.tp, pet.dist)
end

-- A track at (x, y), w by h, `filled` (0 to 1) of it in `color`. The whole bar has a
-- background at 70% that does not fade with the panel: gray while the pointer is over
-- it (`chrome` 1), near-black while not. A 1px stroke in that same near-black, at 70%, sits on the edge.
-- The fill is at 70% too.
local function track(dl, x, y, w, h, filled, color, alpha, chrome)
    local r = math.min(ROUND, math.floor(h / 2))
    kit.fill(dl, x, y, w, h, kit.mix(BAR_OFF, P.track, chrome), r, BAR_TRACK_A)
    local fw = util.clamp(util.round(w * filled), 0, w)
    if fw > 0 then
        kit.fill(dl, x, y, fw, h, color, math.min(r, fw / 2), alpha * BAR_FILL, fw < w and kit.LEFT_CORNERS or nil)
    end
    kit.outline(dl, x, y, w, h, BAR_OFF, r, BAR_EDGE_A, BAR_EDGE)
end

-- A bar: `pct` of its track filled (eased, by `id`).
local function bar(dl, id, x, y, w, h, pct, color, alpha, chrome)
    track(dl, x, y, w, h, kit.ease(id, util.clamp(pct, 0, 100) / 100, 12), color, alpha, chrome)
end

local TIER, TIERS = 1000, 3  -- TP: a weapon skill's worth, and how many stand

-- The TP bar: a track per 1000 TP side by side, each filling once the one before is full (eased, by `id`); the one
-- still filling is drawn faint, as Floaties draws it.
local function tp_bar(dl, id, x, y, w, h, tp, alpha, chrome)
    local tiers = kit.ease(id, util.clamp(tp, 0, TIER * TIERS) / TIER, 12)
    local tw = (w - (TIERS - 1) * BAR_GAP) / TIERS
    for i = 1, TIERS do
        local filled = util.clamp(tiers - (i - 1), 0, 1)
        local tx = util.round(x + (i - 1) * (tw + BAR_GAP))
        track(dl, tx, y, util.round(x + i * tw + (i - 1) * BAR_GAP) - tx, h, filled, P.tp,
            (filled < 1 and 0.5 or 1) * alpha, chrome)
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

-- A character's act: yours, or another session's (`c.remote`), made only when it's used.
local function act_of(c) return c.remote and act.remote(c.name) or act end

-- A character's run button at (x, y) and its cog `gap` right of it, each `s` across, by the ids in `ids`: `c` is
-- { name, running, shown (its Sidekick Settings), remote (nil for yours) }. `lit`: the run button is lit while it
-- runs; `tip`: your own cog's tooltip. Returns whether either is hovered.
local function run_and_cog(c, ids, x, y, s, gap, lit, tip)
    local help = c.remote and f(c.running and 'Stop %s\'s automation' or 'Start %s\'s automation', c.name)
        or t(c.running and 'Stop automation' or 'Start automation')
    local run, over_run = disc_button(ids[1], x, y, s, c.running and 'stop' or 'play', lit and c.running, help)
    if run then act_of(c).run(not c.running) end
    local cog, over_cog = disc_button(ids[2], x + s + gap, y, s, 'cog', c.shown,
        c.remote and f('Settings for %s', c.name) or t(tip))
    if cog and c.remote then act.watch(c.name, not c.shown)
    elseif cog then
        settings_open = not settings_open
        act.settings(settings_open)
    end
    return over_run or over_cog
end

-- Tracker's close: an X, dim until the pointer is on it, then rose. No disc behind it.
local function close_mark(id, cx, cy, box, alpha)
    local hovered, clicked = kit.hit(id, cx - box / 2, cy - box / 2, box, box)
    kit.icon(imgui.GetWindowDrawList(), 'close', cx, cy, box * 0.72, hovered and P.rose or P.dim, alpha)
    return clicked, hovered
end

-- "Sidekick", then close (s pixels across); the title's hover area says what automation is doing.
-- Both fade with the panel (`chrome`).
local function title_row(dl, view, ts, x0, y0, pw, th, s, chrome)
    local font = kit.fonts.semi
    local _, h = kit.measure(TITLE, font, ts)
    kit.halo(dl, x0 + HUD_PAD, y0 + (th - h) / 2, TITLE, P.white, font, ts, chrome)
    local cx, cy = x0 + pw - HUD_PAD - s / 2, y0 + th / 2
    imgui.SetCursorScreenPos({ x0, y0 })
    imgui.Dummy({ cx - s / 2 - x0, th })
    kit.tip(status_tip(view))
    local clicked = close_mark('##sk_close', cx, cy, s, chrome)
    kit.tip(t('Close (/sk hud opens it again)'))
    if clicked then act.close() end  -- Sidekick Settings stay: /sk has them
end

-- Run and the cog at the top right of the HP bar of your card, or of another session's, s pixels across (at most
-- what the bar fits). Returns whether one is hovered, so the card's own tooltip gives way.
local function card_icons(view, ui, p, x, y, s)
    s = math.min(s, ui.hp_height - 4, math.floor((ui.hp_width - 8) / 2))
    local r = p.session
    local c = r and { name = r.name, running = r.running, shown = r.open, remote = r }
        or { name = p.name, running = view.status.running, shown = settings_open }
    local id = r and ('_' .. r.name) or ''
    return run_and_cog(c, { '##sk_run' .. id, '##sk_cog' .. id }, x + HUD_PAD + ui.hp_width - 6 - s * 2, y + 2, s, 4,
        true, 'Settings')
end

-- The name on an HP bar. Over 75% it stays `well` (white, unless given); at 75% it turns yellow, at 50% orange and at
-- 25% red. Away, it greys with the bars.
local function name_color(p, well)
    if p.away then return P.dim end
    local hpp = p.hpp or 100
    if hpp <= 25 then return P.red end
    if hpp <= 50 then return P.orange end
    if hpp <= 75 then return P.yellow end
    return well or P.white
end

-- A member's card at (x, y): the HP bar over the MP bar over the TP bar, the name on the first and the tag on the
-- last, the % of each (TP's number) only in its tooltip. `no_mp` leaves the MP bar out, the TP bar up under the HP
-- bar. A tracked player's MP and TP can't be read: their bars stay empty. The name turns yellow at 75% HP, orange at
-- 50% and red at 25%; MP under the Recover line turns the tag rose. Away, the bars fade and the text greys. `id`
-- keeps the bars' eased fills apart.
local function card(dl, ui, p, x, y, id, chrome, no_mp)
    local fx, mp_top = x + HUD_PAD, y + ui.hp_height + BAR_GAP
    local tp_top = no_mp and mp_top or mp_top + ui.mp_height + BAR_GAP
    local fade = p.away and 0.45 or 1
    bar(dl, 'hp.' .. id, fx, y, ui.hp_width, ui.hp_height, p.hpp, P.hp, fade, chrome)
    if not no_mp then bar(dl, 'mp.' .. id, fx, mp_top, ui.mp_width, ui.mp_height, p.mpp, P.mp, fade, chrome) end
    tp_bar(dl, 'tp.' .. id, fx, tp_top, ui.tp_width, ui.tp_height, p.tp, fade, chrome)
    local font, name = kit.fonts.semi, game_text(p.name)
    local _, nh = kit.measure(name, font, ui.name_size)
    kit.halo(dl, fx + 6, y + ui.hp_height - nh, name, name_color(p), font, ui.name_size)
    local _, th = kit.measure(p.tag, font, ui.text_size)
    kit.halo(dl, fx + 6, tp_top + (ui.tp_height - th) / 2, p.tag,
        p.away and P.dim or p.mp == 'low' and P.rose or P.text2, font, ui.text_size)
end

-- A pet's card at (x, y), yours or another session's: its HP bar over its MP bar over its TP bar, each an alliance
-- row's size (the HP bar's width, the MP bar's height), its name on the first and its tag on the last, at the text's
-- size; `no_mp` leaves the MP bar out, as a card's. The name is coloured as a card's, but pale cyan while healthy.
-- `id` keeps the bars' eased fills apart.
local function pet_card(dl, ui, p, x, y, id, chrome, no_mp)
    local fx, w, h = x + HUD_PAD, ui.hp_width, ui.mp_height
    local mp_top = y + h + BAR_GAP
    local tp_top = no_mp and mp_top or mp_top + h + BAR_GAP
    bar(dl, 'hp.' .. id, fx, y, w, h, p.hpp, P.hp, 1, chrome)
    if not no_mp then bar(dl, 'mp.' .. id, fx, mp_top, w, h, p.mpp, P.mp, 1, chrome) end
    tp_bar(dl, 'tp.' .. id, fx, tp_top, w, h, p.tp, 1, chrome)
    local font, name = kit.fonts.semi, game_text(p.name)
    local _, nh = kit.measure(name, font, ui.text_size)
    kit.halo(dl, fx + 6, y + (h - nh) / 2, name, name_color(p, PET_WELL), font, ui.text_size)
    local _, th = kit.measure(p.tag, font, ui.text_size)
    kit.halo(dl, fx + 6, tp_top + (h - th) / 2, p.tag, P.text2, font, ui.text_size)
end

-- An alliance member's row, its bar's top at `top`: a thin HP bar (the MP bar's height) with the tag and name on
-- it, coloured as a card's name is, its HP % only in its tooltip.
local function ally_row(dl, ui, p, x, top, chrome)
    local fx = x + HUD_PAD
    bar(dl, 'ally.' .. p.name, fx, top, ui.hp_width, ui.mp_height, p.hpp, P.hp, p.away and 0.45 or 1, chrome)
    local label = p.tag .. ' ' .. game_text(p.name)
    local _, h = kit.measure(label, kit.fonts.semi, ui.text_size)
    kit.halo(dl, fx + 6, top + (ui.mp_height - h) / 2, label, name_color(p), kit.fonts.semi, ui.text_size)
end

local ADD_TRACKED = 'Add Tracked'
local asked  -- the target Add Tracked was clicked for, while still your target and not yet shown tracked

-- Your target while Add Tracked is up for them: not once it's clicked, as the snapshot that shows them tracked comes up
-- to a tenth of a second later, and a second click then would /check them again.
local function trackable(view)
    local who = view.track.target
    return who ~= asked and who or nil
end

-- The Add Tracked pill `ph` high, its words at `px`: its width, then from its left its words' and its icon's, and the
-- icon's size (the pill's height less a margin above and below, that margin after it too).
local function add_tracked_size(ph, px)
    local margin, lead = util.round(ph * 0.12), util.round(ph * 0.36)
    local icon = ph - margin * 2
    local ix = lead + math.ceil(kit.measure(t(ADD_TRACKED), kit.fonts.semi, px)) + util.round(ph * 0.23)
    return ix + icon + margin, lead, ix, icon
end

-- Add Tracked at (x, y), `ph` high with its words at `px`, then Material Design's plus-circle: a pill in vana's pill
-- colours, lit under the pointer. A click anywhere on it tracks `who`, your target, as Tracked's Track button does.
-- Each target's its own control, as there: a new one's pill starts unlit, not as the last was left when clicked.
local function add_tracked(id, x, y, ph, px, who)
    id = id .. '_' .. who
    local w, lead, ix, icon = add_tracked_size(ph, px)
    local hovered, clicked, held = kit.hit(id, x, y, w, ph)
    kit.tip(f('Track %s', who) .. '\n'
        .. t('Heal, clear, raise and buff them too, with what reaches outside the party. This session only.'))
    local lit = kit.ease(id, hovered and 1 or 0, 22)
    local body = kit.mix(kit.mix(P.accent_bg, P.accent_lo, lit * 0.6), '#000000', held and 0.15 or 0)
    local fg, dl, cy = kit.mix(P.accent2, P.white, lit), imgui.GetWindowDrawList(), y + ph / 2
    kit.fill(dl, x, y, w, ph, body, ph / 2)
    kit.outline(dl, x, y, w, ph, kit.mix(P.accent_lo, P.accent, lit), ph / 2)
    kit.text_mid(dl, x + lead, cy, t(ADD_TRACKED), fg, kit.fonts.semi, px)
    kit.icon(dl, 'plus_circle', x + ix + icon / 2, cy, icon, fg, 1, body)
    if clicked then asked = who; act.track(who) end
end

local hud_add  -- where the HUD's Add Tracked pill goes this frame, { x, y, ph, px, who }: nil while it has none

-- Labels in pills side by side, the first's point just right of the panel at `cy`: this session's amber while running
-- (what goes), grey while stopped (what would); another session's blue, after its name on a darker part. On the
-- background list: they sit outside the window without widening it, as a transparent window area would block the
-- game's clicks. Add Tracked (`track`, your target's name) only has its shadow and point here: it's drawn and clicked
-- in a window of its own (add_window), once the HUD's is done.
local function draw_labels(list, ts, right, cy)
    if not list[1] then return end
    local dl = imgui.GetBackgroundDrawList()
    local font = kit.fonts.semi
    local h, pad = math.floor(ts * 1.6), math.floor(ts * 0.6)
    cy = math.floor(cy - h / 2) + h / 2  -- their tops on whole pixels, as Add Tracked's window is: all in line
    local x = right + 2 + math.floor(h * 0.45)  -- the first pill's left, after its point
    for i, l in ipairs(list) do
        local who = l.session
        local nw = who and kit.measure(who, font, ts) + pad * 2 or 0  -- the name's part
        local w = l.track and add_tracked_size(h, ts) or nw + kit.measure(l.text, font, ts) + pad * 2
        local color = l.track and P.accent_lo or who and P.accent or l.live and P.amber or P.seg
        kit.fill(dl, x, cy - h / 2 + 2, w, h, '#000000', h / 2, 0.3)  -- its shadow
        if i == 1 then kit.tri(dl, { right + 2, cy }, { x + h / 4, cy - h * 0.32 }, { x + h / 4, cy + h * 0.32 }, color) end
        if l.track then
            hud_add = { x = x, y = cy - h / 2, ph = h, px = ts, who = l.track }
        else
            kit.fill(dl, x, cy - h / 2, w, h, color, h / 2)
            if who then
                kit.fill(dl, x, cy - h / 2, nw, h, P.accent_lo, h / 2, 1, kit.LEFT_CORNERS)
                kit.text_mid(dl, x + pad, cy, who, P.white, font, ts)
            end
            kit.text_mid(dl, x + nw + pad, cy, l.text, (who or l.live) and P.ink or P.text2, font, ts)
        end
        x = x + w + math.floor(h * 0.3)
    end
end

-- view.ui's sizes, each held to its slider's range: nothing checks a value edited
-- by hand or set by a custom UI, and ImGui asserts on a zero-size button.
local function hud_sizes(ui)
    local out = {}
    for _, l in ipairs(UI_SLIDERS) do
        out[l[2]] = util.clamp(math.floor(tonumber(ui[l[2]]) or l[3]), l[3], l[4])
    end
    return out
end

-- The cards from the top: each party line's (`member`, its index) and a pet's under its owner's (`pet`, its line, with
-- its owner's `member`): yours (view.pet), and another session's (its line's `pet`), drawn from a line of the same
-- shape tagged PET; `id` keeps their eased fills apart, two sessions' Carbuncles too. `no_mp`: its MP bar is left out
-- (`ui.hide_mp`), as it has no MP (0/0). Not a tracked player's, nor that of another session's pet its file doesn't
-- name yet: theirs can't be read, and stays empty.
local function cards_of(view)
    local out, hide = {}, view.ui.hide_mp ~= false
    for i, p in ipairs(view.party) do
        out[#out + 1] = { p = p, id = p.name, member = i, no_mp = hide and p.kind ~= 'tracked' and not p.uses_mp }
        local pet = i == 1 and view.pet or p.pet
        if pet then
            out[#out + 1] = { p = { name = pet.name, tag = 'PET', hpp = pet.hpp, mpp = pet.mpp, tp = pet.tp },
                              id = ('pet.%s.%s'):format(p.name, pet.name), member = i, pet = pet,
                              no_mp = hide and pet.pools and not pet.uses_mp }
        end
    end
    return out
end

-- Card `c`'s height: its three bars, a pet's each an alliance row high, or two with its MP bar left out.
local function card_height(ui, c)
    local hp, mp, tp = ui.hp_height, ui.mp_height, ui.tp_height
    if c.pet then hp, tp = mp, mp end
    return hp + BAR_GAP + (c.no_mp and 0 or mp + BAR_GAP) + tp
end

-- Whether the arrow points at card `c`: your pet's for its own actions, else the member's.
local function pointed(view, c)
    local ptr = view.pointer
    if not ptr then return false end
    local to_pet = ptr.pet == true and view.pet ~= nil
    if c.pet then return to_pet and ptr.member == c.member end
    return not to_pet and ptr.member == c.member
end

-- The labels at card `c`, or at the alliance's row `j`: at your own card Add Tracked first while your target is a player
-- you could track (first, so it stays put to be clicked), then this session's, then each other session's there (its
-- pet's own at its pet's card).
local function labels_at(view, c, j)
    local ptr, out = view.pointer, {}
    local who = c and c.p.kind == 'self' and trackable(view)
    if who then out[1] = { track = who } end
    if c and pointed(view, c) or j and ptr and ptr.ally == j then out[#out + 1] = ptr end
    for _, o in ipairs(view.others) do
        if c and o.member == c.member and (not o.pet) == (not c.pet) or j and o.ally == j then out[#out + 1] = o end
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
    local cards = cards_of(view)
    local below = th + math.max(#cards - 1, 0) * ui.gap
    for _, c in ipairs(cards) do  -- each card `h` high
        c.h = card_height(ui, c)
        below = below + c.h
    end
    -- Under the cards, the alliance's rows: B0-B5, then C0-C5, each party after a gap; `rows` holds each bar's top.
    local rows, last = {}, nil
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
    local y = y0 + th
    for _, c in ipairs(cards) do
        local p = c.p
        if c.pet then pet_card(dl, ui, p, x0, y, c.id, chrome, c.no_mp) else card(dl, ui, p, x0, y, c.id, chrome, c.no_mp) end
        local on_icon = (p.kind == 'self' or p.session) and card_icons(view, ui, p, x0, y, s)
        imgui.SetCursorScreenPos({ x0 + HUD_PAD, y })
        imgui.Dummy({ pw - 2 * HUD_PAD, c.h })
        if not on_icon then kit.tip(c.pet and pet_tip(c.pet) or member_tip(p)) end
        draw_labels(labels_at(view, c), ui.text_size, x0 + pw, y + c.h / 2)
        y = y + c.h + ui.gap
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
    return util.clamp(math.floor(tonumber(ui and ui.widget_size) or 16), WIDGET_SIZES[1], WIDGET_SIZES[2])
end

-- The characters the widget shows: you, then every other Sidekick session on this PC (view.sessions, by name: from
-- their files, so a zone leaves them as they were). { name, running, halted, shown (its Sidekick Settings), profiles
-- (nil while unknown), remote (nil for yours) }.
local function characters(view)
    local me = view.party[1]
    local out = { { name = me and me.name or t('You'), running = view.status.running, halted = view.status.halted,
                    shown = settings_open, profiles = view.profiles } }
    for _, r in ipairs(view.sessions or {}) do
        out[#out + 1] = { name = r.name, running = r.running, halted = r.halted, shown = r.open, profiles = r.profiles,
                          remote = r }
    end
    return out
end

-- A character's profiles, right-clicking its name: Default, then each saved; a click loads it there. As tall as a
-- drop-down's list (Drop-down rows), then it scrolls, opening at the one loaded.
local function profile_menu(c, id, px)
    kit.list_size(px, 0, S(1200))
    kit.popup(id, px, function ()
        local p = c.profiles
        if kit.selectable(t('Default') .. id .. '_default', p.active == nil) then act_of(c).profile(nil) end
        for i, name in ipairs(p.names or {}) do  -- over a blank row, so a name with '##' in it shows whole
            local sx = imgui.GetCursorPosX()
            if kit.selectable(id .. '_' .. i, name == p.active) then act_of(c).profile(name) end
            imgui.SameLine(sx)
            imgui.Text(kit.esc(name))
        end
    end)
end

-- One row on a panel of its own: each character in a pill, green while running (blue while something holds it: AFK
-- sleep, a mount, a zone...) and red while stopped, holding its
-- name, its run button and its cog, `ui.widget_size` pixels high. Right-click a name for its profiles; hover it for
-- what it's doing. After them, while your target is a player you could track, Add Tracked.
local function draw_widget(view)
    local dl = imgui.GetWindowDrawList()
    local x0, y0 = imgui.GetCursorScreenPos()
    local h = widget_size(view.ui)
    local function px(k) return util.round(h * k) end
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
    local who = trackable(view)  -- last, so the characters' pills stay put as it comes and goes
    if who then pw = pw + add_tracked_size(pill_h, h) + apart end
    local ph = pill_h + pad * 2
    kit.fill(dl, x0, y0, pw, ph, P.bg, px(0.5))
    kit.outline(dl, x0, y0, pw, ph, P.border, px(0.5))

    local x, cy = x0 + pad, y0 + ph / 2
    for _, c in ipairs(list) do
        local id = c.remote and ('##sk_widget_' .. c.name) or '##sk_widget'
        kit.fill(dl, x, y0 + pad, c.pill, pill_h, c.halted and P.held or c.running and P.go or P.halt, pill_h / 2)
        local nx = x + lead
        kit.text_mid(dl, nx, cy, c.name, P.white, font, h)
        imgui.SetCursorScreenPos({ x, y0 + pad })
        imgui.Dummy({ lead + c.w, pill_h })  -- an item to hover, not a button: the widget still drags by its name
        local menu = id .. '_profiles'
        local state = c.halted and f('Halted (%s)', t(c.halted)) or t(c.running and 'Running' or 'Stopped')
        if imgui.IsItemHovered() then
            if not c.remote then  -- your status's tooltip names the profile already
                kit.tooltip(status_tip(view) .. t('\nRight-click to load a profile.'))
            elseif c.profiles then
                kit.tooltip(f('%s: %s\nProfile: %s\nRight-click to load another.', c.name, state,
                    c.profiles.active or t('Default')))
            else  -- its profiles never came (its file left them out)
                kit.tooltip(('%s: %s'):format(c.name, state))
            end
            if c.profiles and imgui.IsMouseClicked(1) then imgui.OpenPopup(menu) end
        end
        if c.profiles and imgui.IsPopupOpen(menu) then profile_menu(c, menu, h) end  -- the row's size, not Settings'
        -- The run button unlit: the pill says whether it runs.
        run_and_cog(c, { id .. '_run', id .. '_cog' }, nx + c.w + gap, cy - h / 2, h, math.floor(gap / 2), false,
            'Open or close Sidekick Settings')
        x = x + c.pill + apart
    end
    if who then add_tracked('##sk_widget_track', x, y0 + pad, pill_h, h, who) end
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
local LEFT, PAD, GUTTER = 24, 18, 12
local SLIDER_W, PICK_W, ROLL_W, RUNE_W, MANEUVER_W, SONG_W, CHIP_W = 180, 220, 286, 168, 90, 248, 30
local FOOT = { Profiles = true, ['UI / Log'] = true }  -- set apart at the foot of the list of pages

--[[ pg: where a page's rows go, from top to bottom: { dl, x, w, y (the next row's top), lx (where labels start),
     right (where controls end), alpha (0.55 under a section switched off) }. ]]--

-- A line `h` tall (ROW_H unless given): the band under the mouse, `label` at the left (cut to `room` pixels when
-- given: a control sits after it), `help` over the label's half, each as given (in the UI's language already).
-- Returns its first line's middle.
local function line(pg, label, help, h, color, room)
    h = h or S(ROW_H)
    local y = pg.y
    pg.y = y + h
    if kit.over(pg.x + S(4), y, pg.w - S(8), h) then kit.fill(pg.dl, pg.x + S(4), y, pg.w - S(8), h, P.hover, S(3), 0.8) end
    local cy = y + math.min(h, S(ROW_H)) / 2
    if label and room then label = kit.fit(label, room, kit.fonts.text, S(BODY)) end
    if label then kit.text_mid(pg.dl, pg.lx, cy, label, color or P.text, kit.fonts.text, S(BODY), pg.alpha) end
    if help and kit.over(pg.x, y, pg.w / 2, h) then kit.tooltip(help) end
    return cy
end

-- A control's id from its label (English, whatever the UI's language) and the setting it sets:
-- 'Rest under##sk_rest_mp'.
local function id_of(label, path) return label .. '##sk_' .. path:gsub('%.', '_') end

-- The helpers from here to `choice` take their label, help and unit in English and show them in the UI's language.

-- A slider for setting `path` (`value`), over its range in LIMITS unless `range` ({ min, max }) is given.
local function slider(pg, label, path, value, help, unit, range)
    local cy = line(pg, t(label), help and t(help), nil, nil, pg.right - S(SLIDER_W) - S(8) - pg.lx)
    local r = range or LIMITS[path]
    local v, moved = kit.slider(id_of(label, path), pg.right - S(SLIDER_W), cy, S(SLIDER_W), value, r[1], r[2], true, pg.alpha,
        unit and t(unit))
    if moved then act.set(path, v) end
end

-- A switch: `set(on)` when flipped, else setting `path` (also its id).
local function switch(pg, label, path, on, help, set)
    help = help and t(help)
    local cy = line(pg, t(label), help)
    local v, flipped = kit.switch(id_of(label, path), pg.right - S(kit.SW_W), cy, on, true, pg.alpha)
    kit.tip(help)
    if flipped then (set or function (x) act.set(path, x) end)(v) end
end

-- A drop-down at the right of a labelled line; `body` lists its choices.
local function pick(pg, label, id, shown, body, help, w)
    w = w or S(PICK_W)
    local cy = line(pg, t(label), help and t(help), nil, nil, pg.right - w - S(8) - pg.lx)
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
    local title = string.upper(t(s))
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
    if current == '' then return t('None') end
    return choices.names and choices.label(current) or f('%s (not available)', lang.name(current))
end

-- A drop-down's list for setting `path`: None (''), then each of `choices` ({ name, label }) by its
-- `field` (label), `current` ticked, each with the tooltip `tip(choice)` gives; `id` keeps their ids apart.
local function options(id, path, current, choices, field, tip)
    return function ()
        if kit.selectable(t('None') .. '##' .. id .. '_none', current == '') then act.set(path, '') end
        for _, c in ipairs(choices) do
            if kit.selectable(c[field or 'label'] .. '##' .. id .. '_' .. c.name, c.name == current) then act.set(path, c.name) end
            if tip then kit.tip(tip(c)) end
        end
    end
end

-- Names as choices, each shown by `label(name)`: the game's text (a member's name) unless given (a spell's,
-- lang.name).
local function named(names, label)
    label = label or game_text
    local out = { names = true, label = label }
    for i, n in ipairs(names) do out[i] = { name = n, label = label(n) } end
    return out
end

-- A labelled line's drop-down for setting `path` (None for ''), `w` wide (PICK_W).
local function choice(pg, label, id, path, current, choices, help, w, tip)
    pick(pg, label, label .. '##sk_' .. id, shown_pick(current, choices), options('sk_' .. id, path, current, choices, nil, tip),
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
local WHO_TIP = 'Untick to never clear debuffs on them, Doom too: someone else sees to them.'

-- Player chips, one row each: your party, alliance party B (group 'a'), alliance party C (group 'b'), then tracked.
-- An empty slot is left out, a row with none there too; but not a buff's target still on in one, so it can be
-- switched off before whoever takes the slot gets it.
local SLOT_GROUPS = { 'party', 'a', 'b', 'tracked' }

local function slot_groups(chips)
    local by, out = {}, {}
    for _, name in ipairs(SLOT_GROUPS) do by[name] = {} end
    for _, tg in ipairs(chips or {}) do
        local list = by[tg.group]
        if list and (tg.present or tg.on) then list[#list + 1] = tg end
    end
    for _, name in ipairs(SLOT_GROUPS) do
        if by[name][1] then out[#out + 1] = by[name] end
    end
    return out
end

local function slot_look(tg) return tg.on and 'on' or 'off' end

-- `chips` in their rows, from pg.lx. `make_id`, `tip_of` and `on_click` take the chip.
local function draw_slot_rows(pg, chips, make_id, tip_of, on_click)
    local laid, lines = {}, 0
    for _, group in ipairs(slot_groups(chips)) do
        local items = {}
        for j, tg in ipairs(group) do items[j] = { w = S(CHIP_W), t = tg } end
        local n = flow(items, pg.lx, pg.right, S(4))
        laid[#laid + 1] = { items = items, at = lines }
        lines = lines + n
    end
    if lines == 0 then return end
    local y = pg.y
    line(pg, nil, nil, lines * S(CHIP_LINE))
    for _, g in ipairs(laid) do
        for _, it in ipairs(g.items) do
            local tg = it.t
            if kit.chip(make_id(tg), it.x, y + (g.at + it.line - 0.5) * S(CHIP_LINE), it.w, tg.label, slot_look(tg), true, pg.alpha) then
                on_click(tg)
            end
            kit.tip(tip_of(tg))
        end
    end
end

-- Who healing looks after: ME and P1-P5, then B0-B5, C0-C5 and tracked players, as far as someone is there.
local function heal_targets(pg, h)
    local tip = t(HEAL_TIP)
    draw_slot_rows(pg, h.targets, function (tg)
        return tg.label .. '##sk_heal_' .. tg.slot
    end, function (tg)
        return tg.name and game_text(tg.name) .. '\n' .. tip or t('empty slot')
    end, function (tg)
        if tg.name then act.skip(tg.name, tg.on) end
    end)
end

local function draw_heal_settings(view, pg)
    local h = view.heal
    for _, l in ipairs(HEAL_LINES) do slider(pg, l[1], 'heal.' .. l[2], h[l[2]], l[3], '%') end
    -- A heal line at or under its danger line leaves nothing between them: only danger heals go.
    if h.threshold <= h.danger then note(pg, t('Heal under is at or under Danger under: no efficient heals, only danger ones.'), P.amber) end
    choice(pg, 'Focus', 'focus', 'heal.focus', h.focus, named(h.focus_names), 'Heal this member first, on its own lines.')
    for _, l in ipairs(HEAL_LINES) do
        slider(pg, 'Focus ' .. l[1]:lower(), 'heal.focus_' .. l[2], h['focus_' .. l[2]], 'For the focus member: ' .. l[3], '%')
    end
    if h.focus_threshold <= h.focus_danger then
        note(pg, t('Focus heal under is at or under Focus danger under: the focus member gets danger heals only.'), P.amber)
    end
    slider(pg, 'Cure potency +', 'heal.cure_potency', h.cure_potency, 'Cure potency % from gear, until a cure has been seen healing.', '%')
    slider(pg, 'Waltz potency +', 'heal.waltz_potency', h.waltz_potency, 'Waltz potency % from gear, until a waltz has been seen healing.', '%')
    slider(pg, 'Regen potency +', 'heal.regen_potency', h.regen_potency, 'HP per Regen tick from gear.')
    if h.stratagems then
        switch(pg, 'Keep a stratagem for healing', 'heal.reserve', h.reserve,
            'Buff rows never spend the last stratagem charge, so healing has one for Accession or Rapture.')
    end
    heal_targets(pg, h)
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
    if view.pet_sends then
        switch(pg, 'Send at your target', 'pet.at_t', view.pet_at_t == true,
            'Send your pet at your own target (<t>), and only while you are engaged, instead of the battle target.')
    end
end

local function draw_follow(view, pg)
    local fo = view.follow
    choice(pg, 'Leader', 'follow_target', 'follow.target', fo.target, named(fo.names), 'Who to follow; resting stands up when they leave too.')
    slider(pg, 'Follow past', 'follow.distance', fo.distance, 'Yalms.', 'y')
end

-- The leader is Follow's (follow.target), shown here too.
local function draw_rest(view, pg)
    local r, fo = view.rest, view.follow
    slider(pg, 'Rest under', 'rest.mp', r.mp, 'Rest when your MP falls under this %, until it is full.', '%')
    choice(pg, 'Leader', 'rest_leader', 'follow.target', fo.target, named(fo.names),
        'Stand up when they are further than Stand past. The same leader as Follow\'s.')
    slider(pg, 'Stand past', 'rest.distance', r.distance, 'Yalms from the leader.', 'y')
end

local function draw_afk(view, pg)
    local a = view.afk
    slider(pg, 'Sleep after', 'afk.minutes', a.minutes, 'Minutes with no one in your party moving and no combat.', 'm')
    if a.asleep then note(pg, t('Asleep: move to wake.'))
    elseif a.left then note(pg, f('Sleeps in %d min without movement or combat.', math.ceil(a.left / 60))) end
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

local function lucky(c) return f('Lucky %d, unlucky %d.', c.lucky, c.unlucky) end

local function draw_rolls(view, pg)
    local r = view.roll
    choice(pg, 'Roll 1', 'roll_first', 'roll.first', r.first, r.choices, nil, S(ROLL_W), lucky)
    if r.two then
        choice(pg, 'Roll 2', 'roll_second', 'roll.second', r.second, r.choices, nil, S(ROLL_W), lucky)
        if r.second ~= '' and r.second == r.first then note(pg, t('Roll 2 is Roll 1: one roll kept up')) end
    else
        note(pg, t('Roll 2: Corsair main job only'))
    end
    local labels, ids, index = {}, {}, 0
    for i, risk in ipairs(r.risks) do
        local word = util.capitalize(risk)
        labels[i] = t(word)
        ids[i] = word .. '##sk_roll_risk_' .. risk
        if risk == r.risk then index = i end
    end
    local cy = line(pg, t('Risk'), t(RISK_HELP))
    local px = S(BODY - 1)
    local picked, moved, over = kit.segments(ids, pg.right - kit.segments_width(labels, px), cy, labels, index, true, pg.alpha, px)
    if over then kit.tooltip(t(RISKS[r.risks[over]])) end
    if moved then act.set('roll.risk', r.risks[picked]) end
    if r.two then
        switch(pg, 'Max risk while an 11 is up', 'roll.max_at_11', r.max_at_11,
            'While one roll stands at 11, a Bust can\'t happen, so the other is doubled until it is 11 too (rolled again '
                .. 'when it can no longer be doubled). '
                .. 'Once no roll at 11 is up, the risk picked is back.')
        if r.eleven then note(pg, f('Risk at max: %s is at 11', lang.name(r.eleven)), P.teal) end
    end
    local l = r.last
    if l then
        local word = l.bust and ' (Bust)' or l.total == l.lucky and ' (lucky)' or l.total == 11 and ' (11)'
            or l.total == l.unlucky and ' (unlucky)' or nil
        note(pg, f('Last: %s %d%s', lang.name(l.name), l.total, word and t(word) or ''), l.bust and P.rose or P.text2)
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
            local name = set.key ~= 'area' and (set.name and game_text(set.name) or t('no one')) or nil
            local items = {}
            for i = 1, m.slots do items[i] = { w = box, i = i } end
            local lines = flow(items, pg.lx + col, pg.right, gap)
            -- A name shares the label line, so the picks start on the next one.
            local h = S(ROW_H) + (lines - (name and 0 or 1)) * S(CHIP_LINE)
            local help = SONG_HELP[set.key] and t(SONG_HELP[set.key]) or f('Sung on %s alone, through Pianissimo, whenever they lack one.',
                set.name and game_text(set.name) or t('whoever is in this party slot'))
            local cy = line(pg, set.label, help, h, dim and P.dim or P.text)
            for _, it in ipairs(items) do
                local icy = cy + (it.line - (name and 0 or 1)) * S(CHIP_LINE)
                slot_pick(('sk_song_%s_%d'):format(set.key, it.i), ('song.%s_%d'):format(set.key, it.i), set.picks[it.i],
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
        note(pg, f('Pianissimo: %s', m.avail), m.ready and P.teal or P.dim)
    else
        note(pg, t('Songs on one member need Pianissimo (Bard 20)'), P.dim)
    end
    if kit.over(pg.x, y, pg.w, pg.y - y) then kit.tooltip(t(SONGS_TIP)) end
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
    choice(pg, 'Entrust spell', 'geo_entrust_spell', 'geo.entrust_spell', g.entrust_spell, named(g.indi, lang.name),
        'The Indi- spell Entrust puts on that member whenever they lack its aura.')
end

-- What a set's slots show of each rune.
local SHOWS = { element = 'Each rune by the element it adds to your attacks.',
                resist = 'Each rune by the element it resists.', ailments = 'Each rune by the ailments it defends against.' }

local function rune_tip(r)
    return f('%s: adds %s, resists %s, against %s.', r.label or r.name, r.element, r.resist, r.ailments)
end

-- A rune for slot `i` of `set`, or None ('').
local function rune_pick(set, i, runes, x, cy, w, alpha)
    local current = set.picks[i]
    if slot_pick(('sk_rune_%s_%d'):format(set.key, i), ('rune.%s_%d'):format(set.key, i), current, runes, x, cy, w, alpha,
            set.shows, rune_tip) then
        kit.tooltip(shown_pick(current, runes, set.shows) .. '\n' .. t(SHOWS[set.shows]))
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
        local help = set.ward and f('Once %s is ready, its runes take the slots, then it fires in combat.', set.label)
            or t('The runes kept up the rest of the time.')
        local cy = line(pg, set.ward and nil or set.label, help, S(ROW_H) + lines * S(CHIP_LINE))
        if set.ward then
            local on, flipped = kit.switch(set.label .. '##sk_rune_' .. set.key, pg.lx, cy, set.on, true, pg.alpha)
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
        if slot_pick('sk_maneuver_' .. i, 'maneuver.slot_' .. i, m.picks[i], m.choices, it.x, cy + (it.line - 1) * S(CHIP_LINE),
                box, pg.alpha) then
            kit.tooltip(t('The same element in two slots keeps two up.'))
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
                local untrack = t('Untrack')
                local bw = kit.button_width(untrack)
                if kit.button('Untrack##sk_untrack_' .. p.name, pg.right - bw, cy, untrack, 'ghost', true, pg.alpha) then
                    act.untrack(p.name)
                end
                local s = ('%s %s'):format(p.tag, game_text(p.name)) .. (JOINED[p.kind] and t(JOINED[p.kind]) or p.job and ('  ' .. p.job) or '')
                if p.shared and not JOINED[p.kind] then s = s .. f('  (from %s)', p.shared) end
                local room = pg.right - bw - S(12) - pg.lx
                kit.text_mid(pg.dl, pg.lx, cy, kit.fit(s, room, kit.fonts.text, px), p.away and P.dim or P.text, kit.fonts.text, px, pg.alpha)
                local where = p.away and t(p.kind == 'tracked' and 'Out of range.' or 'In another zone.') or nil
                local from = p.shared and f('Tracked while %s\'s session lists them; Untrack keeps them off until tracked again.', p.shared)
                local help = where and from and (where .. '\n' .. from) or where or from
                if help and kit.over(pg.lx, cy - S(ROW_H) / 2, room, S(ROW_H)) then kit.tooltip(help) end
            end
        end
    end
    local who = view.track.target
    if who then
        local cy = line(pg, nil, nil)
        if kit.button(('Track %s##sk_track'):format(who), pg.lx, cy, f('Track %s', who), 'accent', true, pg.alpha) then act.track(who) end
        kit.tip(t('Heal, clear, raise and buff them too, with what reaches outside the party. This session only.'))
    else
        note(pg, view.session and f('Target a player outside the alliance in %s\'s game to track them there.', view.session)
            or t('Target a player outside your alliance to track them, or /sk track Name.'))
    end
end

-- A profile's line in the list: lit when it's the one in use. Returns clicked.
local function profile_item(pg, id, name, on, help)
    local ih = S(28)
    local x, y, w = pg.x + S(4), pg.y, pg.w - S(8)
    pg.y = y + ih
    local hovered, clicked = kit.hit(id, x, y, w, ih)
    kit.tip(help)
    local lit = kit.ease(id, on and 1 or 0, 20)
    if lit > 0.01 then
        kit.fill(pg.dl, x, y, w, ih, P.accent_bg, S(3), 0.9 * lit)
        kit.fill(pg.dl, x, y + S(5), S(2), ih - S(10), P.accent, S(1), lit)
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
    local cy = line(pg, t('Name'), t('A name for Save or Save as. Each job pair has its own profiles.'))
    local fw = S(260)
    kit.input('##sk_profile_name', pg.right - fw, cy, fw, profile_name, 64, t('Name to save under'))
    local typed = profile_name[1]:match('^%s*(.-)%s*$')
    -- { label, id, kind, help, what a click does }
    local buttons = {
        { 'Save', 'save', 'accent', 'Save the settings as they are now under this name. With a profile loaded and the name changed, '
            .. 'rename that profile instead. Never over another profile: Save as replaces one.',
          function () act.save_profile(typed) end },
        { 'Save as', 'save_as', 'ghost', 'Save the settings as they are now under this name, over any profile already named so.',
          function () act.save_profile(typed, true) end },
        { 'New', 'new', 'ghost', 'Every setting back to its default, on Default. Saved profiles are kept.',
          function () act.new_profile(); profile_name[1] = '' end },
    }
    if p.active then
        buttons[#buttons + 1] = { 'Delete', 'delete', 'danger', f('Delete %s, and go back to Default.', p.active),
                                  function () act.delete_profile(p.active) end }
    end
    for _, b in ipairs(buttons) do b.label = t(b[1]) end
    local by = line(pg, nil, nil, S(ROW_H) + S(4))
    local bx = pg.right - (#buttons - 1) * S(6)
    for _, b in ipairs(buttons) do bx = bx - kit.button_width(b.label) end
    for _, b in ipairs(buttons) do
        local clicked, bw = kit.button(b[1] .. '##sk_profile_' .. b[2], bx, by, b.label, b[3], true, pg.alpha)
        kit.tip(b[2] == 'delete' and b[4] or t(b[4]))  -- Delete's is filled in already
        if clicked then b[5]() end
        bx = bx + bw + S(6)
    end
    if typed ~= p.active and util.contains(p.names, typed) then note(pg, f('%s exists: Save as replaces it.', typed), P.amber) end
    subheader(pg, 'SAVED')
    if profile_item(pg, 'Default##sk_profile_default', t('Default'), p.active == nil,
            t('The working copy: your settings as they were before a profile was loaded.')) then
        act.profile(nil)
    end
    -- (drawn on the draw list, a name with '##' in it is shown whole)
    for i, name in ipairs(p.names) do
        if profile_item(pg, '##sk_profile_' .. i, name, name == p.active) then act.profile(name) end
    end
    pg.y = pg.y + S(6)
    note(pg, t('Changes save to the settings in use; to a profile only with Save.'), P.faint)
end

local function draw_recent(view, pg)
    if #view.recent == 0 then return note(pg, t('Nothing sent yet.')) end
    local px = S(SMALL + 0.5)
    for _, r in ipairs(view.recent) do
        local cy = line(pg, nil, nil, S(24))
        kit.text_right(pg.dl, pg.lx + S(30), cy, f('%ds', r.age), P.faint, kit.fonts.text, px, pg.alpha)
        local tx = pg.lx + S(40)
        kit.text_mid(pg.dl, tx, cy, r.text, P.text, kit.fonts.text, px, pg.alpha)
        local wx = tx + kit.measure(r.text, kit.fonts.text, px) + S(10)
        if pg.right - wx > S(30) then
            kit.text_mid(pg.dl, wx, cy, kit.fit(r.why, pg.right - wx, kit.fonts.text, px), P.dim, kit.fonts.text, px, pg.alpha)
        end
    end
end

-- Sidekick Settings' size, % of the size for the screen: view.ui.scale, held to its slider's range.
local function ui_scale(ui) return util.clamp(math.floor(tonumber(ui and ui.scale) or 100), 50, 200) end

-- The most choices a drop-down's list shows before it scrolls: view.ui.list_rows, held to its slider's range.
local function list_rows(ui) return kit.rows(ui and ui.list_rows) end

-- The themes in Sidekick's ui folder, Standard first, the one drawing lit: a click on another draws Sidekick with it,
-- on every character on this PC. One that failed to load says so, why in its tooltip, and isn't taken.
local function draw_themes(view, pg)
    local th = view.themes
    if not (th and th.list and th.list[1]) then return end
    subheader(pg, 'THEME')
    for _, it in ipairs(th.list) do
        local name = it.standard and t('Standard') or it.name
        local on = it.key == th.current
        if profile_item(pg, '##sk_theme_' .. it.key, it.error and f('%s (failed to load)', name) or name, on,
                it.error and f('Failed to load: %s', it.error) or it.file) and not on and not it.error then
            act.theme(it.key)
        end
    end
    pg.y = pg.y + S(6)
    note(pg, t('Every character on this PC draws with the theme picked here. To add one, put its .lua file in '
        .. 'Sidekick\'s ui folder (ui/README.md says how).'), P.faint)
end

-- Another session's shows only what it sent: its HUD is its own.
local function draw_ui(view, pg)
    if view.session then return draw_recent(view, pg) end
    draw_themes(view, pg)
    subheader(pg, 'HUD')
    switch(pg, 'Show the HUD', 'ui.open', view.ui.open == true,
        'The party\'s HP, MP and TP, apart from this window: closing either leaves the other. Also /sk hud.',
        act.hud)
    for _, l in ipairs(UI_SLIDERS) do
        slider(pg, l[1], 'ui.' .. l[2], view.ui[l[2]], l[5], l[6], { l[3], l[4] })
    end
    switch(pg, 'Hide unused MP bars', 'ui.hide_mp', view.ui.hide_mp ~= false,
        'Leave out the MP bar of a member or pet with no MP (0/0): a job without it, a wyvern, a jug pet. '
        .. 'A tracked player\'s stays: their MP can\'t be read.')
    switch(pg, 'Lock position', 'ui.locked', view.ui.locked == true,
        'Keep the HUD and the widget where they are: dragging them no longer moves them.')
    switch(pg, 'Widget', 'ui.widget', view.ui.widget == true,
        'One row of its own: each character\'s name (yours, then each other Sidekick session\'s), its Start/Stop and its '
        .. 'Settings. Right-click a name to load a profile. Up with the HUD closed too. Also /sk widget.')
    slider(pg, 'Widget size', 'ui.widget_size', widget_size(view.ui), 'Pixels: the widget\'s text and icons\' height.',
        'px', WIDGET_SIZES)
    subheader(pg, 'Sidekick Settings')
    slider(pg, 'Size', 'ui.scale', ui_scale(view.ui),
        'This window\'s size, % of the size that suits your screen. Taken up once the slider is let go.', '%', { 50, 200 })
    slider(pg, 'Drop-down rows', 'ui.list_rows', list_rows(view.ui),
        'The most choices a drop-down or the widget\'s profile menu shows at once; scroll for the rest. Lower it on a '
        .. 'small screen.', nil,
        kit.LIST_ROWS)
    subheader(pg, 'AUTOMATION')
    switch(pg, 'After zone stop', 'ui.zone_stop', view.ui.zone_stop == true,
        'Stop automation each time you zone, logging in and out too: it stays stopped in the new zone until you start '
        .. 'it.')
    switch(pg, 'Always load stopped', 'ui.load_stopped', view.ui.load_stopped ~= false,
        'Start stopped each time Sidekick loads. Off: automation comes back as it was when Sidekick last ran, running '
        .. 'or stopped.')
    subheader(pg, 'LOG')
    draw_recent(view, pg)
    subheader(pg, 'CLIENT')
    switch(pg, 'Japanese client', 'japanese', view.japanese,
        'Send spell, ability and item names in Japanese, and show Sidekick in Japanese, on every job.')
    -- (only ever shown in English: the window can't draw Japanese then)
    if view.japanese and not lang.drawable then
        local needs = kit.dynamic and 'a Japanese font in Windows\' Fonts (Meiryo, Yu Gothic or MS Gothic)'
            or 'a Japanese font in Ashita\'s boot config, [ashita.imgui.fonts] with is_jp (Sidekick\'s README says '
            .. 'how), and a restart'
        note(pg, 'This window stays in English: Japanese needs ' .. needs .. '. Names still go out in Japanese.'
            .. (kit.ja_error and ' (Ashita\'s fonts couldn\'t be read: ' .. kit.ja_error .. ')' or ''), P.amber)
    end
end

-- Rows ------------------------------------------------------------------------------

local HOLD_TIP = 'Wait while a modifier picked here can\'t go with the spell (on recast, too few charges, the wrong Arts, '
    .. 'Accession unable to spread it, or short of MP for it); otherwise the spell goes without it.'

local MATCH_WEATHER_TIP = 'Cast the storm matching the zone\'s weather. With no elemental weather, the one picked goes.'
local MATCH_ELEMENT_TIP = 'Cast the tier matching your weather (a storm on you first), else the day\'s element. '
    .. 'With no match (Lightsday, say: there is no light one), the one picked goes.'
local TIER_TIP = 'Untick to never heal with it; the other tiers still go.'
local WAKE_TIP = 'Untick to never heal with it; the other tiers still go, and it still wakes a sleeper.'

-- A row's gate, as a pill after its name: Combat in the palette's rose, Idle in its teal. `word`, when
-- there, is its key in core/ja.lua: Idle's there is the rune set's 通常時, a gate's 戦闘外.
local GATES = {
    combat = { label = 'Combat', tint = P.rose,
               help = 'Only in combat: while there is a battle target, and for a few seconds after.',
               fixed = 'Built in: it only goes in combat.' },
    idle = { label = 'Idle', word = 'Idle (gate)', tint = P.teal,
             help = 'Only out of combat: once the battle target has been gone a few seconds.',
             fixed = 'Built in: it only goes out of combat.' },
}
-- The pills in the order they're drawn, by the gate that leads: both (with no gate, Combat first), or one alone.
local BOTH = { combat = { 'combat', 'idle' }, idle = { 'idle', 'combat' } }
local ALONE = { combat = { 'combat' }, idle = { 'idle' } }
local GATE_GAP = 4

local function gate_label(gate)
    local spec = GATES[gate]
    return lang.on and t(spec.word or spec.label) or spec.label
end

-- The room row `r`'s pills take, hovered or not, so its name leaves it either way and the one set stays put.
local function gate_room(r)
    if r.gate_fixed then return GATES[r.gate] and kit.pill_width(gate_label(r.gate)) or 0 end
    return kit.pill_width(gate_label('combat')) + S(GATE_GAP) + kit.pill_width(gate_label('idle'))
end

-- The gates row `r` shows, in order (nil for none): the one it's set to (or has built in), then, while the row is
-- hovered (`reveal`, eased: the other fades out as it ends) and its gate isn't built in, the other. `lead` (revealed)
-- goes first.
local function gate_order(r, reveal, lead)
    if r.gate_fixed or reveal <= 0 then return ALONE[r.gate] end
    return BOTH[lead or 'combat']
end

-- The gates of `order` from x, centred on cy: a click on one sets the row's gate to it (the other goes), a click on the
-- one set clears it. The one not set is drawn at `reveal`; all dimmed while the row is off, as its name is. Ids by the
-- English words, whatever the language.
local function draw_gates(id, r, order, x, cy, reveal, alpha)
    alpha = alpha * (r.on and 1 or 0.5)
    for _, gate in ipairs(order) do
        local spec, set, label = GATES[gate], gate == r.gate, gate_label(gate)
        if kit.pill(spec.label .. '##' .. id .. '_gate', x, cy, label, spec.tint, set, not r.gate_fixed,
                alpha * (set and 1 or reveal)) then
            act.gate(r.key, not set and gate or nil)
        end
        if r.gate_fixed then kit.tip(t(spec.fixed))
        else
            kit.tip(t(spec.help) .. (set and t('\nClick again to let it go any time.') or '')
                .. (r.also and f('\nShared with its row under %s: set here, it is set there too.', t(r.also)) or ''))
        end
        x = x + kit.pill_width(label) + S(GATE_GAP)
    end
end

-- By window and row id (kit.prefix, as kit.ease's), while the pointer is over the row: the gate it had when the
-- pointer came (false for none).
local leads = {}

-- How far the pointer's being over a row's band (`y`, `h` tall) has eased in, for its gate pills, and the gate they
-- lead with: the one set (`gate`), but while the pointer stays, the one set when it came, so a click never moves a pill
-- from under it (Idle clicked stays second, where a second click clears it; it goes first once the pointer leaves).
local function revealed(pg, id, y, h, gate)
    local over, lead, key = kit.over(pg.x + S(4), y, pg.w - S(8), h), gate, kit.prefix .. id
    if not over then
        leads[key] = nil
    else
        if leads[key] == nil then leads[key] = gate or false end
        lead = leads[key]
    end
    return kit.ease(id .. '_gates', over and 1 or 0, 22), lead
end

local NAME_MIN = 72  -- px a row's name keeps (when it's that long) before its readiness gives way

-- Row `r`'s readiness, ending at `right`: ready or why not, cut to leave its name (`label`, from `lx`: NAME_MIN of
-- it at least) and its gate pills' `room`; with the pointer over it, its action's name (r.action), after the reason
-- in full when that's cut. Returns where it starts.
local function row_readiness(pg, r, label, lx, right, cy, room)
    local px = S(SMALL + 0.5)
    local keep = math.min(kit.measure(label, kit.fonts.text, S(BODY)), S(NAME_MIN))
    local avail = kit.fit(r.avail, right - lx - keep - S(8) - room - S(12), kit.fonts.text, px)
    local aw = kit.measure(avail, kit.fonts.text, px)
    readiness(pg, right, cy, avail, r.ready)
    local whole = avail ~= r.avail and r.avail or nil
    if (whole or r.action) and kit.over(right - aw, cy - S(10), aw, S(20)) then
        kit.tooltip(whole and r.action and whole .. '\n' .. r.action or whole or r.action)
    end
    return right - aw
end

-- One row per settings key: its name (and how many you carry), ready or why not, its switch. Under that, on their
-- own lines: its pick, then its targets a row at a time (ME P1-P5, then B0-B5, C0-C5 and tracked; no empty slot), then its
-- modifiers fired before its spell (Penury, Celerity, Accession, Embolden...) and Hold, then a heal's tiers as
-- checkboxes. Its gate's pills (Combat, Idle) follow its name, pick or not.
local function family_row(pg, sid, r)
    local id = sid .. '_' .. r.key
    local n = r.count or r.tools
    local hold = t('Hold')
    local laid, tlines = {}, 0
    for _, group in ipairs(slot_groups(r.targets)) do
        local items = {}
        for j, tg in ipairs(group) do items[j] = { w = S(CHIP_W), t = tg } end
        laid[#laid + 1] = { items = items, at = tlines }
        tlines = tlines + flow(items, pg.lx, pg.right, S(4))
    end
    local mods = {}
    for _, m in ipairs(r.mods or {}) do mods[#mods + 1] = { w = kit.chip_width(m.label), m = m } end
    if r.mods then mods[#mods + 1] = { w = kit.chip_width(hold), hold = true } end
    local mod_lines = #mods > 0 and flow(mods, pg.lx, pg.right, S(4)) or 0
    local tiers, px_tier = {}, S(SMALL + 0.5)
    for _, tr in ipairs(r.tiers or {}) do
        tiers[#tiers + 1] = { w = S(kit.CB) + S(6) + kit.measure(tr.label, kit.fonts.text, px_tier), pre = S(8), tr = tr }
    end
    local tier_lines = #tiers > 0 and flow(tiers, pg.lx, pg.right, S(4)) or 0
    local pick_lines = r.choices and 1 or 0
    local lines = pick_lines + tlines + mod_lines + tier_lines
    local y0, h = pg.y, S(ROW_H) + lines * S(CHIP_LINE) + (lines > 0 and S(4) or 0)
    local cy = line(pg, nil, nil, h)
    local reveal, lead = revealed(pg, id, y0, h, r.gate)
    local gates, room = gate_order(r, reveal, lead), gate_room(r)

    -- An item shows how many you carry, ninjutsu their tools; ### keeps its id while the count changes.
    local sx = pg.right - S(kit.SW_W)
    local on, flipped = kit.switch(n and ('%s (%d)###%s'):format(r.label, n, id) or r.label .. '##' .. id, sx, cy, r.on, true, pg.alpha)
    if flipped then act.row(r.key, on) end
    local label = n and ('%s (%d)'):format(r.label, n) or r.label
    local ax = row_readiness(pg, r, label, pg.lx, sx - S(12), cy, room)
    local name = kit.fit(label, ax - S(12) - pg.lx - room - S(8), kit.fonts.text, S(BODY))
    kit.text_mid(pg.dl, pg.lx, cy, name, r.on and P.text or P.dim, kit.fonts.text, S(BODY), pg.alpha)
    if gates then
        draw_gates(id, r, gates, pg.lx + kit.measure(name, kit.fonts.text, S(BODY)) + S(8), cy, reveal, pg.alpha)
    end

    local any = false
    for _, m in ipairs(r.mods or {}) do any = any or m.on end
    local top = cy + S(ROW_H) / 2 + S(CHIP_LINE) / 2 - S(2)  -- the first line under the name
    local line_i = 0
    if r.choices then
        line_i = 1
        kit.dropdown('##pick_' .. id, pg.lx, top, S(PICK_W), r.choice, true, pg.alpha, function ()
            for _, c in ipairs(r.choices) do
                if kit.selectable(c.label, c.name == r.pick) then act.pick(r.key, c.name) end
            end
        end)
        -- Enspells, storms: Match beside the pick, which it stands in for while the sky matches a tier.
        if r.match ~= nil then
            local label = t(r.match_rule == 'weather' and 'Weather' or 'Weather/Day')
            if kit.chip('Match##' .. id .. '_match', pg.lx + S(PICK_W) + S(8), top, kit.chip_width(label), label,
                r.match and 'on' or 'off', true, pg.alpha) then
                act.match(r.key, not r.match)
            end
            kit.tip(t(r.match_rule == 'weather' and MATCH_WEATHER_TIP or MATCH_ELEMENT_TIP))
        end
    end
    for _, g in ipairs(laid) do
        for _, it in ipairs(g.items) do
            local tg = it.t
            local icy = top + (line_i + g.at + it.line - 1) * S(CHIP_LINE)
            if kit.chip(tg.label .. '##' .. id .. tg.slot, it.x, icy, it.w, tg.label, slot_look(tg), true, pg.alpha) then
                act.target(r.key, tg.slot, not tg.on)
            end
            kit.tip(tg.name and game_text(tg.name) or t('empty slot'))
        end
    end
    line_i = line_i + tlines
    for _, it in ipairs(mods) do
        local icy = top + (line_i + it.line - 1) * S(CHIP_LINE)
        if it.hold then
            -- With no modifier on, it waits for nothing: an outline, but kept and still clickable.
            if kit.chip('Hold##' .. id .. '_hold', it.x, icy, it.w, hold, not any and 'empty' or r.hold and 'held' or 'off', true, pg.alpha) then
                act.hold(r.key, not r.hold)
            end
            kit.tip(t(HOLD_TIP) .. (any and '' or t('\nNo modifier is on here: it waits for nothing.')))
        else
            local m = it.m
            if kit.chip(m.label .. '##' .. id .. '_mod_' .. m.name, it.x, icy, it.w, m.label, m.on and 'on' or 'off', true, pg.alpha) then
                act.mod(r.key, m.name, not m.on)
            end
            kit.tip(m.note and f('%s first: %s', lang.name(m.name), m.note) or lang.name(m.name))
        end
    end
    line_i = line_i + mod_lines
    for _, it in ipairs(tiers) do
        local tr, icy = it.tr, top + (line_i + it.line - 1) * S(CHIP_LINE)
        local ticked, ticks = kit.checkbox(tr.label .. '##sk_heal_spell_' .. tr.name, it.x, icy, tr.on, true, pg.alpha)
        if ticks then act.heal_spell(tr.name, ticked) end
        kit.tip(t(tr.wakes and WAKE_TIP or TIER_TIP))
        kit.text_mid(pg.dl, it.x + S(kit.CB) + S(6), icy, tr.label, r.on and tr.on and P.text2 or P.dim, kit.fonts.text,
            px_tier, pg.alpha)
    end
end

local REMOVER_TIP = 'Untick to never use it: the debuffs only it removes are greyed out below.'
local DEBUFF_TIP = 'Untick to leave it on: worth it for what doesn\'t matter to your job (MP Down on a Warrior).'
local DOOM_RETRIES_TIP = 'Times Cursna is cast again after it misses a Doom; then the Doom is taken as gone. '
    .. 'Yours and your party\'s Doom are read from the game: Cursna goes on while it shows.\n'
    .. 'Trust, Alliance and Tracked targets: their debuffs are read from what this character sees, so if '
    .. 'someone else removed the Doom, a Cursna that finds nothing may look the same as a miss.'

-- Debuff removal's spells and abilities, a checkbox each: its name, then ready or why not at the right.
local function remover_row(pg, sid, r)
    local id, y0 = sid .. '_' .. r.key, pg.y
    local cy = line(pg, nil, nil)
    local reveal, lead = revealed(pg, id, y0, S(ROW_H), r.gate)
    local gates, room = gate_order(r, reveal, lead), gate_room(r)
    local on, flipped = kit.checkbox(r.label .. '##' .. sid .. '_with_' .. r.key, pg.lx, cy, r.on, true, pg.alpha)
    if flipped then act.row(r.key, on) end
    kit.tip(t(REMOVER_TIP) .. (r.shared and t('\nIt heals too: unticked here, it is unticked under Heal.') or ''))
    local lx = pg.lx + S(kit.CB) + S(10)
    local ax = row_readiness(pg, r, r.label, lx, pg.right, cy, room)
    local name = kit.fit(r.label, ax - S(12) - lx - room - S(8), kit.fonts.text, S(BODY))
    kit.text_mid(pg.dl, lx, cy, name, r.on and P.text or P.dim, kit.fonts.text, S(BODY), pg.alpha)
    if gates then draw_gates(id, r, gates, lx + kit.measure(name, kit.fonts.text, S(BODY)) + S(8), cy, reveal, pg.alpha) end
end

-- A tab for everyone, then one for each player removal runs on, then None, All and the
-- tab's debuffs. Everyone's are those of each player without a set of their own.
local function debuff_panel(pg, pane, debuffs, who)
    local everyone = t('Everyone')
    local tabs = { { label = everyone, id = '*', w = kit.chip_width(everyone),
                     tip = t('Everyone without a set of their own, and whoever joins. A player\'s first change gives them their own.') } }
    for _, tg in ipairs(who or {}) do
        if tg.on and tg.name then
            tabs[#tabs + 1] = { label = tg.label, id = tg.slot, name = tg.name, w = S(CHIP_W), tip = game_text(tg.name) }
        end
    end
    local active = tabs[1]
    for _, tab in ipairs(tabs) do
        if tab.name ~= nil and tab.name == pane.debuff then active = tab end
    end
    pane.debuff = active.name
    local items = {}
    for i, tab in ipairs(tabs) do items[i] = { w = tab.w, t = tab } end
    local n = flow(items, pg.lx, pg.right, S(4))
    local y = pg.y
    line(pg, nil, nil, n * S(CHIP_LINE))
    for _, it in ipairs(items) do
        local tab = it.t
        if kit.chip(tab.label .. '##remove_tab_' .. tab.id, it.x, y + (it.line - 0.5) * S(CHIP_LINE), it.w,
                tab.label, tab == active and 'on' or 'off', true, pg.alpha) then
            active, pane.debuff = tab, tab.name
        end
        kit.tip(tab.tip)
    end
    local whose = active.name or '*'
    local none, all, names = t('None'), t('All'), {}
    local chips = { { w = kit.button_width(none), kind = 'none' }, { w = kit.button_width(all), kind = 'all' } }
    for _, r in ipairs(debuffs) do
        chips[#chips + 1] = { w = kit.chip_width(r.label), r = r }
        names[#names + 1] = r.key
    end
    local clines = flow(chips, pg.lx, pg.right, S(4))
    local cy0 = pg.y
    line(pg, nil, nil, clines * S(CHIP_LINE))
    for _, it in ipairs(chips) do
        local icy = cy0 + (it.line - 0.5) * S(CHIP_LINE)
        if it.kind == 'none' then
            if kit.button('None##remove_debuff_none', it.x, icy, none, 'ghost', true, pg.alpha) then
                act.debuffs(names, false, active.name)
            end
            kit.tip(t('Leave all of these debuffs on.'))
        elseif it.kind == 'all' then
            if kit.button('All##remove_debuff_all', it.x, icy, all, 'ghost', true, pg.alpha) then
                act.debuffs(names, true, active.name)
            end
            kit.tip(t('Remove all of these debuffs.'))
        else
            local r = it.r
            local on = r.on
            if active.name and r.own and r.own[active.name] ~= nil then on = r.own[active.name] end
            local usable = r.usable ~= false
            if kit.chip(r.label .. '##remove_' .. whose .. '_' .. r.key, it.x, icy, it.w, r.label,
                    not usable and 'empty' or on and 'on' or 'off', usable, pg.alpha) then
                act.debuff(r.key, not on, active.name)
            end
            local by = r.action ~= '' and f('Removed by %s', r.action) .. '\n' or ''
            local left = not on and not usable and t('\nSwitched off: left on once something removes it again.') or ''
            local how = usable and DEBUFF_TIP or 'Tick something above that removes it.'
            kit.tip(('%s%s\n%s%s'):format(by, r.avail, t(how), left))
        end
    end
end

-- Spells and abilities, then items (rows with a count) under a heading of their own. Debuff removal lists who it
-- runs on, then its spells and abilities as checkboxes, then a tab of debuff chips for everyone and for each player
-- it runs on.
local function section_rows(pg, s, has_body, pane)
    local removers, debuffs, acts, items = {}, {}, {}, {}
    for _, r in ipairs(s.rows) do
        table.insert(r.remover and removers or r.debuff and debuffs or r.count and items or acts, r)
    end
    if s.who then
        local tip = t(WHO_TIP)
        draw_slot_rows(pg, s.who, function (tg)
            return tg.label .. '##sk_remove_who_' .. tg.slot
        end, function (tg)
            return tg.name and game_text(tg.name) .. '\n' .. tip or t('empty slot')
        end, function (tg)
            if tg.name then act.who(tg.name, not tg.on) end
        end)
    end
    if #removers > 0 then
        subheader(pg, 'REMOVERS')
        for _, r in ipairs(removers) do
            remover_row(pg, s.id, r)
            if r.doom_retries then slider(pg, 'Doom retries', 'remove.doom_retries', r.doom_retries, DOOM_RETRIES_TIP) end
        end
    end
    if #debuffs > 0 then
        subheader(pg, 'DEBUFFS')
        debuff_panel(pg, pane, debuffs, s.who)
    end
    if #acts > 0 and has_body then subheader(pg, 'ACTIONS') end
    for _, r in ipairs(acts) do family_row(pg, s.id, r) end
    if #items > 0 then
        subheader(pg, 'ITEMS')
        for _, r in ipairs(items) do family_row(pg, s.id, r) end
    end
end

-- Sidekick Settings -----------------------------------------------------------------------

local SWITCH_HELP = {
    follow = 'Follow the leader once they are further away than the distance: mounted, in a safe zone and with '
        .. 'automation stopped too.',
    heal = 'Heal the party with the rows that are on.',
    revive = 'Raise fallen members with the rows that are on.',
    wake = 'Wake a sleeping member with a cure or waltz that is on under Heal; an area one for two or more.',
    remove = 'Remove the debuffs that are on for the players that are on, with the spells, abilities and items ticked.',
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
    rest = 'Rest for MP out of combat once it falls under a line; stand at full MP, or when the leader leaves.',
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
    local line_end, help = pg.right, SWITCH_HELP[s.id] and t(SWITCH_HELP[s.id])
    if s.on ~= nil then
        local on, flipped = kit.switch(s.title .. '##sk_on_' .. s.id, line_end - S(kit.SW_W), cy, s.on, true)
        kit.tip(help)
        if flipped then act.section(s.id, on) end
        line_end = line_end - S(kit.SW_W) - S(12)
    end
    local font, px, spacing = kit.fonts.semi_italic, S(SMALL), math.max(1, S(1.2))
    local title = string.upper(t(s.title))
    local tw = kit.text_spaced(nil, 0, 0, title, nil, font, px, spacing)
    local hovered, clicked = kit.hit('##sk_fold_' .. s.id, pg.x + S(2), cy - S(12), S(LEFT) - S(2) + tw + S(8), S(24))
    kit.tip(help)
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
    if s.rows then section_rows(pg, s, body ~= nil, pane) end
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
    local hovered, clicked = kit.hit('##sk_page_' .. page.name, x, y, w, ih)
    if clicked then pane.page = page.name end
    local active = pane.page == page.name
    local lit = kit.ease('nav.' .. page.name, active and 1 or 0, 20)
    if lit > 0.01 then
        kit.fill(dl, x, y, w, ih, P.accent_bg, 0, 0.9 * lit)
        kit.fill(dl, x, y, S(2), ih, P.accent, 0, lit)
    end
    if hovered and not active then kit.fill(dl, x, y, w, ih, P.hover, 0, 0.7) end
    local cy, dx = y + ih / 2, x + S(PAD) + S(4)
    if page.switches and page.on then kit.circle(dl, dx, cy, S(3.5), P.teal)
    elseif page.switches then kit.ring(dl, dx, cy, S(3.5), P.faint) end
    if hovered and page.switches and not page.on then kit.tooltip(t('Every switch here is off.')) end
    local nx, px, name = x + S(PAD) + S(16), S(BODY + 0.5), t(page.name)
    kit.text_mid(dl, nx, cy, name, active and P.white or P.text, kit.fonts.text, px)
    if tag then
        local room = x + w - S(PAD) - (nx + kit.measure(name, kit.fonts.text, px) + S(8))
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
    kit.text_mid(dl, x + pad, y + S(24), kit.fit(name or t('Sidekick Settings'), w - pad * 2, kit.fonts.semi, title_px), P.white, kit.fonts.semi, title_px)
    kit.text_mid(dl, x + pad, y + S(46), kit.fit(view.job, w - pad * 2, kit.fonts.text, small), P.dim, kit.fonts.text, small)
    kit.circle(dl, x + pad + S(3), y + S(65), S(3), st.running and P.teal or P.faint)
    kit.text_mid(dl, x + pad + S(12), y + S(65), t(st.state), st.running and P.teal or P.dim, kit.fonts.text, small)
    if kit.over(x, y, w, S(78)) then
        kit.tooltip(name and t('Changes here are sent to that session, which applies them within a second or so.') or status_tip(view))
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
    kit.text_mid(dl, x + pad, fy - S(12), t('SETUP'), P.faint, kit.fonts.semi, S(SMALL - 1.5))
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
    if close_mark('##sk_settings_close', cx, cy, box) then open[1] = false end
    kit.tip(t('Close'))
    kit.line(dl, x, y + S(TITLE_H), x + w, y + S(TITLE_H), P.border)
end

-- The page's sections, scrolling under its title. A Lua error inside still ends the child, then is raised.
local function draw_page(view, pane, page, x, y, w, h, open)
    title_bar(t(page.name), page.name == 'Profiles' and view.profiles.active and f('loaded: %s', view.profiles.active) or nil,
        x, y, w, open)
    imgui.SetCursorScreenPos({ x, y + S(TITLE_H) + 1 })
    local ok, err = true, nil
    if kit.child('##sk_pane_' .. page.name, w, h - S(TITLE_H) - 1) then
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
    local vars = kit.push_style(SETTINGS_COLOURS, ImGuiStyleVar_WindowPadding, { 0, 0 }, ImGuiStyleVar_WindowBorderSize, 0,
        ImGuiStyleVar_ItemSpacing, { 0, 0 }, ImGuiStyleVar_ScrollbarSize, S(6), ImGuiStyleVar_ScrollbarRounding, S(3))
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
    kit.pop_style(SETTINGS_COLOURS, vars)
    if not ok then return err end
end

-- The HUD or the widget: a window ImGui draws nothing of, `draw(view)` inside under pcall
-- (Begin, the body, End); returns the error the body raised.
local NO_COLOURS = {}
local function panel(title, flags, draw, view)
    local vars = kit.push_style(NO_COLOURS, ImGuiStyleVar_WindowPadding, { 0, 0 }, ImGuiStyleVar_WindowBorderSize, 0)
    local shown = imgui.Begin(title, true, flags + (view.ui.locked and ImGuiWindowFlags_NoMove or 0))
    kit.pop_style(NO_COLOURS, vars)
    local ok, err = true, nil
    if shown then ok, err = pcall(draw, view) end
    imgui.End()  -- ImGui keeps where it was dragged, in imgui.ini
    if not ok then return err end
end

local ADD_FLAGS = HUD_FLAGS + ImGuiWindowFlags_NoMove + ImGuiWindowFlags_NoSavedSettings + ImGuiWindowFlags_NoFocusOnAppearing

-- The HUD's Add Tracked pill (`at`, from draw_labels), in a window of its own put on it each frame and just its size:
-- the HUD's labels sit outside the HUD's window, where a click goes to the game, and this one's has to come here. No
-- minimum size or rounding, so it's no bigger than the pill and takes no click beside it. On whole pixels, as ImGui
-- floors a window's place: a pill half a pixel lower would lose its bottom edge to its window's clip. Returns the error
-- it raised.
local function add_window(at)
    local x, y, w = math.floor(at.x), math.floor(at.y), add_tracked_size(at.ph, at.px)
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always)
    imgui.SetNextWindowSize({ w, at.ph }, ImGuiCond_Always)
    local vars = kit.push_style(NO_COLOURS, ImGuiStyleVar_WindowPadding, { 0, 0 }, ImGuiStyleVar_WindowBorderSize, 0,
        ImGuiStyleVar_WindowMinSize, { 1, 1 }, ImGuiStyleVar_WindowRounding, 0)
    local shown = imgui.Begin('Sidekick Add Tracked', true, ADD_FLAGS)
    kit.pop_style(NO_COLOURS, vars)
    local ok, err = true, nil
    if shown then ok, err = pcall(add_tracked, '##sk_add_tracked', x, y, at.ph, at.px, at.who) end
    imgui.End()
    if not ok then return err end
end

local function settings_window(view)
    local open = { true }
    local err = settings_shell('Sidekick Settings', open, 0, function (x, y, side, pw, ph)
        draw_settings(view, '', nil, x, y, side, pw, ph, open)
    end)
    if not open[1] then
        settings_open = false
        act.settings(false)
    end
    return err
end

-- Another session's Sidekick Settings, from the view it published, its changes sent to it; until its first view comes, or
-- from a session running other code, a line saying so.
local function remote_window(r, index)
    local open = { true }
    local mine = act
    local err = settings_shell(('Sidekick Settings: %s###sk_settings_%s'):format(r.name, r.name), open, index, function (x, y, side, pw, ph)
        act = mine.remote(r.name)
        if r.view and not r.other then return draw_settings(r.view, r.name, r.name, x, y, side, pw, ph, open) end
        local dl = imgui.GetWindowDrawList()
        kit.text_mid(dl, x + S(PAD), y + S(24), kit.fit(r.name, side - S(PAD) * 2, kit.fonts.semi, S(BODY + 2)), P.white, kit.fonts.semi, S(BODY + 2))
        title_bar(t('Sidekick Settings'), nil, x + side + 1, y, pw - side - 1, open)
        local pg = { dl = dl, x = x + side + 1, w = pw - side - 1, y = y + S(TITLE_H) + S(14), lx = x + side + 1 + S(LEFT),
                     right = x + pw - S(PAD), alpha = 1 }
        note(pg, r.other and f('%s runs another version of Sidekick: /addon reload sidekick there.', r.name)
            or f('Waiting for %s\'s session...', r.name))
    end)
    act = mine
    if not (open[1] and not err) then act.watch(r.name, false) end  -- a view that won't draw isn't drawn again
    return err
end

-- Once, at load, before any frame: Segoe UI, which ImGui 1.81 (Ashita 4.16) takes only then.
function window.load() kit.bake() end

-- One frame. A Lua error raised while drawing is raised again after the windows
-- are ended, so ImGui stays balanced and Sidekick reports it. Its words are in the
-- client's language once the kit has a font for it (Meiryo for Japanese).
function window.render(view, act_)
    act = act_
    if not imgui.IsAnyItemActive() then user_scale = ui_scale(view.ui) / 100 end  -- not mid-drag: the window would move under it
    kit.frame(user_scale, view.japanese == true)
    kit.list_rows = list_rows(view.ui)
    lang.use(view.japanese)
    local open = view.ui.open ~= false
    settings_open = view.ui.settings == true  -- /sk's, apart from the HUD
    if view.track.target ~= asked then asked = nil end  -- shown tracked, or someone else targeted: Add Tracked's back
    local err
    if open then
        kit.prefix = 'hud|'
        hud_add = nil
        err = panel('Sidekick', HUD_FLAGS, draw_hud, view)
        if hud_add then err = add_window(hud_add) or err end
    end
    if view.ui.widget then
        kit.prefix = 'widget|'
        err = panel('SK Widget', WIDGET_FLAGS, draw_widget, view) or err
    end
    kit.prefix = ''
    if settings_open then err = settings_window(view) or err end
    for i, r in ipairs(view.remote or {}) do  -- the cogs' and /sk alt's, apart from the HUD too
        kit.prefix = r.name .. '|'
        err = remote_window(r, i) or err
    end
    kit.prefix = ''
    kit.tooltips()
    if err then error(err, 0) end
end

return window
