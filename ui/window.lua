--[[
    The Sidekick3 window: ImGui only. It draws the view ui/model.lua builds and
    turns clicks into model mutators; it reads no game state and decides nothing.

    Ashita's binding (as v2 found it): widget values are one-element tables
    ({ true }, { 75 }), and Text, TextColored and SetTooltip take a printf
    format, so any '%' shown goes through text() / tip(), which double it.
]]--

local imgui = require('imgui')
local model = require('ui.model')

local window = {}

local GREEN = { 0.6, 1.0, 0.6, 1.0 }
local RED = { 1.0, 0.55, 0.55, 1.0 }
local YELLOW = { 1.0, 0.85, 0.4, 1.0 }
local GREY = { 0.55, 0.55, 0.55, 1.0 }
local HP_BAR = { ok = { 0.2, 0.55, 0.2, 1.0 }, low = { 0.7, 0.55, 0.1, 1.0 }, critical = { 0.7, 0.15, 0.15, 1.0 } }
-- Button, hovered, active.
local START = { { 0.15, 0.5, 0.15, 1.0 }, { 0.2, 0.6, 0.2, 1.0 }, { 0.25, 0.7, 0.25, 1.0 } }
local STOP = { { 0.6, 0.15, 0.15, 1.0 }, { 0.7, 0.2, 0.2, 1.0 }, { 0.8, 0.25, 0.25, 1.0 } }
local CHIP_OFF = { { 0.3, 0.3, 0.3, 1.0 }, { 0.4, 0.4, 0.4, 1.0 }, { 0.5, 0.5, 0.5, 1.0 } }
local CHIP_EMPTY = { { 0.2, 0.2, 0.2, 1.0 }, { 0.2, 0.2, 0.2, 1.0 }, { 0.2, 0.2, 0.2, 1.0 } }

local SETTING_WIDTH, PICK_WIDTH, CHIP_WIDTH, HP_WIDTH = 160, 170, 28, 80

local cfg, save  -- this frame's settings and save callback

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

-- Header ---------------------------------------------------------------------------

local function draw_header(view, status)
    local s = view.status
    push_button(s.running and STOP or START)
    if imgui.Button(s.running and 'Stop##sk3_run' or 'Start##sk3_run', { 70, 0 }) then status.running = not s.running end
    imgui.PopStyleColor(3)
    imgui.SameLine()
    text(view.job)
    text(s.state, s.running and GREEN or RED)
    imgui.SameLine()
    text(s.text)
    if s.dim then
        imgui.SameLine()
        text(s.dim, GREY)
    end
end

-- Party and recent actions (evaluate) ------------------------------------------------

local function draw_member(p)
    local dim = p.away and GREY or nil
    imgui.TableNextRow()
    imgui.TableNextColumn()
    text(p.tag, GREY)
    imgui.TableNextColumn()
    text(p.name .. (p.kind == 'trust' and ' (trust)' or '') .. ((p.alive or p.away) and '' or ' (KO)'), dim)
    imgui.TableNextColumn()
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, HP_BAR[p.hp])
    imgui.ProgressBar(p.hpp / 100, { HP_WIDTH, 0 }, ('%d%%'):format(p.hpp))
    imgui.PopStyleColor()
    imgui.TableNextColumn()
    text(('MP %d%%'):format(p.mpp), dim)
    imgui.TableNextColumn()
    text(p.dist, dim)
    imgui.TableNextColumn()
    text(p.buffs, GREY)
    tip(p.buffs_all)
end

local function draw_party(view)
    if not imgui.CollapsingHeader('Party###sk3_party', ImGuiTreeNodeFlags_DefaultOpen) then return end
    if imgui.BeginTable('##sk3_party_table', 6, ImGuiTableFlags_SizingFixedFit) then
        for _, p in ipairs(view.party) do draw_member(p) end
        imgui.EndTable()
    end
    for _, e in ipairs({ { 'Target', view.bt }, { 'Pet', view.pet } }) do
        if e[2] then text(('%s: %s  %d%%  %s'):format(e[1], e[2].name, e[2].hpp, e[2].dist), GREY) end
    end
    for i, f in ipairs(view.flags) do
        if i > 1 then imgui.SameLine() end
        text('[' .. f .. ']', YELLOW)
    end
end

local function draw_recent(view)
    if not imgui.CollapsingHeader(('Recent actions (%d)###sk3_recent'):format(#view.recent), ImGuiTreeNodeFlags_DefaultOpen) then
        return
    end
    if #view.recent == 0 then text('Nothing sent yet.', GREY) end
    for _, r in ipairs(view.recent) do
        text(('%3ds'):format(r.age), GREY)
        imgui.SameLine()
        text(r.text)
        imgui.SameLine()
        text(r.why, GREY)
    end
end

-- Section bodies --------------------------------------------------------------------

-- Sliders write as they move and save once let go.
local function slider(label, path, value, min, max, help)
    local v = { value }
    imgui.PushItemWidth(SETTING_WIDTH)
    if imgui.SliderInt(label, v, min, max) then model.set_value(cfg, path, v[1]) end
    imgui.PopItemWidth()
    if imgui.IsItemDeactivatedAfterEdit() then save() end
    tip(help)
end

local function focus_combo(h)
    imgui.PushItemWidth(SETTING_WIDTH)
    if imgui.BeginCombo('Focus##sk3_focus', h.focus ~= '' and h.focus or 'None') then
        if imgui.Selectable('None##sk3_focus_none', h.focus == '') then model.set_value(cfg, 'heal.focus', ''); save() end
        for _, name in ipairs(h.focus_names) do
            if imgui.Selectable(name, name == h.focus) then model.set_value(cfg, 'heal.focus', name); save() end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    tip('Heal this member first, under its own threshold.')
end

local function draw_heal_settings(h)
    slider('Heal under##sk3_threshold', 'heal.threshold', h.threshold, 1, 99, 'Cure anyone under this HP %.')
    slider('Critical under##sk3_critical', 'heal.critical', h.critical, 1, 99,
        'Under this HP %, boost the cure first (Divine Seal) or save them (Martyr).')
    focus_combo(h)
    slider('Focus under##sk3_focus_threshold', 'heal.focus_threshold', h.focus_threshold, 1, 99,
        'Cure the focus member under this HP %.')
    slider('Cure potency +##sk3_cure_potency', 'heal.cure_potency', h.cure_potency, 0, 50,
        'Cure potency % from gear, to size each cure to the HP missing.')
    slider('Waltz potency +##sk3_waltz_potency', 'heal.waltz_potency', h.waltz_potency, 0, 50,
        'Waltz potency % from gear.')
    imgui.Separator()
end

local function pick_combo(r, id)
    imgui.PushItemWidth(PICK_WIDTH)
    if imgui.BeginCombo('##pick_' .. id, r.choice) then
        for _, c in ipairs(r.choices) do
            if imgui.Selectable(c.label, c.name == r.pick) then model.set_pick(cfg, r.key, c.name); save() end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
end

-- ME, P1-P5. An empty slot can't be picked, but a picked one can still be cleared.
local function target_chips(r, id)
    for i, t in ipairs(r.targets) do
        if i > 1 then imgui.SameLine(0, 2) end
        local disabled = not t.present and not t.on
        local colors = disabled and CHIP_EMPTY or not t.on and CHIP_OFF
        if colors then push_button(colors) end
        if disabled then imgui.PushStyleColor(ImGuiCol_Text, GREY) end
        if imgui.Button(t.label .. '##' .. id .. t.slot, { CHIP_WIDTH, 0 }) and not disabled then
            model.toggle_target(cfg, r.key, t.slot)
            save()
        end
        if colors then imgui.PopStyleColor(disabled and 4 or 3) end
        tip(t.name or 'empty slot')
    end
end

-- One row per settings key: [x] Name (note) | pick | ME P1-P5 | ready or why not.
local function draw_rows(s)
    local columns = 2 + (s.has_choices and 1 or 0) + (s.has_targets and 1 or 0)
    if not imgui.BeginTable('##sk3_rows_' .. s.id, columns, ImGuiTableFlags_SizingFixedFit) then return end
    for _, r in ipairs(s.rows) do
        local id = s.id .. '_' .. r.key
        imgui.TableNextRow()
        imgui.TableNextColumn()
        local v = { r.on }
        if imgui.Checkbox(r.label .. '##' .. id, v) then model.set_row_on(cfg, r.key, v[1]); save() end
        if s.has_choices then
            imgui.TableNextColumn()
            if r.choices then pick_combo(r, id) end
        end
        if s.has_targets then
            imgui.TableNextColumn()
            if r.targets then target_chips(r, id) end
        end
        imgui.TableNextColumn()
        text(r.avail, r.ready and GREEN or GREY)
        tip(r.action)
    end
    imgui.EndTable()
end

local function draw_options(view, status)
    local v = { view.japanese }
    if imgui.Checkbox('Japanese client##sk3_japanese', v) then model.set_value(cfg, 'japanese', v[1]); save() end
    tip('Send spell and ability names in Japanese.')
    v = { view.log }
    if imgui.Checkbox('Action log##sk3_log', v) then status.log = v[1] end
    tip('Print each action to chat as it is sent.')
end

local function draw_body(view, s, status)
    if s.id == 'heal' then draw_heal_settings(view.heal) end
    if s.rows then draw_rows(s) else draw_options(view, status) end
end

-- Sections ------------------------------------------------------------------------------

-- A behavior's switch, beside its header.
local function section_switch(s)
    local v = { s.on }
    if imgui.Checkbox('##sk3_on_' .. s.id, v) then model.set_section(cfg, s.id, v[1]); save() end
    tip(('%s %s'):format(s.title, s.on and 'on' or 'off'))
end

local function draw_sections(view, status)
    for _, s in ipairs(view.sections) do
        if s.rows then
            section_switch(s)
            imgui.SameLine()
        end
        if imgui.CollapsingHeader(s.title .. '###sk3_' .. s.id, ImGuiTreeNodeFlags_DefaultOpen) then
            draw_body(view, s, status)
        end
    end
end

-- One frame. Returns a Lua error raised while drawing, after closing the window
-- cleanly; the caller reports it.
-- ponytail: an error inside a table or combo still leaves that scope open, which
-- ImGui asserts on; unwind tracked scopes (as v2's abort_sections does) if one shows up.
function window.render(view, cfg_, status, save_)
    cfg, save = cfg_, save_
    local open = { true }
    local ok, err = true, nil
    if imgui.Begin('Sidekick3', open, ImGuiWindowFlags_AlwaysAutoResize) then
        ok, err = pcall(function ()
            draw_header(view, status)
            draw_party(view)
            draw_recent(view)
            draw_sections(view, status)
        end)
    end
    imgui.End()
    if not open[1] then
        status.open = false
        model.set_value(cfg, 'ui.open', false)
        save()
    end
    if not ok then return err end
end

return window
