--[[
    The standard Sidekick3 window, and the reference UI: it uses only the `view`
    and `act` every UI is given (ui/README.md), so ui/custom.lua can replace it.
    ImGui only; it reads no game state and decides nothing.

    Ashita's binding (as v2 found it): widget values are one-element tables
    ({ true }, { 75 }), and Text, TextColored and SetTooltip take a printf
    format, so any '%' shown goes through text() / tip(), which double it.
]]--

local imgui = require('imgui')

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

local DISPLAYS = {
    { 'headers', 'Sections as headers' },
    { 'tabs', 'Sections as tabs' },
    { 'groups', 'Sections as pages: Healing, Support, Utility' },
}
local SIZES = { { 'auto', 'Fit the window to its contents' }, { 'custom', 'Size the window by dragging its corner' } }

local act                 -- this frame's actions
local page = 'Healing'    -- the page on show in the 'groups' layout; this session only

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

-- A menu of { value, label } setting `path`, the current value checked.
local function choose(options, current, path)
    for _, o in ipairs(options) do
        if imgui.Selectable(o[2], o[1] == current) and o[1] ~= current then act.set(path, o[1]) end
    end
end

-- Right-click on any section header or tab: the section layout. The view keeps
-- this frame's layout, so a switch made here lands next frame, never mid-tab-bar.
local function display_menu(view, id)
    if imgui.BeginPopupContextItem('##sk3_display_' .. id) then
        choose(DISPLAYS, view.ui.display, 'ui.display')
        imgui.EndPopup()
    end
end

-- Right-click on empty window space (headers and widgets keep their own clicks).
local function size_menu(view)
    if imgui.BeginPopupContextWindow('##sk3_size', ImGuiPopupFlags_MouseButtonRight + ImGuiPopupFlags_NoOpenOverItems) then
        choose(SIZES, view.ui.size, 'ui.size')
        imgui.EndPopup()
    end
end

-- Header ---------------------------------------------------------------------------

local function draw_header(view)
    local s = view.status
    push_button(s.running and STOP or START)
    if imgui.Button(s.running and 'Stop##sk3_run' or 'Start##sk3_run', { 70, 0 }) then act.run(not s.running) end
    imgui.PopStyleColor(3)
    imgui.SameLine()
    imgui.AlignTextToFramePadding()  -- level with the button
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
    local open = imgui.CollapsingHeader('Party###sk3_party', ImGuiTreeNodeFlags_DefaultOpen)
    display_menu(view, 'party')
    if not open then return end
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
    local open = imgui.CollapsingHeader(('Recent actions (%d)###sk3_recent'):format(#view.recent), ImGuiTreeNodeFlags_DefaultOpen)
    display_menu(view, 'recent')
    if not open then return end
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
local function heal_members(h)
    if #h.members == 0 then return end
    text('Heal:')
    for _, m in ipairs(h.members) do
        imgui.SameLine()
        local v = { m.healed }
        if imgui.Checkbox(m.name .. '##sk3_heal_' .. m.name, v) then act.skip(m.name) end
        tip('Untick to never heal them for their own sake; an area heal may still land on them.')
    end
end

local function draw_heal_settings(h, wake)
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
    heal_members(h)
    checkbox('Wake sleepers##sk3_wake', wake, function (on) act.section('wake', on) end,
        'Wake a sleeping member with a cure or waltz that is on below; an area one for two or more.')
    imgui.Separator()
end

local function draw_recover_settings(r)
    slider('MP under##sk3_recover_mp', 'recover.mp', r.mp, 1, 99,
        'Recover MP under this MP % (yours; a member\'s for Devotion).')
    slider('TP under##sk3_recover_tp', 'recover.tp', r.tp, 0, 3000, 'In combat, get TP back under this.')
    if r.spends_tp then
        slider('Spend TP from##sk3_recover_min_tp', 'recover.min_tp', r.min_tp, 0, 3000,
            'Chivalry turns all your TP into MP: only from this much.')
    end
    imgui.Separator()
end

local function draw_pet_settings(line)
    slider('Pet HP under##sk3_pet_heal', 'pet.heal', line, 1, 99, 'Heal your pet under this HP %.')
    imgui.Separator()
end

local function draw_move(view)
    local f, r = view.follow, view.rest
    checkbox('Follow##sk3_follow', f.on, function (on) act.set('follow.on', on) end,
        'Follow this member once they are further away than the distance.')
    member_combo('Leader', 'follow_target', f.target, f.names, 'follow.target', 'Who to follow; resting stands up when they leave too.')
    slider('Follow past##sk3_follow_distance', 'follow.distance', f.distance, 1, 15, 'Yalms.')
    imgui.Separator()
    checkbox('Rest##sk3_rest', r.on, function (on) act.set('rest.on', on) end,
        'Rest for MP out of combat once nothing else has happened for a while; stand at full MP.')
    slider('Rest after##sk3_rest_delay', 'rest.delay', r.delay, 1, 20, 'Seconds of nothing to do.')
    slider('Stand past##sk3_rest_distance', 'rest.distance', r.distance, 1, 15, 'Yalms from the leader.')
end

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

-- ME, P1-P5. An empty slot can't be picked, but a picked one can still be cleared.
local function target_chips(r, id)
    for i, t in ipairs(r.targets) do
        if i > 1 then imgui.SameLine(0, 2) end
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

-- One row per settings key: [x] Name (note) | pick | ME P1-P5 | ready or why not.
local function draw_rows(s)
    local columns = 2 + (s.has_choices and 1 or 0) + (s.has_targets and 1 or 0)
    if not imgui.BeginTable('##sk3_rows_' .. s.id, columns, ImGuiTableFlags_SizingFixedFit) then return end
    for _, r in ipairs(s.rows) do
        local id = s.id .. '_' .. r.key
        imgui.TableNextRow()
        imgui.TableNextColumn()
        local v = { r.on }
        local label = r.count and ('%s (%d)'):format(r.label, r.count) or r.label  -- an item: how many you carry
        if imgui.Checkbox(label .. '##' .. id, v) then act.row(r.key, v[1]) end
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

local function draw_options(view)
    local v = { view.japanese }
    if imgui.Checkbox('Japanese client##sk3_japanese', v) then act.set('japanese', v[1]) end
    tip('Send spell and ability names in Japanese.')
    v = { view.log }
    if imgui.Checkbox('Action log##sk3_log', v) then act.log(v[1]) end
    tip('Print each action to chat as it is sent.')
end

local function draw_body(view, s)
    if s.id == 'heal' then draw_heal_settings(view.heal, view.wake)
    elseif s.id == 'recover' then draw_recover_settings(view.recover)
    elseif s.id == 'pet' then draw_pet_settings(view.pet_heal) end
    if s.rows then draw_rows(s)
    elseif s.id == 'move' then draw_move(view)
    else draw_options(view) end
end

-- Sections: built once, wrapped by the layout --------------------------------------------

-- A behavior's switch: beside its header, or atop its tab (a tab can't hold one).
local function section_switch(s, label)
    local v = { s.on }
    if imgui.Checkbox(label .. '##sk3_on_' .. s.id, v) then act.section(s.id, v[1]) end
    tip(('%s %s'):format(s.title, s.on and 'on' or 'off'))
end

local function header_section(view, s)
    if s.rows then
        section_switch(s, '')
        imgui.SameLine()
    end
    local open = imgui.CollapsingHeader(s.title .. '###sk3_' .. s.id, ImGuiTreeNodeFlags_DefaultOpen)
    display_menu(view, s.id)
    if open then draw_body(view, s) end
end

-- NoPushId keeps the menu's popup id the same whether or not the tab is selected.
local function tab_section(view, s)
    local label = s.title .. (s.on == false and ' (off)' or '') .. '###sk3_tab_' .. s.id
    local open = imgui.BeginTabItem(label, nil, ImGuiTabItemFlags_NoPushId)
    display_menu(view, s.id)
    if not open then return end
    if s.rows then
        section_switch(s, s.title)
        imgui.Separator()
    end
    draw_body(view, s)
    imgui.EndTabItem()
end

-- One tab bar of the sections in `group` (all when nil).
local function tab_bar(view, id, group)
    if not imgui.BeginTabBar(id, ImGuiTabBarFlags_FittingPolicyScroll) then return end
    for _, s in ipairs(view.sections) do
        if not group or s.group == group then tab_section(view, s) end
    end
    imgui.EndTabBar()
end

-- Healing / Support / Utility, each a tab bar of its sections; empty pages hidden.
local function pages(view)
    local shown, has = {}, {}
    for _, s in ipairs(view.sections) do
        if not has[s.group] then has[s.group] = true; shown[#shown + 1] = s.group end
    end
    if not has[page] then page = shown[1] end
    for i, g in ipairs(shown) do
        if i > 1 then imgui.SameLine() end
        local w, h = imgui.CalcTextSize(g)  -- an explicit size: a zero width would span the row
        if imgui.Selectable(g .. '##sk3_page', g == page, 0, { w, h }) then page = g end
    end
    imgui.Separator()
    tab_bar(view, '##sk3_tabs_' .. page, page)
end

local function draw_sections(view)
    if view.ui.display == 'tabs' then
        tab_bar(view, '##sk3_tabs')
    elseif view.ui.display == 'groups' then
        pages(view)
    else
        for _, s in ipairs(view.sections) do header_section(view, s) end
    end
end

-- One frame. A Lua error raised while drawing is raised again after the window
-- is ended, so ImGui stays balanced and Sidekick reports it.
-- ponytail: an error inside a table or combo still leaves that scope open, which
-- ImGui asserts on; unwind tracked scopes (as v2's abort_sections does) if one shows up.
function window.render(view, act_)
    act = act_
    local open = { true }
    local ok, err = true, nil
    -- 'custom': resizable, contents scroll. Leaving 'auto' keeps the size it had fitted.
    local flags = view.ui.size == 'custom' and 0 or ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoResize
    if imgui.Begin('Sidekick3', open, flags) then
        ok, err = pcall(function ()
            draw_header(view)
            draw_party(view)
            draw_recent(view)
            draw_sections(view)
            size_menu(view)
        end)
    end
    imgui.End()
    if not open[1] then act.close() end
    if not ok then error(err, 0) end
end

return window
