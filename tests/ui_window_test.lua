-- ui/window.lua against a fake imgui: every path draws without a Lua error,
-- every ImGui scope it opens is closed, widget ids are unique, and clicks
-- reach the settings through the model.
local fake = require('tests.fake')
local model = require('ui.model')
local settings = require('core.settings')

-- The ImGui constants .luacheckrc lets the window use, as distinct numbers.
local rc = { files = {} }
setfenv(assert(loadfile('.luacheckrc')), rc)()
for i, name in ipairs(rc.read_globals) do
    if name:match('^ImGui') then rawset(_G, name, i) end
end

-- Openers and their closers. Every opener reports open (so every body draws)
-- unless a test sets frame.clicks[opener] = false; Begin and Push* need their
-- closer either way.
local CLOSER = {
    Begin = 'End', BeginTable = 'EndTable', BeginCombo = 'EndCombo', BeginTabBar = 'EndTabBar',
    BeginTabItem = 'EndTabItem', BeginPopupContextItem = 'EndPopup', BeginPopupContextWindow = 'EndPopup',
    PushStyleColor = 'PopStyleColor', PushItemWidth = 'PopItemWidth',
}
local ALWAYS = { Begin = true, PushStyleColor = true, PushItemWidth = true }
local IDS = { Checkbox = true, Button = true, SliderInt = true, BeginCombo = true, CollapsingHeader = true, BeginTabItem = true }

local frame  -- { stack, texts, ids, clicks, edited }

local function pop(closer)
    local top = table.remove(frame.stack)
    assert(top == closer, ('%s, but %s is open'):format(closer, tostring(top)))
end

-- What a printf-style text shows; a lone '%' would garble it in game.
local function shown(fmt)
    assert(type(fmt) == 'string', 'text must be a string')
    assert(not fmt:gsub('%%%%', ''):find('%%'), 'unescaped % in: ' .. fmt)
    frame.texts[#frame.texts + 1] = fmt:gsub('%%%%', '%%')
end

local handlers = {
    Text = function (fmt) shown(fmt) end,
    TextColored = function (color, fmt) assert(#color == 4); shown(fmt) end,
    SetTooltip = function (fmt) shown(fmt) end,
    IsItemHovered = function () return true end,
    CalcTextSize = function (s) return #s * 7, 13 end,
    ProgressBar = function (f) assert(f >= 0 and f <= 1) end,
    PopStyleColor = function (n) for _ = 1, n or 1 do pop('PopStyleColor') end end,
    Checkbox = function (label, v)
        assert(type(v) == 'table' and type(v[1]) == 'boolean', label .. ': value must be { bool }')
        if not frame.clicks[label] then return false end
        v[1] = not v[1]
        return true
    end,
    Button = function (label) return frame.clicks[label] == true end,
    Selectable = function (label) return frame.clicks[label] == true end,
    SliderInt = function (label, v, min, max)
        assert(type(v) == 'table' and v[1] >= min and v[1] <= max, label .. ': value must be { n } in range')
        if not frame.clicks[label] then return false end
        v[1], frame.edited = frame.clicks[label], true
        return true
    end,
    IsItemDeactivatedAfterEdit = function ()
        local edited = frame.edited
        frame.edited = false
        return edited
    end,
}

-- frame.args[name] lists each call's label; frame.clicks.popup, when set, is the
-- one popup open this frame (else all are).
local imgui = setmetatable({}, { __index = function (_, name)
    return function (...)
        local label = ...
        if type(label) == 'string' then
            frame.args[name] = frame.args[name] or {}
            table.insert(frame.args[name], label)
        end
        if IDS[name] then
            local id = label:match('###.*') or label
            assert(not frame.ids[id], 'duplicate widget id ' .. id)
            frame.ids[id] = true
        end
        if CLOSER[name] then
            local open = frame.clicks[name] ~= false
            if name:match('^BeginPopup') and frame.clicks.popup then open = frame.clicks.popup == label end
            if open or ALWAYS[name] then table.insert(frame.stack, CLOSER[name]) end
            if name == 'Begin' then
                frame.flags = select(3, ...)
                if frame.clicks.close then select(2, ...)[1] = false end
            end
            return open
        elseif name:match('^End') or name == 'PopItemWidth' then
            pop(name)
        elseif name == 'CollapsingHeader' then
            return frame.clicks[label] ~= false
        elseif handlers[name] then
            return handlers[name](...)
        end
        return false
    end
end })
package.preload['imgui'] = function () return imgui end
package.loaded['ui.window'] = nil
local window = require('ui.window')

local cat = fake.catalog(3, 75, 4, 37, { 'Divine Seal', 'Martyr' })
local NAMES = { job = function (id) return ({ [3] = 'WHM', [4] = 'BLM' })[id] end, statuses = fake.res.statuses }
local SENT = { at = 990, command = '/ma "Cure IV" 101', action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }

local function status(t)
    local s = { running = false, open = true, log = true, intent = SENT, sent = { SENT } }
    for k, v in pairs(t or {}) do s[k] = v end
    return s
end

local function snap()
    return fake.snap({
        { name = 'A', hpp = 62, buffs = { [40] = true, [41] = true } },
        { name = 'B', kind = 'trust', in_zone = false },
    }, { bt = { name = 'Crab', hpp = 50, dist = 4.3 }, pet = { name = 'Carbuncle', hpp = 100, dist = 2 }, combat = true })
end

-- One frame; returns the number of saves. `view` defaults to the model's.
local function render(cfg, st, clicks, view)
    frame = { stack = {}, texts = {}, ids = {}, args = {}, clicks = clicks or {} }
    local saves = 0
    local err = window.render(view or model.build(snap(), cat, cfg, st, NAMES), cfg, st, function () saves = saves + 1 end)
    eq(err, nil, 'no Lua error')
    eq(frame.stack, {}, 'every ImGui scope closed')
    return saves
end

local function showed(s)
    for _, t in ipairs(frame.texts) do if t == s then return true end end
    return false
end

test('draws the whole window in each display mode and size, every scope closed', function ()
    for _, display in ipairs({ 'headers', 'tabs', 'groups' }) do
        for _, size in ipairs({ 'auto', 'custom' }) do
            local cfg = settings.defaults()
            cfg.ui.display, cfg.ui.size = display, size
            eq(render(cfg, status()), 0)
            eq({ showed('WHM 75 / BLM 37'), showed('would: Cure IV -> A (heal: A at 62%)'), showed('ready') }, { true, true, true })
        end
    end
    eq(render(settings.defaults(), status({ running = true, intent = false, why = 'casting' })), 0)
    eq({ showed('Running'), showed('Cure IV -> A (heal: A at 62%)'), showed('casting') }, { true, true, true })
end)

test('a row, its pick and its targets, and a section switch, each write and save', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Protect##buff_Protect'] = true }), 1)
    eq(cfg.rows.Protect, { on = true })
    eq(render(cfg, st, { ['Protect II'] = true }), 1)
    eq(cfg.rows.Protect.pick, 'Protect II')
    eq(render(cfg, st, { ['P1##buff_Protect1'] = true }), 1)
    eq(cfg.rows.Protect.targets, { [0] = true, [1] = true })
    eq(render(cfg, st, { ['P4##buff_Protect4'] = true }), 0)  -- empty slot
    eq(cfg.rows.Protect.targets, { [0] = true, [1] = true })
    eq(render(cfg, st, { ['##sk3_on_buff'] = true }), 1)
    eq(cfg.buff.on, false)
    eq(render(cfg, st, { ['Cure##heal_Cure'] = true }), 1)
    eq(cfg.rows.Cure, { on = false })
end)

test('sliders write as they move and save once let go; focus and options save', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Heal under##sk3_threshold'] = 60 }), 1)
    eq(cfg.heal.threshold, 60)
    eq(render(cfg, st, { A = true }), 1)  -- the focus combo's member
    eq(cfg.heal.focus, 'A')
    eq(render(cfg, st, { ['None##sk3_focus_none'] = true }), 1)
    eq(cfg.heal.focus, '')
    eq(render(cfg, st, { ['Japanese client##sk3_japanese'] = true }), 1)
    eq(cfg.japanese, true)
end)

test('Start/Stop and the action log change the session, not the settings', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Start##sk3_run'] = true, ['Action log##sk3_log'] = true }), 0)
    eq({ st.running, st.log }, { true, false })
    eq(cfg, settings.defaults())
end)

test('the close button closes the window and remembers it', function ()
    local cfg, st = settings.defaults(), status()
    cfg.ui.open = true
    eq(render(cfg, st, { close = true }), 1)
    eq({ st.open, cfg.ui.open }, { false, false })
end)

test('collapsed, only the window is begun and ended', function ()
    eq(render(settings.defaults(), status(), { Begin = false }), 0)
    eq(#frame.texts, 0)
end)

test('a Lua error while drawing still ends the window, and is returned', function ()
    local cfg, st = settings.defaults(), status()
    local view = model.build(snap(), cat, cfg, st, NAMES)
    view.recent = nil
    frame = { stack = {}, texts = {}, ids = {}, args = {}, clicks = {} }
    local err = window.render(view, cfg, st, function () end)
    eq(type(err), 'string')
    eq(frame.stack, {})
end)

-- One frame in `display` with Buffs switched off; `in_cat` replaces the catalog.
local function layout(display, clicks, in_cat)
    local cfg, st = settings.defaults(), status()
    cfg.ui.display = display
    cfg.buff.on = false
    render(cfg, st, clicks, in_cat and model.build(snap(), in_cat, cfg, st, NAMES))
    return frame.args, cfg
end

test('headers: a collapsing header per section, no tab bar', function ()
    local args = layout('headers')
    eq(args.CollapsingHeader, { 'Party###sk3_party', 'Recent actions (1)###sk3_recent', 'Healing###sk3_heal',
        'Debuffs###sk3_remove', 'Buffs###sk3_buff', 'Raise###sk3_revive', 'Options###sk3_options' })
    eq(args.BeginTabBar, nil)
end)

test('tabs: one tab bar of every section; a switched-off one says so, its switch atop it', function ()
    local args = layout('tabs')
    eq(args.BeginTabBar, { '##sk3_tabs' })
    eq(args.BeginTabItem, { 'Healing###sk3_tab_heal', 'Debuffs###sk3_tab_remove', 'Buffs (off)###sk3_tab_buff',
        'Raise###sk3_tab_revive', 'Options###sk3_tab_options' })
    eq(args.CollapsingHeader, { 'Party###sk3_party', 'Recent actions (1)###sk3_recent' })
    local _, cfg = layout('tabs', { ['Buffs##sk3_on_buff'] = true })
    eq(cfg.buff.on, true)
end)

local function page_buttons(args)
    local out = {}
    for _, label in ipairs(args.Selectable) do
        if label:match('##sk3_page$') then out[#out + 1] = label end
    end
    return out
end

test('groups: a row of pages, then the page\'s tab bar; empty pages are hidden', function ()
    local args = layout('groups')
    eq(page_buttons(args), { 'Healing##sk3_page', 'Support##sk3_page', 'Utility##sk3_page' })
    eq(args.BeginTabBar, { '##sk3_tabs_Healing' })
    eq(args.BeginTabItem, { 'Healing###sk3_tab_heal' })
    args = layout('groups', { ['Support##sk3_page'] = true })
    eq(args.BeginTabBar, { '##sk3_tabs_Support' })
    eq(args.BeginTabItem, { 'Debuffs###sk3_tab_remove', 'Buffs (off)###sk3_tab_buff', 'Raise###sk3_tab_revive' })
    args = layout('groups', nil, {})  -- nothing to automate: only Options
    eq(page_buttons(args), { 'Utility##sk3_page' })
    eq(args.BeginTabBar, { '##sk3_tabs_Utility' })
end)

test('right-click menus switch the layout and the window size, and save', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { popup = '##sk3_display_buff', ['Sections as tabs'] = true }), 1)
    eq(cfg.ui.display, 'tabs')
    eq(render(cfg, st, { popup = '##sk3_display_buff', ['Sections as tabs'] = true }), 0)  -- already
    eq(render(cfg, st, { popup = '##sk3_display_party', ['Sections as pages: Healing, Support, Utility'] = true }), 1)
    eq(cfg.ui.display, 'groups')
    eq(frame.flags, ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoResize)
    eq(render(cfg, st, { popup = '##sk3_size', ['Size the window by dragging its corner'] = true }), 1)
    eq(cfg.ui.size, 'custom')
    render(cfg, st)
    eq(frame.flags, 0)
end)
