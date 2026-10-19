-- ui/window.lua (and ui/custom.lua, when there is one) against a fake imgui:
-- every path draws without a Lua error, every ImGui scope it opens is closed,
-- widget ids are unique, and clicks reach the settings through `act`.
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
-- closer either way. Style vars are counted apart: ImGui lets them be pushed
-- before a Begin and popped straight after it. Tabs and context popups are for custom UIs.
local CLOSER = {
    Begin = 'End', BeginTable = 'EndTable', BeginCombo = 'EndCombo', BeginTabBar = 'EndTabBar',
    BeginTabItem = 'EndTabItem', BeginPopup = 'EndPopup', BeginPopupContextItem = 'EndPopup', BeginPopupContextWindow = 'EndPopup',
    PushStyleColor = 'PopStyleColor', PushItemWidth = 'PopItemWidth',
}
local ALWAYS = { Begin = true, PushStyleColor = true, PushItemWidth = true }
local IDS = { Checkbox = true, Button = true, InvisibleButton = true, SliderInt = true, BeginCombo = true,
              CollapsingHeader = true, BeginTabItem = true }

local frame  -- { stack, vars, texts, ids, args, flags, columns, previews, headers, drawn, window, cursor, extent, clicks, edited }

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

local function point(p, what)
    assert(type(p) == 'table' and type(p[1]) == 'number' and type(p[2]) == 'number', what .. ': must be { x, y }')
end

-- The arguments of each draw-list call that are points.
local POINTS = { AddRectFilled = { 1, 2 }, AddRect = { 1, 2 }, AddRectFilledMultiColor = { 1, 2 }, AddLine = { 1, 2 },
                 AddCircleFilled = { 1 }, AddCircle = { 1 }, AddTriangleFilled = { 1, 2, 3 }, AddTriangle = { 1, 2, 3 } }

-- A draw list records each call as { list, name, args }. Its text is drawn as is,
-- AddText(pos, col, s) or AddText(font, size, pos, col, s).
local function draw_list(list)
    return setmetatable({}, { __index = function (_, name)
        return function (_, ...)
            local args = { ... }
            for _, i in ipairs(POINTS[name] or {}) do point(args[i], name) end
            if name == 'AddText' then
                local at = type(args[1]) == 'table' and 1 or 3
                point(args[at], name)
                assert(type(args[at + 2]) == 'string', 'AddText: text must be a string')
            end
            frame.drawn[#frame.drawn + 1] = { list = list, name = name, args = args }
        end
    end })
end

-- Items placed with SetCursorScreenPos widen the window's content to their far corner.
local function placed(size, what)
    point(size, what)
    assert(size[1] >= 0 and size[2] >= 0, what .. ': negative size')
    if not frame.cursor then return end
    local e = frame.extent[frame.window] or { -math.huge, -math.huge }
    frame.extent[frame.window] = { math.max(e[1], frame.cursor[1] + size[1]), math.max(e[2], frame.cursor[2] + size[2]) }
end
local WINDOW_LIST, BACKGROUND_LIST = draw_list('window'), draw_list('background')

local handlers = {
    Text = function (fmt) shown(fmt) end,
    TextColored = function (color, fmt) assert(#color == 4); shown(fmt) end,
    SetTooltip = function (fmt) shown(fmt) end,
    IsItemHovered = function () return true end,
    CalcTextSize = function (s) return #s * 7, 13 end,
    GetFontSize = function () return 13 end,
    GetFont = function () return 'font' end,
    GetCursorScreenPos = function () return 100, 50 end,
    GetColorU32 = function (c) assert(#c == 4); return c end,  -- so tests can compare colours
    GetWindowDrawList = function () return WINDOW_LIST end,
    GetBackgroundDrawList = function () return BACKGROUND_LIST end,
    PushStyleVar = function (var, v)
        if var == ImGuiStyleVar_WindowPadding then point(v, 'WindowPadding') end
        if var == ImGuiStyleVar_WindowBorderSize then assert(type(v) == 'number', 'WindowBorderSize: must be a number') end
        frame.vars = frame.vars + 1
    end,
    SetCursorScreenPos = function (p)
        point(p, 'SetCursorScreenPos')
        frame.cursor = p
    end,
    Dummy = function (size) placed(size, 'Dummy') end,
    PopStyleVar = function (n)
        frame.vars = frame.vars - (n or 1)
        assert(frame.vars >= 0, 'PopStyleVar with none pushed')
    end,
    PopStyleColor = function (n) for _ = 1, n or 1 do pop('PopStyleColor') end end,
    Checkbox = function (label, v)
        assert(type(v) == 'table' and type(v[1]) == 'boolean', label .. ': value must be { bool }')
        if not frame.clicks[label] then return false end
        v[1] = not v[1]
        return true
    end,
    Button = function (label) return frame.clicks[label] == true end,
    InvisibleButton = function (label, size)
        placed(size, label)
        assert(size[1] > 0 and size[2] > 0, label .. ': ImGui asserts on a zero size')
        return frame.clicks[label] == true
    end,
    Selectable = function (label) return frame.clicks[label] == true end,
    GetCursorPosX = function () return 8 end,
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

-- frame.args[name] lists each call's label. clicks.close = a window's label
-- clicks that window's close button.
local imgui = setmetatable({}, { __index = function (_, name)
    return function (...)
        local label = ...
        if type(label) == 'string' then
            frame.args[name] = frame.args[name] or {}
            table.insert(frame.args[name], label)
        end
        if IDS[name] then  -- ImGui's ids are per window
            local id = label:match('###.*') or label
            local key = (name == 'Begin' and '' or frame.window or '') .. '|' .. id
            assert(not frame.ids[key], 'duplicate widget id ' .. id)
            frame.ids[key] = true
        end
        if CLOSER[name] then
            local open = frame.clicks[name] ~= false
            if open or ALWAYS[name] then table.insert(frame.stack, CLOSER[name]) end
            if name == 'Begin' then
                frame.window, frame.cursor = label, nil
                local p_open
                p_open, frame.flags[label] = select(2, ...)
                if frame.clicks.close == label and type(p_open) == 'table' then p_open[1] = false end
            elseif name == 'BeginTable' then
                frame.columns[label] = select(2, ...)
            elseif name == 'BeginCombo' then
                frame.previews[label] = select(2, ...)  -- what it shows closed
            end
            return open
        elseif name:match('^End') or name == 'PopItemWidth' then
            pop(name)
        elseif name == 'CollapsingHeader' then
            frame.headers[label] = select(2, ...) or 0
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

local function has(list, x)
    for _, v in ipairs(list or {}) do if v == x then return true end end
    return false
end

-- The last frame began this window.
local function begun(label) return has(frame.args.Begin, label) end

-- SK Settings stays open between frames, as in game; this follows it.
local settings_shown = false

-- What Track and Untrack asked of Sidekick, in order.
local tracking_calls = {}
local TRACKING = {
    add = function (name) tracking_calls[#tracking_calls + 1] = { 'add', name } end,
    remove = function (name) tracking_calls[#tracking_calls + 1] = { 'remove', name } end,
}

-- One frame of `ui`; returns the Lua error it raised, if any, and the number of
-- settings writes. `view` defaults to the model's.
-- What act.remote sent, as { session, fn, args... }.
local remote_calls = {}
local function send(name, call)
    local c = { name }
    for i = 1, call.n + 1 do c[i + 1] = call[i] end
    remote_calls[#remote_calls + 1] = c
end

local function draw(ui, cfg, st, clicks, view)
    frame = { stack = {}, vars = 0, texts = {}, ids = {}, args = {}, flags = {}, columns = {}, previews = {}, headers = {},
              drawn = {}, extent = {}, clicks = clicks or {} }
    local writes = 0
    local act = model.actions(cfg, st, function () writes = writes + 1 end, TRACKING, send)
    local ok, err = pcall(ui.render, view or model.build(snap(), cat, cfg, st, NAMES), act)
    eq(frame.stack, {}, 'every ImGui scope closed')
    eq(frame.vars, 0, 'every style var popped')
    settings_shown = begun('SK Settings') and frame.clicks.close ~= 'SK Settings'
    return not ok and err or nil, writes
end

-- One frame of the standard window; returns the number of settings writes.
local function render(cfg, st, clicks, view)
    local err, writes = draw(window, cfg, st, clicks, view)
    eq(err, nil, 'no Lua error')
    return writes
end

-- SK Settings, opened through the HUD's cog (or closed with its X) unless it already is.
local function open_settings()
    if not settings_shown then render(settings.defaults(), status(), { ['##sk3_cog'] = true }) end
    assert(settings_shown, 'SK Settings open')
end

local function close_settings()
    if settings_shown then render(settings.defaults(), status(), { close = 'SK Settings' }) end
    assert(not settings_shown, 'SK Settings closed')
end

local function showed(s) return has(frame.texts, s) end

-- Some tooltip or text holds `s`.
local function tipped(s)
    for _, t in ipairs(frame.texts) do if t:find(s, 1, true) then return true end end
    return false
end

-- The draw calls named `name` on `list` ('window' when nil).
local function calls(name, list)
    local out = {}
    for _, d in ipairs(frame.drawn) do
        if d.name == name and d.list == (list or 'window') then out[#out + 1] = d end
    end
    return out
end

-- The colour `s` was last drawn in: its fill, drawn after its outline.
local function fill(s, list)
    local color
    for _, d in ipairs(calls('AddText', list)) do
        if d.args[5] == s then color = d.args[4] end
    end
    return color
end

local function rgb(r, g, b) return { r / 255, g / 255, b / 255, 1 } end
local WHITE, RED, AWAY = rgb(0xFF, 0xFF, 0xFF), rgb(0xF0, 0x7A, 0x7A), rgb(0xA0, 0xA0, 0xA0)

-- The HUD ---------------------------------------------------------------------------

test('the HUD draws running and stopped; SK Settings only once the cog opens it, until its X', function ()
    close_settings()
    for _, running in ipairs({ true, false }) do  -- stopped last, for its tooltip
        eq(render(settings.defaults(), status({ running = running })), 0)
        eq({ begun('Sidekick3'), begun('SK Settings') }, { true, false })
    end
    eq(tipped('WHM 75 / BLM 37\nStopped: would: Cure IV -> A (heal: A at 62%)\n[combat]\nTarget: Crab  50%  4.3y'), true)
    eq(render(settings.defaults(), status(), { ['##sk3_cog'] = true }), 0)
    eq({ begun('SK Settings'), showed('ready') }, { true, true })
    render(settings.defaults(), status({ running = true, intent = false, why = 'casting' }))
    eq({ begun('SK Settings'), tipped('Running: Cure IV -> A (heal: A at 62%)\n(casting)') }, { true, true })
    eq(render(settings.defaults(), status(), { close = 'SK Settings' }), 0)
    render(settings.defaults(), status())
    eq(begun('SK Settings'), false)
    open_settings()
    render(settings.defaults(), status(), { ['##sk3_cog'] = true })  -- the cog closes it too
    eq(begun('SK Settings'), false)
end)

test('a card per member: name and tag drawn as is, its HP % and MP % and the rest in its tooltip', function ()
    render(settings.defaults(), status())
    for _, s in ipairs({ 'Sidekick3', 'Me', 'A', 'B', 'ME', 'P1', 'P2' }) do eq(fill(s) ~= nil, true, s) end
    eq({ fill('62%'), fill('100%') }, { nil, nil })
    eq(tipped('A\nHP 62%  MP 100%  5.0y\nProtect\nShell'), true)
    eq(tipped('B (trust, away)\nHP 100%  MP 100%'), true)
end)

test('the panel and bars follow the UI settings', function ()
    local cfg = settings.defaults()
    cfg.ui.hp_width, cfg.ui.opacity = 300, 50
    render(cfg, status())
    local panel = calls('AddRectFilled')[1].args
    eq({ panel[1], panel[2][1], panel[3] }, { { 100, 50 }, 100 + 2 * 4 + 2 * 2 + 300, { 0x60 / 255, 0x60 / 255, 0x60 / 255, 0.5 } })
    local hp = calls('AddRectFilledMultiColor')[3].args  -- A's HP: 62% of 300
    eq({ hp[1], hp[2] }, { { 106, 50 + 23 + 64 + 8 + 2 }, { 106 + 186, 50 + 23 + 64 + 8 + 2 + 40 } })
    cfg.ui.hp_width, cfg.ui.mp_width, cfg.ui.text_size = 80, 80, 48  -- big text on short bars: the title row still fits
    render(cfg, status())
    eq(calls('AddRectFilled')[1].args[2][1], 100 + math.ceil(8 + 9 * 7 * 48 / 13 + 8 + 60 + 6))
end)

test('the HUD\'s items reach exactly the panel\'s far corner, so its auto-size fits the panel', function ()
    render(settings.defaults(), status())
    eq(frame.extent.Sidekick3, calls('AddRectFilled')[1].args[2])
    eq(frame.extent.Sidekick3, { 100 + 232, 50 + 23 + 3 * 64 + 2 * 8 + 4 })
end)

test('sizes out of their sliders\' range, set by hand or by a custom UI, are held to it', function ()
    close_settings()  -- its sliders would show the values as they are
    local cfg = settings.defaults()
    cfg.ui.text_size, cfg.ui.hp_width, cfg.ui.opacity = 0, 5000, -20  -- a zero text size would make zero-size icons
    render(cfg, status())
    local panel = calls('AddRectFilled')[1].args
    eq({ panel[2][1], panel[3][4] }, { 100 + 2 * 4 + 2 * 2 + 600, 0 })
end)

test('critical HP turns the name red, MP under the Recover line the tag', function ()
    local cfg, st = settings.defaults(), status()
    local g = fake.snap({
        { name = 'A', hpp = 20, mpp = 10 },
        { name = 'W', hpp = 90, mpp = 0, uses_mp = false },  -- no MP to recover
        { name = 'Gone', hpp = 25, in_zone = false },
    })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ fill('A'), fill('P1') }, { RED, RED })
    eq({ fill('W'), fill('P2') }, { WHITE, WHITE })
    eq({ fill('Me'), fill('ME') }, { WHITE, WHITE })
    eq({ fill('Gone'), fill('P3') }, { AWAY, AWAY })
end)

test('the alliance gets a thin HP row each under the cards, a gap before each party; the arrow points at one', function ()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea', hpp = 20 }, { kind = 'alliance', name = 'Bo', slot = 7 },
        { kind = 'alliance', name = 'Cy', slot = 12, in_zone = false } })
    local st = status({ intent = { at = 990, action = 'Cure IV', target = 'Bo', behavior = 'heal', why = 'Bo' } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    local cards = 23 + 2 * 64 + 8               -- title, two cards and the gap between them
    local b, c = cards + 8 + 2, cards + 8 + 2 + 2 * 20 + 8 + 2  -- each party's first bar top: after a gap and a border
    eq(frame.extent.Sidekick3, { 100 + 232, 50 + c + 20 + 4 })  -- the panel still fits its items exactly
    eq(calls('AddRectFilled')[1].args[2][2], 50 + c + 20 + 4)
    eq({ fill('B0 Bea'), fill('B1 Bo'), fill('C0 Cy'), fill('20%') }, { RED, WHITE, AWAY, nil })
    eq(tipped('Bea (alliance)\nHP 20%  MP 100%  5.0y'), true)
    local arrow = calls('AddTriangleFilled', 'background')
    eq({ #arrow, arrow[1].args[1] }, { 2, { 100 + 232 + 1, 50 + b + 20 + 9 } })  -- one arrow (fill, bevel): Bo's row, its centre
    eq(fill('Heal:Cure IV', 'background') ~= nil, true)
end)

test('the arrow points at the card the next action is for: yellow running, grey stopped, none idle', function ()
    render(settings.defaults(), status())
    local arrow = calls('AddTriangleFilled', 'background')[1].args
    eq({ arrow[1], arrow[4] }, { { 100 + 232 + 1, 50 + 23 + 72 + 32 }, rgb(0xB4, 0xB4, 0xB4) })  -- A's card, its centre
    eq(fill('Heal:Cure IV', 'background'), rgb(0xD0, 0xD0, 0xD0))
    render(settings.defaults(), status({ running = true }))
    eq(calls('AddTriangleFilled', 'background')[1].args[4], rgb(0xFF, 0xE5, 0x45))
    eq(fill('Heal:Cure IV', 'background'), WHITE)
    render(settings.defaults(), status({ intent = false }))
    eq(#calls('AddTriangleFilled', 'background'), 0)
end)

-- The icons drawn at (x, y): their discs' centres, in the order drawn.
local function discs()
    local out = {}
    for _, d in ipairs(calls('AddCircleFilled')) do out[#out + 1] = d.args[1] end
    return out
end

test('run and the cog sit at the top right of your own HP bar, the title row keeps close', function ()
    close_settings()
    render(settings.defaults(), status())
    -- Text 14: icons 17px. Your card's HP bar runs x 106-326 from y 75; close is in the title row at y 50.
    local c = discs()
    eq(c[1], { 100 + 232 - 6 - 17 + 8.5, 50 + 3 + 8.5 })                 -- close
    eq({ c[2], c[3] }, { { 326 - 2 - 17 - 4 - 17 + 8.5, 77 + 8.5 }, { 326 - 2 - 17 + 8.5, 77 + 8.5 } })  -- run, then the cog's body
    eq(#frame.args.InvisibleButton, 3)
    -- On a full bar the icons are cut in its colour; on an empty one, in the empty colour.
    local cfg, st = settings.defaults(), status()
    local g = fake.snap({ { name = 'A' } })
    g.me.hpp = 10
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(calls('AddTriangleFilled')[1].args[4], rgb(0x2E, 0x2E, 0x2E))  -- the play triangle, cut on empty
    render(settings.defaults(), status())
    eq(calls('AddTriangleFilled')[1].args[4], rgb(0xFF, 0x90, 0x90))
end)

test('a short HP bar shrinks the icons to fit it', function ()
    local cfg = settings.defaults()
    cfg.ui.hp_height = 12
    render(cfg, status())
    local c = discs()
    eq(c[2][2] - 75, 2 + 4)  -- 8px icons, 2px from the bar's top
    cfg.ui.hp_height, cfg.ui.hp_width, cfg.ui.text_size = 120, 80, 48  -- big text on a narrow bar: both still fit across it
    render(cfg, status())
    c = discs()
    eq({ c[2][1] - 18, c[3][1] + 18 }, { 106 + 80 - 2 - 36 - 4 - 36, 106 + 80 - 2 })  -- 36px icons, from the bar's left to its right
end)

test('an icon\'s tooltip replaces the card\'s', function ()
    render(settings.defaults(), status())  -- the fake hovers everything: the icons win
    eq({ tipped('Start automation'), tipped('Settings'), tipped('Me\nHP') }, { true, true, false })
    eq(tipped('A\nHP 62%'), true)
end)

test('the run icon starts and stops automation, for this session only', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['##sk3_run'] = true }), 0)
    eq(st.running, true)
    eq(render(cfg, st, { ['##sk3_run'] = true }), 0)
    eq(st.running, false)
    eq(cfg, settings.defaults())
end)

test('the close icon closes the HUD, remembers it, and hides SK Settings', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.ui.open = true
    eq(render(cfg, st, { ['##sk3_close'] = true }), 1)
    eq({ st.open, cfg.ui.open, begun('SK Settings') }, { false, false, false })
    render(cfg, st)
    eq(begun('SK Settings'), false)
end)

test('hidden, only the windows are begun and ended', function ()
    open_settings()
    eq(render(settings.defaults(), status(), { Begin = false }), 0)
    eq({ #frame.texts, #frame.drawn, begun('SK Settings') }, { 0, 0, true })
end)

test('a Lua error while drawing still ends both windows, then is raised', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    local view = model.build(snap(), cat, cfg, st, NAMES)
    view.recent = nil  -- in SK Settings
    eq(type(draw(window, cfg, st, nil, view)), 'string')
    view = model.build(snap(), cat, cfg, st, NAMES)
    view.party = nil  -- in the HUD
    eq(type(draw(window, cfg, st, nil, view)), 'string')
end)

test('a Lua error inside a combo or a table closes it before its window ends', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    local view = model.build(snap(), cat, cfg, st, NAMES)
    view.heal.focus_names = { false }  -- in the Focus combo
    eq(type(draw(window, cfg, st, nil, view)), 'string')
    view = model.build(snap(), cat, cfg, st, NAMES)
    for _, s in ipairs(view.sections) do
        if s.id == 'buff' then s.rows[1].targets = { {} } end  -- in the Buffs table
    end
    eq(type(draw(window, cfg, st, nil, view)), 'string')
end)

-- The widget ------------------------------------------------------------------------

local function widget_cfg()
    local cfg = settings.defaults()
    cfg.ui.widget = true
    return cfg
end

test('the widget is off at first; on, it shows the profile, the job and the status, its whole in the tooltip', function ()
    close_settings()
    render(settings.defaults(), status())
    eq(begun('SK Widget'), false)
    local cfg = widget_cfg()
    render(cfg, status())
    eq({ begun('SK Widget'), has(frame.args.Button, 'Default###sk3_widget_profile'), showed('WHM 75 / BLM 37'),
         showed('Stopped'), has(frame.args.Button, 'Start###sk3_widget_run') }, { true, true, true, true, true })
    eq(tipped('Stopped: would: Cure IV -> A (heal: A at 62%)'), true)
    eq(frame.flags['SK Widget'] - ImGuiWindowFlags_NoTitleBar - ImGuiWindowFlags_NoResize
        - ImGuiWindowFlags_AlwaysAutoResize - ImGuiWindowFlags_NoScrollbar, 0)
    render(cfg, status({ running = true, intent = false, why = 'casting' }))
    eq({ showed('Running'), tipped('(casting)'), has(frame.args.Button, 'Stop###sk3_widget_run') }, { true, true, true })
end)

test('the widget\'s Start/Stop runs this session only; Settings opens and closes SK Settings', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    remote_calls = {}
    eq(render(cfg, st, { ['Start###sk3_widget_run'] = true }), 0)
    eq({ st.running, remote_calls }, { true, {} })
    eq(render(cfg, st, { ['Stop###sk3_widget_run'] = true }), 0)
    eq(st.running, false)
    render(cfg, st, { ['Settings##sk3_widget_settings'] = true })
    render(cfg, st)
    eq(begun('SK Settings'), true)
    render(cfg, st, { ['Settings##sk3_widget_settings'] = true })
    render(cfg, st)
    eq(begun('SK Settings'), false)
end)

test('the widget\'s profile button lists the profiles: a click loads one, Default goes back', function ()
    local cfg, st = widget_cfg(), status()
    cfg.heal.danger = 40
    cfg.profiles['Sky##1'] = { heal = { danger = 20 } }
    eq(render(cfg, st, { ['##sk3_widget_profile_1'] = true }), 1)
    eq({ cfg.profile, cfg.heal.danger }, { 'Sky##1', 20 })
    render(cfg, st)
    eq({ has(frame.args.Button, 'Sky#1###sk3_widget_profile'), showed('Sky##1') }, { true, true })
    render(cfg, st, { ['Default##sk3_widget_profile_default'] = true })
    eq({ cfg.profile, cfg.heal.danger }, { '', 40 })
    cfg.profiles['Sky#'] = {}
    render(cfg, st, { ['##sk3_widget_profile_1'] = true })  -- sorted before Sky##1
    render(cfg, st)
    eq(has(frame.args.Button, 'Sky# ###sk3_widget_profile'), true)
end)

test('the widget offers Track for a player you target outside the alliance', function ()
    local g = fake.snap({ { name = 'A' } }, { target = { sid = 900, tidx = 1200, name = 'Stranger' } })
    local cfg, st = widget_cfg(), status()
    tracking_calls = {}
    render(cfg, st, { ['Track Stranger###sk3_widget_track'] = true }, model.build(g, cat, cfg, st, NAMES))
    eq(tracking_calls, { { 'add', 'Stranger' } })
    g.target = nil
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(has(frame.args.Button, 'Track Stranger###sk3_widget_track'), false)
end)

test('UI / Log turns the widget on and off; Lock position keeps it still too', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Widget##sk3_ui_widget'] = true }), 1)
    eq(cfg.ui.widget, true)
    render(cfg, st)
    local free = frame.flags['SK Widget']
    cfg.ui.locked = true
    render(cfg, st)
    eq(frame.flags['SK Widget'] - free, ImGuiWindowFlags_NoMove)
    eq(render(cfg, st, { ['Widget##sk3_ui_widget'] = true }), 1)
    eq(cfg.ui.widget, false)
    close_settings()
end)

test('with the HUD closed the widget still shows, and its Settings opens SK Settings; closing the HUD closes them', function ()
    close_settings()
    local cfg = widget_cfg()
    render(cfg, status({ open = false }))
    eq({ begun('Sidekick3'), begun('SK Widget') }, { false, true })
    render(cfg, status({ open = false }), { ['Settings##sk3_widget_settings'] = true })
    render(cfg, status({ open = false }))
    eq({ begun('Sidekick3'), begun('SK Settings') }, { false, true })
    render(cfg, status())
    render(cfg, status({ open = false }))  -- /sk3 closed the HUD
    eq(begun('SK Settings'), false)
    render(settings.defaults(), status({ open = false }))
    eq({ begun('Sidekick3'), begun('SK Widget'), begun('SK Settings') }, { false, false, false })
    render(settings.defaults(), status())
end)

test('the widget says the state alone: what it does or why it waits is in its tooltip', function ()
    local cfg = widget_cfg()
    render(cfg, status({ running = true, intent = false, why = 'holding Valor Minuet IV for Pianissimo' }))
    eq({ showed('Running'), tipped('(holding Valor Minuet IV for Pianissimo)') }, { true, true })
    local g = snap()
    g.afk = true
    local st = status({ running = true })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(showed('Asleep'), true)
end)

test('a Lua error in the widget still ends every window, then is raised', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    local view = model.build(snap(), cat, cfg, st, NAMES)
    view.track = nil  -- read by the widget alone while SK Settings is closed
    local err = draw(window, cfg, st, nil, view)
    eq({ type(err), begun('Sidekick3'), begun('SK Widget') }, { 'string', true, true })
end)

-- SK Settings -----------------------------------------------------------------------

-- SK Settings' headers for `cfg` (and `in_cat` in place of the catalog).
local function headers(cfg, in_cat)
    open_settings()
    local st = status()
    render(cfg, st, nil, in_cat and model.build(snap(), in_cat, cfg, st, NAMES))
    return frame.args.CollapsingHeader
end

test('a header for each group of sections, in order, closed at first; all its switches off, it says so', function ()
    local cfg = settings.defaults()
    cfg.buff.on = false
    eq(headers(cfg), { 'Profiles###sk3_Profiles', 'Follow (off)###sk3_Follow', 'Heal###sk3_Heal', 'Remove###sk3_Remove', 'Buff (off)###sk3_Buff',
        'Recover###sk3_Recover', 'Tracked###sk3_Tracked', 'AFK###sk3_AFK', 'UI / Log###sk3_UI / Log' })
    for _, flags in pairs(frame.headers) do eq(flags, 0) end
    eq(headers(settings.defaults(), fake.catalog(18, 75, nil, 0, { 'Repair', 'Deploy' })),  -- PUP
        { 'Profiles###sk3_Profiles', 'Follow (off)###sk3_Follow', 'Remove###sk3_Remove', 'Pet###sk3_Pet', 'Recover (off)###sk3_Recover',
          'Tracked###sk3_Tracked', 'AFK###sk3_AFK', 'UI / Log###sk3_UI / Log' })
end)

test('section switches write: Buffs, Follow, Wake sleepers, Resting', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Buffs##sk3_on_buff'] = true, ['Follow##sk3_on_follow'] = true,
        ['Wake sleepers##sk3_on_wake'] = true, ['Resting##sk3_on_rest'] = true }), 4)
    eq({ cfg.buff.on, cfg.follow.on, cfg.wake.on, cfg.rest.on }, { false, true, false, true })
end)

test('a row, its pick and its targets each write and save', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Protect##buff_Protect'] = true }), 1)
    eq(cfg.rows.Protect, { on = true })
    eq(render(cfg, st, { ['Protect II'] = true }), 1)
    eq(cfg.rows.Protect.pick, 'Protect II')
    eq(render(cfg, st, { ['P1##buff_Protect1'] = true }), 1)
    eq(cfg.rows.Protect.targets, { [0] = true, [1] = true })
    eq(render(cfg, st, { ['P4##buff_Protect4'] = true }), 0)  -- empty slot
    eq(cfg.rows.Protect.targets, { [0] = true, [1] = true })
    eq(render(cfg, st, { ['Cure##heal_Cure'] = true }), 1)
    eq(cfg.rows.Cure, { on = false })
    eq(render(cfg, st, { ['Echo Drops (0)###remove_Echo Drops'] = true }), 1)  -- an item, with how many you carry
    eq(cfg.rows['Echo Drops'], { on = true })
end)

test('items get a table of their own, with no empty pick or target columns', function ()
    open_settings()
    render(settings.defaults(), status())
    eq({ frame.columns['##sk3_rows_remove'], frame.columns['##sk3_rows_remove_items'], frame.columns['##sk3_rows_buff'] },
       { 2, 2, 4 })
    eq(showed('Items'), true)
end)

test('sliders, the focus and the options write the settings', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Danger under##sk3_heal_danger'] = 60 }), 1)
    eq(cfg.heal.danger, 60)
    eq(render(cfg, st, { ['A##sk3_heal_focus_A'] = true }), 1)  -- the focus combo's member
    eq(cfg.heal.focus, 'A')
    eq(render(cfg, st, { ['None##sk3_heal_focus_none'] = true }), 1)
    eq(cfg.heal.focus, '')
    eq(render(cfg, st, { ['Japanese client##sk3_japanese'] = true }), 1)
    eq(cfg.ui.japanese, true)
    eq(render(cfg, st, { ['Focus danger under##sk3_heal_focus_danger'] = 65 }), 1)
    eq(cfg.heal.focus_danger, 65)
    eq(frame.ids['SK Settings|Ask them to gather##sk3_buff_gather'], nil)  -- only while holding
    eq(render(cfg, st, { ['Hold area buffs for the group##sk3_buff_hold_aoe'] = true }), 1)
    eq(cfg.buff.hold_aoe, true)
    eq(render(cfg, st, { ['Ask them to gather##sk3_buff_gather'] = true }), 1)
    eq(cfg.buff.gather, false)
end)

test('a member combo shows a name as it was typed; a spell or roll the job lacks says so', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.heal.focus, cfg.follow.target = 'a', 'Gone'  -- /sk3 focus a: healing matches any case
    render(cfg, st)
    eq({ frame.previews['Focus##sk3_heal_focus'], frame.previews['Leader##sk3_follow_target'] }, { 'a', 'Gone' })
    cfg.heal.focus = ''
    render(cfg, st)
    eq(frame.previews['Focus##sk3_heal_focus'], 'None')
    local cor = fake.catalog(17, 75, 3, 37, { 'Corsair\'s Roll' })
    local g = snap()
    g.main = 17
    cfg.roll.first = 'Bolter\'s Roll'
    render(cfg, st, nil, model.build(g, cor, cfg, st, NAMES))
    eq(frame.previews['Roll 1##sk3_roll_first'], 'Bolter\'s Roll (not available)')
end)

test('recovery, pet, follow and rest settings write through act', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['MP under##sk3_recover_mp'] = 40, ['TP under##sk3_recover_tp'] = 1500 }), 2)
    eq({ cfg.recover.mp, cfg.recover.tp }, { 40, 1500 })
    eq(render(cfg, st, { ['Spend TP from##sk3_recover_min_tp'] = 1500 }), 0)  -- no Chivalry here
    local pld = model.build(snap(), fake.catalog(7, 75, nil, 0, { 'Chivalry' }), cfg, st, NAMES)
    eq(render(cfg, st, { ['Spend TP from##sk3_recover_min_tp'] = 1500 }, pld), 1)
    eq(cfg.recover.min_tp, 1500)
    local pup = model.build(snap(), fake.catalog(18, 75, nil, 0, { 'Repair', 'Deploy' }), cfg, st, NAMES)
    eq(render(cfg, st, { ['Pet HP under##sk3_pet_heal'] = 70 }, pup), 1)
    eq(cfg.pet.heal, 70)
    eq(render(cfg, st, { ['A##sk3_follow_target_A'] = true, ['Follow past##sk3_follow_distance'] = 9 }), 2)
    eq({ cfg.follow.target, cfg.follow.distance, cfg.heal.focus }, { 'A', 9, '' })
    eq(render(cfg, st, { ['Rest after##sk3_rest_delay'] = 8, ['Stand past##sk3_rest_distance'] = 12 }), 2)
    eq({ cfg.rest.delay, cfg.rest.distance }, { 8, 12 })
end)

test('AFK sleep: its minutes, and how it stands while running', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Sleep after##sk3_afk_minutes'] = 20, ['AFK sleep##sk3_on_afk'] = true }), 2)
    eq(cfg.afk, { on = false, minutes = 20 })
    local g = snap()
    g.afk_in = 125
    render(cfg, st, {}, model.build(g, cat, cfg, st, NAMES))
    eq(showed('Sleeps in 3 min without movement or combat.'), true)
    g.afk, g.afk_in = true, nil
    render(cfg, st, {}, model.build(g, cat, cfg, st, NAMES))
    eq(showed('Asleep: move to wake.'), true)
end)

test('a member unticked under Heal is skipped by healing', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['A##sk3_heal_A'] = true }), 1)
    eq(cfg.heal.skip, { A = true })
    eq(render(cfg, st, { ['A##sk3_heal_A'] = true }), 1)
    eq(cfg.heal.skip, {})
end)

test('UI / Log: the sliders size the HUD, Lock position keeps it still', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['HP bar width##sk3_ui_hp_width'] = 300, ['Name font size##sk3_ui_name_size'] = 30,
        ['Background opacity##sk3_ui_opacity'] = 50 }), 3)
    eq({ cfg.ui.hp_width, cfg.ui.name_size, cfg.ui.opacity }, { 300, 30, 50 })
    local free = frame.flags.Sidekick3
    eq(render(cfg, st, { ['Lock position##sk3_ui_locked'] = true }), 1)
    eq(cfg.ui.locked, true)
    render(cfg, st)
    eq(frame.flags.Sidekick3 - free, ImGuiWindowFlags_NoMove)
end)

test('the action log changes the session, not the settings; the recent list is under it', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Action log##sk3_log'] = true }), 0)
    eq({ st.log, showed('Cure IV -> A'), showed('heal: A at 62%') }, { false, true, true })
    eq(cfg, settings.defaults())
    render(cfg, status({ sent = {} }))
    eq(showed('Nothing sent yet.'), true)
end)

-- A custom UI gets the same checks as the standard window. The fake answers
-- false to any call it has no handler for; add one if yours needs it.
if package.searchpath('ui.custom', package.path) then
    test('ui/custom.lua draws running and stopped, every scope closed', function ()
        local custom = require('ui.custom')
        for _, running in ipairs({ false, true }) do
            eq(draw(custom, settings.defaults(), status({ running = running })), nil, 'no Lua error')
        end
    end)
end

test('a tracked player\'s card has its tag; Tracked lists them to untrack, and offers your target', function ()
    local g = fake.snap({ { name = 'A', tracked = true }, { kind = 'tracked', name = 'Out', hpp = 80, main = 3, main_lv = 75, sub = 4, sub_lv = 37 } },
        { target = { sid = 900, tidx = 1200, name = 'Stranger' } })
    local cfg, st = settings.defaults(), status()
    open_settings()
    tracking_calls = {}
    local writes = render(cfg, st, { ['Untrack##sk3_untrack_Out'] = true, ['Track Stranger##sk3_track'] = true },
        model.build(g, cat, cfg, st, NAMES))
    eq({ tracking_calls, writes }, { { { 'remove', 'Out' }, { 'add', 'Stranger' } }, 0 })
    eq(fill('T1') ~= nil, true)
    eq(tipped('Out (tracked, WHM 75 / BLM 37)\nHP 80%  5.0y'), true)
    eq({ showed('T1 Out  WHM 75 / BLM 37'), showed('P1 A  (in your party)') }, { true, true })
    g.target = nil
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(showed('Target a player outside your alliance to track them, or /sk3 track Name.'), true)
end)

test('Heal the alliance writes heal.alliance; alliance chips write their slot; Tracked lists one in the alliance', function ()
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea', tracked = true } })
    local cfg, st = settings.defaults(), status()
    open_settings()
    eq(render(cfg, st, { ['Heal the alliance##sk3_heal_alliance'] = true }), 1)
    eq(cfg.heal.alliance, true)
    eq(render(cfg, st, { ['B0##buff_Haste6'] = true }, model.build(g, cat, cfg, st, NAMES)), 1)
    eq(cfg.rows.Haste.targets, { [0] = true, [6] = true })
    eq(showed('B0 Bea  (in your alliance)'), true)
    eq(render(cfg, st, { ['Bea##sk3_heal_Bea'] = true }, model.build(g, cat, cfg, st, NAMES)), 1)  -- listed: heal.alliance is on
    eq(cfg.heal.skip, { Bea = true })
    eq({ fill('Bea'), fill('B0 Bea') }, { nil, WHITE })  -- no card in the HUD: a row
end)

local function profiles_named(cfg) return require('core.profiles').names(cfg) end

test('Profiles: Save names the profile loaded, a click loads one, Default goes back; the header names it', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.heal.danger = 40
    render(cfg, st, { ['Save as##sk3_profile_save_as'] = true })  -- the name typed is blank: nothing saved
    eq(next(cfg.profiles), nil)
    cfg.profiles.Dynamis = { heal = { danger = 20 } }
    local writes = render(cfg, st, { ['##sk3_profile_1'] = true })
    eq({ cfg.profile, cfg.heal.danger, cfg.parked.heal.danger, writes }, { 'Dynamis', 20, 40, 1 })
    render(cfg, st)
    eq(has(frame.args.CollapsingHeader, 'Profiles: Dynamis###sk3_Profiles'), true)
    eq(has(frame.args.Button, 'Delete##sk3_profile_delete'), true)
    cfg.heal.danger = 25
    render(cfg, st, { ['Save##sk3_profile_save'] = true })  -- the name field holds the one loaded
    eq(cfg.profiles.Dynamis.heal.danger, 25)
    render(cfg, st, { ['Default##sk3_profile_default'] = true })
    eq({ cfg.profile, cfg.heal.danger }, { '', 40 })
    render(cfg, st)
    eq(has(frame.args.Button, 'Delete##sk3_profile_delete'), false)
    render(cfg, st, { ['##sk3_profile_1'] = true })
    render(cfg, st, { ['New##sk3_profile_new'] = true })  -- the name loaded is cleared with it
    render(cfg, st, { ['Save##sk3_profile_save'] = true })
    eq({ profiles_named(cfg), cfg.profile }, { { 'Dynamis' }, '' })
end)

test('Profiles: a name with ## is drawn whole, each row its own; the header keeps one #; a taken name says so', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.profiles['Sky##2'], cfg.profiles['a###x'], cfg.profiles['b###x'] = {}, {}, {}
    render(cfg, st, { ['##sk3_profile_2'] = true })  -- names in order: a###x, b###x, Sky##2
    eq(cfg.profile, 'b###x')
    render(cfg, st, { ['##sk3_profile_3'] = true })
    eq(cfg.profile, 'Sky##2')
    render(cfg, st)
    eq({ showed('Sky##2'), showed('a###x'), has(frame.args.CollapsingHeader, 'Profiles: Sky#2###sk3_Profiles') },
        { true, true, true })
    render(cfg, st, { ['Default##sk3_profile_default'] = true })
    render(cfg, st)  -- the name field empties with Default
    eq(showed('a###x exists: Save as replaces it.'), false)
end)

test('SCH: a buff row\'s stratagem chips get a column of their own and each toggles', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Celerity', 'Accession', 'Perpetuance' })
    local cfg, st = settings.defaults(), status()
    local function view() return model.build(snap(), sch, cfg, st, NAMES) end
    eq(render(cfg, st, { ['Acc##buff_Protect_mod_Accession'] = true }, view()), 1)
    eq(cfg.rows.Protect, { on = false, mods = { Accession = true } })
    eq(frame.columns['##sk3_rows_buff'], 5)  -- name, pick, targets, stratagems, ready
    eq(render(cfg, st, { ['Acc##buff_Protect_mod_Accession'] = true }, view()), 1)
    eq(cfg.rows.Protect.mods, {})
    eq(render(cfg, st, { ['Hold##buff_Protect_hold'] = true }, view()), 1)
    eq({ cfg.rows.Protect.hold, tipped('No modifier is on here: it waits for nothing.') }, { true, true })
    render(cfg, st, {})
    eq(frame.columns['##sk3_rows_buff'], 4)  -- WHM: no stratagems, no column
end)

test('SCH: Keep a stratagem for healing, under Heal, only for a job with stratagems', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Accession' })
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['Keep a stratagem for healing##sk3_heal_reserve'] = true }, model.build(snap(), sch, cfg, st, NAMES)), 1)
    eq(cfg.heal.reserve, true)
    eq(render(cfg, st, { ['Keep a stratagem for healing##sk3_heal_reserve'] = true }), 0)  -- WHM: not drawn
end)

test('COR: Rolls under Buff picks each roll and the risk; Roll 2 only on a Corsair main job', function ()
    open_settings()
    local jas = { 'Corsair\'s Roll', 'Ninja Roll', 'Double-Up', 'Snake Eye', 'Fold' }
    local cor = fake.catalog(17, 75, 3, 37, jas)
    local cfg, st = settings.defaults(), status()
    local function view(main, sub, list)
        local g = snap()
        g.main, g.sub = main or 17, sub or 3
        g.roll = { id = 622, total = 4, at = 990 }
        g.me.buffs[322] = true  -- Ninja Roll on you
        return model.build(g, list or cor, cfg, st, NAMES)
    end
    eq(render(cfg, st, { ['Corsair\'s Roll (EXP+)##sk3_roll_first_Corsair\'s Roll'] = true }, view()), 1)
    eq(render(cfg, st, { ['Ninja Roll (EVA+)##sk3_roll_second_Ninja Roll'] = true }, view()), 1)
    eq(render(cfg, st, { ['Highest##sk3_roll_risk_highest'] = true, ['Rolls##sk3_on_roll'] = true }, view()), 2)
    eq(cfg.roll, { on = false, first = 'Corsair\'s Roll', second = 'Ninja Roll', risk = 'highest' })
    eq({ showed('Last: Ninja Roll 4 (lucky)'), tipped('Lucky 5, unlucky 9.') }, { true, true })
    cfg.roll.second = cfg.roll.first
    render(cfg, st, {}, view())
    eq(showed('Roll 2 is Roll 1: one roll kept up'), true)
    cfg.roll.first = 'Bolter\'s Roll'
    render(cfg, st, {}, view())
    eq(has(frame.args.BeginCombo, 'Roll 1##sk3_roll_first'), true)
    eq(has(frame.args.Selectable, 'None##sk3_roll_first_none'), true)
    render(cfg, st, {}, view(13, 17, fake.catalog(13, 75, 17, 37, jas)))  -- NIN / COR
    eq({ showed('Roll 2: Corsair main job only'), has(frame.args.BeginCombo, 'Roll 2##sk3_roll_second') }, { true, false })
end)

test('BRD: Songs under Buff: Area and each slot that is filled or has a pick, a combo per song slot', function ()
    open_settings()
    local brd = fake.catalog(10, 75, 3, 37, { 'Pianissimo' })
    local cfg, st = settings.defaults(), status()
    local function view(main, sub, list)
        local g = snap(); g.main, g.sub = main or 10, sub or 3
        return model.build(g, list or brd, cfg, st, NAMES)
    end
    local minuet = 'Valor Minuet IV (+ATK)##sk3_song_area_1_Valor Minuet IV'
    eq(render(cfg, st, { [minuet] = true, ['Mage\'s Ballad II (+Refresh)##sk3_song_p1_2_Mage\'s Ballad II'] = true }, view()), 2)
    eq({ cfg.song.area_1, cfg.song.p1_2 }, { 'Valor Minuet IV', 'Mage\'s Ballad II' })
    render(cfg, st, {}, view())
    eq({ frame.columns['##sk3_songs'], showed('Area'), showed('ME'), showed('P1'), showed('P2'), showed('P3') },
       { 4, true, true, true, true, false })  -- P2 is B, a trust in another zone; P3 is no one
    eq({ showed('Pianissimo: ready'), has(frame.args.BeginCombo, '##sk3_song_me_2') }, { true, true })
    eq(render(cfg, st, { ['Song Duration##sk3_song_duration'] = 170 }, view()), 1)  -- BRD 75 main
    eq(cfg.song.duration, 170)
    eq(render(cfg, st, { ['Pianissimo fast casting##sk3_song_fast'] = true }, view()), 1)
    eq(cfg.song.fast, true)
    cfg.song.p4_1 = 'Herb Pastoral'
    render(cfg, st, {}, view())
    eq({ showed('P4'), showed('no one') }, { true, true })  -- a pick keeps its line
    eq(render(cfg, st, { ['None##sk3_song_area_1_none'] = true, ['Songs##sk3_on_song'] = true }, view()), 2)
    eq({ cfg.song.area_1, cfg.song.on }, { '', false })
    render(cfg, st, {}, view(3, 10, fake.catalog(3, 75, 10, 15, {})))  -- WHM / BRD 15: one slot, no Pianissimo
    eq({ frame.columns['##sk3_songs'], showed('Songs on one member need Pianissimo (Bard 20)') }, { 3, true })
    eq(has(frame.args.SliderInt, 'Song Duration##sk3_song_duration'), false)  -- a subjob has no timers
    eq(has(frame.args.Checkbox, 'Pianissimo fast casting##sk3_song_fast'), false)  -- nor fast casting, with no Pianissimo
    eq(render(cfg, st, { [minuet] = true }), 0)  -- WHM: no Songs
end)

test('GEO: Geomancy under Buff: its rows, how far and how long, and Entrust\'s member and spell', function ()
    open_settings()
    local geo = fake.catalog(21, 75, nil, 0, { 'Full Circle', 'Blaze of Glory', 'Entrust' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 21; return model.build(g, geo, cfg, st, NAMES) end
    eq(render(cfg, st, { ['Recall past##sk3_geo_distance'] = 12, ['Keep after combat##sk3_geo_linger'] = 8 }, view()), 2)
    eq({ cfg.geo.distance, cfg.geo.linger }, { 12, 8 })
    eq(render(cfg, st, { ['A##sk3_geo_entrust_A'] = true, ['Indi-Fury##sk3_geo_entrust_spell_Indi-Fury'] = true }, view()), 2)
    eq({ cfg.geo.entrust, cfg.geo.entrust_spell }, { 'A', 'Indi-Fury' })
    eq(render(cfg, st, { ['P1##geo_geo1'] = true }, view()), 1)  -- the Geo row's target chips
    eq(cfg.rows.geo.targets, { [0] = true, [1] = true })
    eq(frame.columns['##sk3_rows_geo'], 4)  -- name, pick, targets, ready
    eq(render(cfg, st, { ['Recall past##sk3_geo_distance'] = 12 }), 0)  -- WHM: no Geomancy
end)

test('RUN: Runes under Buff: a line per set, a rune per slot by what it does, each ward\'s switch', function ()
    open_settings()
    local run = fake.catalog(22, 75, 4, 37, { 'Ignis', 'Gelus', 'Vallation', 'Pflug' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 22; return model.build(g, run, cfg, st, NAMES) end
    eq(render(cfg, st, { ['Fire##sk3_rune_idle_1_Ignis'] = true, ['Wind##sk3_rune_vallation_2_Gelus'] = true }, view()), 2)
    eq({ cfg.rune.idle_1, cfg.rune.vallation_2 }, { 'Ignis', 'Gelus' })
    eq(has(frame.args.Selectable, 'Silence / Weight##sk3_rune_pflug_3_Gelus'), true, 'Pflug shows the ailments')
    eq(tipped('Ignis: adds Fire, resists Ice, against Paralyze / Bind.'), true)
    render(cfg, st, {}, view())
    eq({ has(frame.args.BeginCombo, '##sk3_rune_idle_1'), showed('Idle') }, { true, true })
    eq(frame.columns['##sk3_runes'], 5)  -- the set, three slots, ready
    eq(render(cfg, st, { ['Pflug##sk3_rune_pflug'] = true, ['Runes##sk3_on_rune'] = true }, view()), 2)
    eq({ cfg.rows.Pflug.on, cfg.rune.on }, { false, false })
    cfg.rune.idle_2 = 'Lux'
    render(cfg, st, {}, view())
    eq(has(frame.args.BeginCombo, '##sk3_rune_idle_2'), true)
    local sub = fake.catalog(1, 75, 22, 37, { 'Ignis', 'Vallation' })
    local g = snap(); g.main, g.sub = 1, 22
    render(cfg, st, {}, model.build(g, sub, cfg, st, NAMES))  -- WAR / RUN 37: two slots
    eq({ frame.columns['##sk3_runes'], has(frame.args.BeginCombo, '##sk3_rune_idle_3') }, { 4, false })
    eq(render(cfg, st, { ['Fire##sk3_rune_idle_1_Ignis'] = true }), 0)  -- WHM: no Runes
end)

test('PUP: Maneuvers under Pet: a combo per slot by element, then whether they can go', function ()
    open_settings()
    local pup = fake.catalog(18, 75, 3, 37, { 'Fire Maneuver', 'Light Maneuver' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 18; return model.build(g, pup, cfg, st, NAMES) end
    eq(render(cfg, st, { ['Fire##sk3_maneuver_slot_1_Fire Maneuver'] = true, ['Light##sk3_maneuver_slot_3_Light Maneuver'] = true }, view()), 2)
    eq({ cfg.maneuver.slot_1, cfg.maneuver.slot_2, cfg.maneuver.slot_3 }, { 'Fire Maneuver', '', 'Light Maneuver' })
    render(cfg, st, {}, view())
    eq({ has(frame.args.BeginCombo, '##sk3_maneuver_slot_2'), frame.columns['##sk3_maneuvers'], showed('ready') }, { true, 4, true })
    eq(render(cfg, st, { ['None##sk3_maneuver_slot_1_none'] = true, ['Maneuvers##sk3_on_maneuver'] = true }, view()), 2)
    eq({ cfg.maneuver.slot_1, cfg.maneuver.on }, { '', false })
    eq(render(cfg, st, { ['Fire##sk3_maneuver_slot_1_Fire Maneuver'] = true }), 0)  -- WHM: no Maneuvers
end)

-- Remote control -------------------------------------------------------------------

-- A's a session too: its view as its own session publishes it (with its own settings).
local function remote_status(t)
    local st = status(t)
    st.sessions = { A = { running = false, members = { { sid = 101, name = 'A' } } } }
    st.watching = st.watching or {}
    return st
end

local function remote_view(cfg)
    local st = status({ running = true, sent = {} })
    return model.published(model.build(snap(), cat, cfg, st, NAMES))
end

test('another session\'s card has its run icon and cog: run starts it there, the cog shows its settings', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status()
    remote_calls = {}
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ has(frame.args.InvisibleButton, '##sk3_run_A'), has(frame.args.InvisibleButton, '##sk3_cog_A') }, { true, true })
    eq({ tipped('Start A\'s automation'), tipped('Settings for A'), tipped('A\nHP 62%') }, { true, true, false })
    eq(has(frame.args.InvisibleButton, '##sk3_run_B'), false)  -- a trust: no session
    eq(render(cfg, st, { ['##sk3_run_A'] = true }, model.build(snap(), cat, cfg, st, NAMES)), 0)
    eq({ remote_calls, st.running }, { { { 'A', 'run', true } }, false })  -- sent there, not run here
    st.sessions.A.running = true
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq(tipped('Stop A\'s automation'), true)
    render(cfg, st, { ['##sk3_cog_A'] = true }, model.build(snap(), cat, cfg, st, NAMES))
    eq({ st.watching, settings_shown }, { { A = true }, false })
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ begun('SK Settings: A###sk3_settings_A'), showed('Waiting for A\'s session...') }, { true, true })
    render(cfg, st, { ['##sk3_cog_A'] = true }, model.build(snap(), cat, cfg, st, NAMES))  -- the cog again hides it
    eq(st.watching, {})
end)

test('another session\'s SK Settings draw its view; changes go to it, never to your settings', function ()
    close_settings()
    local mine, theirs = settings.defaults(), settings.defaults()
    theirs.heal.danger = 33
    local st = remote_status({ watching = { A = true } })
    st.views = { A = remote_view(theirs) }
    remote_calls = {}
    local function frame_with(clicks) return render(mine, st, clicks, model.build(snap(), cat, mine, st, NAMES)) end
    eq(frame_with({ ['Danger under##sk3_heal_danger'] = 60, ['Cure##heal_Cure'] = true, ['Buffs##sk3_on_buff'] = true,
        ['Save as##sk3_profile_save_as'] = true }), 0)
    eq(remote_calls, { { 'A', 'save_profile', '', true }, { 'A', 'set', 'heal.danger', 60 }, { 'A', 'row', 'Cure', false },
        { 'A', 'section', 'buff', false } })  -- in the order drawn
    eq(mine, settings.defaults())
    eq({ showed('WHM 75 / BLM 37  Running'), showed('Nothing sent yet.') }, { true, true })  -- its own status and log
    eq({ has(frame.args.Checkbox, 'Action log##sk3_log'), has(frame.args.Checkbox, 'Japanese client##sk3_japanese'),
         has(frame.args.SliderInt, 'HP bar width##sk3_ui_hp_width') }, { false, false, false })  -- the HUD and log are its own
    frame_with({ close = 'SK Settings: A###sk3_settings_A' })
    eq(st.watching, {})
end)

test('your SK Settings and another session\'s draw side by side, each its own profile name', function ()
    open_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    cfg.profiles.Mine = {}
    cfg.profile = 'Mine'
    st.views = { A = remote_view(settings.defaults()) }
    remote_calls = {}
    render(cfg, st, { ['Save##sk3_profile_save'] = true }, model.build(snap(), cat, cfg, st, NAMES))
    eq({ begun('SK Settings'), begun('SK Settings: A###sk3_settings_A') }, { true, true })
    eq(remote_calls, { { 'A', 'save_profile', '' } })  -- A's name field: blank, A has no profile loaded
    eq(cfg.profiles.Mine.heal ~= nil, true)  -- the click also landed in your own window: saved there under Mine
end)

test('a view that won\'t draw closes its window and is not shown again; the HUD comes back', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    st.views = { A = { job = 'WHM 75', status = { state = 'Stopped' }, version = model.VIEW } }  -- broken: no sections
    local err = draw(window, cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ type(err), st.watching }, { 'string', {} })
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq(begun('SK Settings: A###sk3_settings_A'), false)
end)

test('another session\'s Tracked says where to target, its game not yours', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    local v = remote_view(cfg)
    v.track = {}
    st.views = { A = v }
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq(showed('Target a player outside the alliance in A\'s game to track them there.'), true)
    st.watching = {}
end)

test('a view from a session running another version is not drawn: it says to reload it', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    local v = remote_view(cfg)
    v.version = model.VIEW + 1
    st.views = { A = v }
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ showed('A runs another version of Sidekick3: /addon reload sidekick3 there.'), frame.args.CollapsingHeader },
       { true, nil })
    st.watching = {}
end)

test('chips and Heal ticks send the state they\'re set to, here and to another session', function ()
    open_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    st.views = { A = remote_view(settings.defaults()) }
    remote_calls = {}
    render(cfg, st, { ['P1##buff_Protect1'] = true, ['A##sk3_heal_A'] = true }, model.build(snap(), cat, cfg, st, NAMES))
    eq({ cfg.rows.Protect.targets, cfg.heal.skip }, { { [0] = true, [1] = true }, { A = true } })
    eq(remote_calls, { { 'A', 'skip', 'A', true }, { 'A', 'target', 'Protect', 1, true } })
    st.watching = {}
    close_settings()
end)
