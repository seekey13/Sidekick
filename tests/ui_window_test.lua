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

-- Openers and their closers. Every opener reports open (so every body draws, every
-- popup's list too) unless a test sets frame.clicks[opener] = false; Begin, BeginChild
-- and Push* need their closer either way. Style vars are counted apart: ImGui lets
-- them be pushed before a Begin and popped straight after it. Tabs are for custom UIs.
local CLOSER = {
    Begin = 'End', BeginChild = 'EndChild', BeginTable = 'EndTable', BeginCombo = 'EndCombo', BeginTabBar = 'EndTabBar',
    BeginTabItem = 'EndTabItem', BeginPopup = 'EndPopup', BeginPopupContextItem = 'EndPopup', BeginPopupContextWindow = 'EndPopup',
    PushStyleColor = 'PopStyleColor', PushItemWidth = 'PopItemWidth',
}
local ALWAYS = { Begin = true, BeginChild = true, PushStyleColor = true, PushItemWidth = true }
local IDS = { Checkbox = true, Button = true, InvisibleButton = true, SliderInt = true, BeginCombo = true,
              CollapsingHeader = true, BeginTabItem = true }

local frame  -- { stack, vars, texts, ids, args, flags, columns, drawn, window, cursor, extent, clicks, edited }

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
    TextDisabled = function (fmt) shown(fmt) end,
    SetTooltip = function (fmt) shown(fmt) end,
    IsItemHovered = function () return true end,
    -- The HUD's chrome reads this. A test sets clicks.hover = false for the faded frame.
    IsWindowHovered = function () return frame.hover ~= false end,
    SetNextWindowSize = function (size)
        point(size, 'SetNextWindowSize')
        frame.window_size = size
    end,
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
    -- A click is clicks[label] = true; a slider is dragged to clicks[label] = n (kit.dragged, below).
    InvisibleButton = function (label, size)
        placed(size, label)
        assert(size[1] > 0 and size[2] > 0, label .. ': ImGui asserts on a zero size')
        return frame.clicks[label] == true
    end,
    Selectable = function (label) return frame.clicks[label] == true end,
    -- Typing: clicks[label] = 'text' types it and presses Enter.
    InputText = function (label, v)
        assert(type(v) == 'table' and type(v[1]) == 'string', label .. ': value must be { string }')
        if type(frame.clicks[label]) ~= 'string' then return false end
        v[1] = frame.clicks[label]
        return true
    end,
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
            end
            return open
        elseif name:match('^End') or name == 'PopItemWidth' then
            pop(name)
        elseif handlers[name] then
            return handlers[name](...)
        end
        return false
    end
end })
package.preload['imgui'] = function () return imgui end
package.loaded['ui.kit'], package.loaded['ui.window'] = nil, nil
local window = require('ui.window')

-- The kit's clock steps a second a frame, so every eased value lands at once; a
-- slider is held while the test drags it, to the value it names.
local kit = require('ui.kit')
local P = kit.P
local tick = 0
kit.clock = function () tick = tick + 1; return tick end
kit.dragged = function (id) local v = frame.clicks[id]; return type(v) == 'number' and v or nil end

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

-- What act.remote sent, as { session, fn, args... }.
local remote_calls = {}
local function send(name, call)
    local c = { name }
    for i = 1, call.n + 1 do c[i + 1] = call[i] end
    remote_calls[#remote_calls + 1] = c
end

-- One frame of `ui`; returns the Lua error it raised, if any, and the number of
-- settings writes. `view` defaults to the model's.
local function draw(ui, cfg, st, clicks, view)
    frame = { stack = {}, vars = 0, texts = {}, ids = {}, args = {}, flags = {}, columns = {},
              drawn = {}, extent = {}, clicks = clicks or {} }
    frame.hover = frame.clicks.hover ~= false
    local writes = 0
    local act = model.actions(cfg, st, function () writes = writes + 1 end, TRACKING, send)
    local ok, err = pcall(ui.render, view or model.build(snap(), cat, cfg, st, NAMES), act)
    eq(frame.stack, {}, 'every ImGui scope closed')
    eq(frame.vars, 0, 'every style var popped')
    settings_shown = begun('SK Settings') and frame.clicks.close ~= 'SK Settings'
        and frame.clicks['##sk3_settings_close'] ~= true
    return not ok and err or nil, writes
end

-- One frame of the standard window; returns the number of settings writes.
local function render(cfg, st, clicks, view)
    local err, writes = draw(window, cfg, st, clicks, view)
    eq(err, nil, 'no Lua error')
    return writes
end

-- `clicks` with SK Settings' page `name` clicked too: the list of pages is drawn
-- first, so the page shows in that same frame.
local function on(name, clicks)
    clicks = clicks or {}
    clicks['##sk3_page_' .. name] = true
    return clicks
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

-- `s` was drawn: the drawn text, one string after another, a space apart, holds it
-- (so a note wrapped onto two lines still reads whole).
local function drew(s, list)
    local all = {}
    for _, d in ipairs(calls('AddText', list)) do all[#all + 1] = d.args[5] end
    return (' ' .. table.concat(all, ' ') .. ' '):find(s, 1, true) ~= nil
end

-- A widget's button was made: its id among this frame's invisible buttons.
local function button(id) return has(frame.args.InvisibleButton, id) end

local u32 = kit.u32

-- The HUD ---------------------------------------------------------------------------

test('the HUD draws running and stopped; SK Settings only once the cog opens it, until its X', function ()
    close_settings()
    for _, running in ipairs({ true, false }) do  -- stopped last, for its tooltip
        eq(render(settings.defaults(), status({ running = running })), 0)
        eq({ begun('Sidekick3'), begun('SK Settings') }, { true, false })
    end
    eq(tipped('WHM 75 / BLM 37\nStopped: would: Cure IV -> A (heal: A at 62%)\n[combat]\nTarget: Crab  50%  4.3y'), true)
    eq(render(settings.defaults(), status(), { ['##sk3_cog'] = true }), 0)
    eq({ begun('SK Settings'), drew('Follow past') }, { true, true })  -- its first page: Follow
    render(settings.defaults(), status({ running = true, intent = false, why = 'casting' }))
    eq({ begun('SK Settings'), tipped('Running: Cure IV -> A (heal: A at 62%)\n(casting)') }, { true, true })
    eq(render(settings.defaults(), status(), { close = 'SK Settings' }), 0)
    render(settings.defaults(), status())
    eq(begun('SK Settings'), false)
    open_settings()
    render(settings.defaults(), status(), { ['##sk3_settings_close'] = true })  -- its own X
    eq(begun('SK Settings'), true)
    render(settings.defaults(), status())
    eq(begun('SK Settings'), false)
    open_settings()
    render(settings.defaults(), status(), { ['##sk3_cog'] = true })  -- the cog closes it too
    eq(begun('SK Settings'), false)
end)

test('a card per member: name and tag drawn as is, its HP %, MP % and TP and the rest in its tooltip', function ()
    close_settings()
    render(settings.defaults(), status())
    for _, s in ipairs({ 'Sidekick3', 'Me', 'A', 'B', 'ME', 'P1', 'P2' }) do eq(fill(s) ~= nil, true, s) end
    eq({ fill('62%'), fill('100%') }, { nil, nil })
    eq(tipped('A\nHP 62%  MP 100%  TP 0  5.0y\nProtect\nShell'), true)
    eq(tipped('B (trust, away)\nHP 100%  MP 100%'), true)
end)

local BAR_FILL = 0.7        -- ui/window.lua's fill, at 70%
local BAR_TRACK_A = 0.7     -- each bar's gray background; it does not fade with the panel
local BAR_OFF = '#0c0c0c'   -- the empty track while the pointer is off the panel, and the stroke
local BAR_EDGE_A = 0.7      -- that 1px stroke, at the same 70%

-- The HP fill drawn from (x, y): its rectangle's far corner and its colour.
local function hp_fill(x, y)
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[1][1] == x and d.args[1][2] == y and d.args[3] == u32(P.hp, BAR_FILL) then return d.args[2] end
    end
end

-- A bar's near-black stroke, on the bar itself: w by h from (x, y), 1px at 70%.
local function bar_edge(x, y, w, h)
    for _, d in ipairs(calls('AddRect')) do
        if d.args[1][1] == x and d.args[1][2] == y and d.args[2][1] == x + w and d.args[2][2] == y + h
            and d.args[3] == u32(BAR_OFF, BAR_EDGE_A) and d.args[6] == nil then
            return true
        end
    end
end

test('the panel and bars follow the UI settings', function ()
    close_settings()
    local cfg = settings.defaults()
    cfg.ui.hp_width, cfg.ui.opacity = 300, 50
    render(cfg, status())
    local panel = calls('AddRectFilled')[1].args
    eq({ panel[1], panel[2][1], panel[3] }, { { 100, 50 }, 100 + 2 * 8 + 300, u32(P.bg, 0.5) })
    -- Title 25, then cards 40 + 3 + 18 + 3 + 8 high and 8 apart: A's, the third (under yours and your pet's), from
    -- y 235; 62% of 300.
    eq(hp_fill(108, 235), { 108 + 186, 235 + 40 })
    local rest, glow = false, false  -- the whole bar has a 70% gray background and a 1px near-black stroke, no bloom
    for _, d in ipairs(calls('AddRectFilled')) do
        rest = rest or (d.args[1][1] == 108 and d.args[1][2] == 235 and d.args[2][1] == 108 + 300
            and d.args[2][2] == 235 + 40 and d.args[3] == u32(P.track, BAR_TRACK_A))
    end
    for _, d in ipairs(calls('AddRect')) do
        local x, y = d.args[1][1], d.args[1][2]
        glow = glow or (x >= 105 and x < 108 and y >= 232 and y < 235)
    end
    eq({ rest, glow, bar_edge(108, 235, 300, 40) }, { true, false, true })
    cfg.ui.tp_width = 400  -- the widest bar sets the panel's width
    render(cfg, status())
    eq(calls('AddRectFilled')[1].args[2][1], 100 + 2 * 8 + 400)
    cfg.ui.hp_width, cfg.ui.mp_width, cfg.ui.tp_width, cfg.ui.text_size = 80, 80, 80, 48  -- big text on short bars: the title row still fits
    render(cfg, status())
    eq(calls('AddRectFilled')[1].args[2][1], 100 + math.ceil(8 + 9 * 7 * 48 / 13 + 8 + 60 + 8))
end)

test('the panel, frame, title and close fade out until the mouse is over the window; the bars stay', function ()
    close_settings()
    local cfg = settings.defaults()
    render(cfg, status(), { hover = false })
    eq(calls('AddRectFilled')[1].args[3], u32(P.bg, 0))
    eq(calls('AddRect')[1].args[3], u32(P.border, 0))
    eq(fill('Sidekick3'), u32(P.white, 0))
    local rose, back = false, false  -- the panel around the bars is gone; each bar's background is near-black at 70%
    for _, d in ipairs(calls('AddLine')) do rose = rose or d.args[3] == u32(P.rose, 0) end
    for _, d in ipairs(calls('AddRectFilled')) do
        back = back or (d.args[1][1] == 108 and d.args[1][2] == 75 and d.args[2][1] == 108 + 220
            and d.args[2][2] == 75 + 40 and d.args[3] == u32(BAR_OFF, BAR_TRACK_A))
    end
    eq({ rose, hp_fill(108, 75) ~= nil, back, bar_edge(108, 75, 220, 40) }, { true, true, true, true })
    render(cfg, status())  -- over it again: back to the Background opacity
    eq({ calls('AddRectFilled')[1].args[3], fill('Sidekick3') }, { u32(P.bg), u32(P.white) })
end)

test('the HUD\'s items reach exactly the panel\'s far corner, so its auto-size fits the panel', function ()
    close_settings()
    render(settings.defaults(), status())
    eq(frame.extent.Sidekick3, calls('AddRectFilled')[1].args[2])
    eq(frame.extent.Sidekick3, { 100 + 236, 50 + 25 + 4 * 72 + 3 * 8 + 8 })  -- yours, your pet's, A's and B's cards
end)

test('sizes out of their sliders\' range, set by hand or by a custom UI, are held to it', function ()
    close_settings()  -- its sliders would show the values as they are
    local cfg = settings.defaults()
    cfg.ui.text_size, cfg.ui.hp_width, cfg.ui.opacity = 0, 5000, -20  -- a zero text size would make zero-size buttons
    render(cfg, status())
    local panel = calls('AddRectFilled')[1].args
    eq({ panel[2][1], panel[3] }, { 100 + 2 * 8 + 600, u32(P.bg, 0) })
end)

test('a name turns yellow at 75% HP, orange at 50% and red at 25%; away greys it, low MP the tag', function ()
    close_settings()
    local cfg, st = settings.defaults(), status()
    local g = fake.snap({
        { name = 'High', hpp = 76 },
        { name = 'Yel', hpp = 75 },
        { name = 'Org', hpp = 50, mpp = 10 },
        { name = 'Red', hpp = 25 },
        { name = 'Gone', hpp = 10, in_zone = false },
        { kind = 'tracked', name = 'Mid', hpp = 51 },  -- still yellow: not at 50% yet
        { kind = 'tracked', name = 'Low', hpp = 26 },  -- still orange: not at 25% yet
    })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ fill('Me'), fill('High'), fill('Yel'), fill('Mid') },
        { u32(P.white), u32(P.white), u32(P.yellow), u32(P.yellow) })
    eq({ fill('Org'), fill('P3'), fill('Low'), fill('Red') },
        { u32(P.orange), u32(P.rose), u32(P.orange), u32(P.red) })
    eq({ fill('Gone'), fill('P5') }, { u32(P.dim), u32(P.dim) })
end)

-- The TP fills drawn: each one's corners and colour, in the order drawn.
local function tp_fills()
    local full, filling = u32(P.tp, BAR_FILL), u32(P.tp, 0.5 * BAR_FILL)
    local out = {}
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[3] == full or d.args[3] == filling then out[#out + 1] = { d.args[1], d.args[2], d.args[3] } end
    end
    return out
end

test('the TP bar, under the MP bar: a part per 1000 TP, each filling in turn, the one filling faint', function ()
    close_settings()
    local cfg, st = settings.defaults(), status()
    local function tp(n)
        render(cfg, st, nil, model.build(fake.snap({ { name = 'A', tp = n } }), cat, cfg, st, NAMES))
        return tp_fills()
    end
    -- A's card from y 155 (under yours, 72 high, and a gap): its TP bar from 155 + 40 + 3 + 18 + 3, 8 high. Its three
    -- parts share 220 less two gaps of 3: x 108-179, 182-254 and 257-328.
    eq(tp(1500), { { { 108, 219 }, { 179, 227 }, u32(P.tp, BAR_FILL) }, { { 182, 219 }, { 218, 227 }, u32(P.tp, 0.5 * BAR_FILL) } })
    eq(bar_edge(108, 219, 71, 8), true)  -- the stroke stays on each part, full even while that part is still filling
    eq(tipped('A\nHP 100%  MP 100%  TP 1500  5.0y'), true)
    eq(tp(3000), { { { 108, 219 }, { 179, 227 }, u32(P.tp, BAR_FILL) }, { { 182, 219 }, { 254, 227 }, u32(P.tp, BAR_FILL) },
                   { { 257, 219 }, { 328, 227 }, u32(P.tp, BAR_FILL) } })
    eq(#tp(0), 0)
    render(cfg, st, nil, model.build(fake.snap({ { kind = 'tracked', name = 'Out', tp = 0 } }), cat, cfg, st, NAMES))
    eq(tipped('Out (tracked)\nHP 100%  5.0y'), true)  -- a tracked player's TP can't be read
end)

test('your pet\'s card sits under yours, before P1: its HP, MP and TP, and its own tooltip', function ()
    close_settings()
    local cfg, st = settings.defaults(), status()
    local g = fake.snap({ { name = 'A' } }, { pet = { name = 'Ifrit', hpp = 50, mpp = 40, tp = 1000, dist = 3 } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ hp_fill(108, 75), hp_fill(108, 155), hp_fill(108, 235) }, { { 328, 115 }, { 108 + 110, 195 }, { 328, 275 } })
    eq({ fill('Ifrit'), fill('PET') }, { u32(P.orange), u32(P.text2) })  -- 50% HP: the name is orange
    eq(tp_fills(), { { { 108, 155 + 64 }, { 179, 155 + 72 }, u32(P.tp, BAR_FILL) } })  -- 1000 TP: one part, full
    eq(tipped('Ifrit (pet)\nHP 50%  MP 40%  TP 1000  3.0y'), true)
    g.pet = nil
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ fill('PET'), hp_fill(108, 155) }, { nil, { 328, 195 } })  -- no pet: A's card under yours
end)

test('the arrow points at your pet\'s card for its care and sending it in', function ()
    close_settings()
    local cfg = settings.defaults()
    for _, b in ipairs({ 'pet', 'pet_send', 'heal' }) do
        local st = status({ intent = { at = 990, action = 'Healing Ruby', behavior = b, why = 'Carbuncle at 40%' } })
        render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
        local arrow = calls('AddTriangleFilled', 'background')
        eq({ #arrow, arrow[1].args[1][2] }, { 1, b == 'heal' and 75 + 36 or 155 + 36 }, b)  -- yours for a heal of no one
    end
end)

test('the alliance gets a thin HP row each under the cards, a gap before each party; the arrow points at one', function ()
    close_settings()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea', hpp = 20 },
        { kind = 'alliance', name = 'Bo', slot = 7, hpp = 75 }, { kind = 'alliance', name = 'Cy', slot = 12, in_zone = false } })
    local st = status({ intent = { at = 990, action = 'Cure IV', target = 'Bo', behavior = 'heal', why = 'Bo' } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    local cards = 25 + 2 * 72 + 8               -- title, two cards and the gap between them
    local b, c = cards + 8, cards + 8 + 18 + 3 + 18 + 8  -- each party's first bar top: after a gap
    eq(frame.extent.Sidekick3, { 100 + 236, 50 + c + 18 + 8 })  -- the panel still fits its items exactly
    eq(calls('AddRectFilled')[1].args[2][2], 50 + c + 18 + 8)
    eq({ fill('B0 Bea'), fill('B1 Bo'), fill('C0 Cy'), fill('20%') }, { u32(P.red), u32(P.yellow), u32(P.dim), nil })
    eq(tipped('Bea (alliance)\nHP 20%  MP 100%  TP 0  5.0y'), true)
    local arrow = calls('AddTriangleFilled', 'background')
    eq({ #arrow, arrow[1].args[1] }, { 1, { 100 + 236 + 2, 50 + b + 18 + 3 + 9 } })  -- its point: Bo's row, its middle
    eq(fill('Heal:Cure IV', 'background') ~= nil, true)
end)

test('the arrow\'s label points at the card the next action is for: amber running, grey stopped, none idle', function ()
    close_settings()
    render(settings.defaults(), status())
    local arrow = calls('AddTriangleFilled', 'background')[1].args
    eq({ arrow[1], arrow[4] }, { { 100 + 236 + 2, 50 + 25 + 2 * 80 + 36 }, u32(P.seg) })  -- A's card, under your pet's: its middle
    eq(fill('Heal:Cure IV', 'background'), u32(P.text2))
    render(settings.defaults(), status({ running = true }))
    eq(calls('AddTriangleFilled', 'background')[1].args[4], u32(P.amber))
    eq(fill('Heal:Cure IV', 'background'), u32(P.ink))
    render(settings.defaults(), status({ intent = false }))
    eq(#calls('AddTriangleFilled', 'background'), 0)
end)

-- The pills drawn in `color` on the background list: each one's AddRectFilled arguments.
local function pills(color)
    local out = {}
    for _, d in ipairs(calls('AddRectFilled', 'background')) do
        if d.args[3] == u32(color) then out[#out + 1] = d.args end
    end
    return out
end

test('another session\'s label is blue, after its name: after yours on the same card, else pointing itself', function ()
    close_settings()
    local cfg = settings.defaults()
    local st = status({ running = true })
    st.sessions = { A = { running = true, members = { { sid = 101, name = 'A' } },
                          act = { behavior = 'buff', action = 'Haste', target = 'A' } } }  -- the card yours is at
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    local own, theirs, name = pills(P.amber), pills(P.accent), pills(P.accent_lo)
    eq({ #own, #theirs, #name, #calls('AddTriangleFilled', 'background') }, { 1, 1, 1, 1 })  -- one point: yours
    eq(theirs[1][1][1] > own[1][2][1], true)  -- after yours
    eq({ theirs[1][1][2], name[1][1] }, { own[1][1][2], theirs[1][1] })  -- in line; its name at its left
    eq({ fill('A', 'background'), fill('Buff:Haste', 'background') }, { u32(P.white), u32(P.ink) })
    st.intent, st.sent = false, {}
    st.sessions.A.act = { behavior = 'heal', action = 'Cure IV', target = 'Me' }  -- yours only: it points itself
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    local tri = calls('AddTriangleFilled', 'background')
    eq({ #tri, tri[1].args[1], tri[1].args[4], #pills(P.amber) }, { 1, { 100 + 236 + 2, 75 + 36 }, u32(P.accent), 0 })
end)

-- The round buttons and glyphs drawn: their discs' centres and colours, in the order drawn.
local function discs()
    local out = {}
    for _, d in ipairs(calls('AddCircleFilled')) do out[#out + 1] = { d.args[1][1], d.args[1][2], d.args[3] } end
    return out
end

-- The close mark's X: the two strokes' shared middle, and the colour of the first.
local function close_x()
    local lines = {}
    for _, d in ipairs(calls('AddLine')) do
        if d.args[3] == u32(P.rose) then lines[#lines + 1] = d.args end
    end
    if #lines < 2 then return nil end
    local a, b = lines[1][1], lines[1][2]
    return { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 }
end

test('run and the cog sit at the top right of your own HP bar, the title row keeps close; lit while on', function ()
    close_settings()
    render(settings.defaults(), status())
    -- Text 14: buttons 17px. Your card's HP bar runs x 108-328 from y 75. Close is an X in the title row, no disc.
    local c = discs()
    eq(close_x(), { 100 + 236 - 8 - 8.5, 50 + 12.5 })
    eq({ c[1][1], c[1][2], c[2][1], c[2][2] }, { 328 - 2 - 17 - 4 - 17 + 8.5, 77 + 8.5, 328 - 2 - 17 + 8.5, 77 + 8.5 })
    eq(#frame.args.InvisibleButton, 3)
    -- The fake hovers everything: run unlit is the accent's low shade, lit its light one; the cog lit while SK Settings shows.
    eq({ c[1][3], c[2][3] }, { u32(P.accent_lo), u32(P.accent_lo) })
    render(settings.defaults(), status({ running = true }))
    eq(discs()[1][3], u32(P.accent2))
    open_settings()
    render(settings.defaults(), status())
    eq(discs()[2][3], u32(P.accent2))
    eq(close_x() ~= nil, true)  -- SK Settings' X, rose under the pointer, and no disc of its own
    close_settings()
end)

test('a short HP bar shrinks the buttons to fit it', function ()
    close_settings()
    local cfg = settings.defaults()
    cfg.ui.hp_height = 12
    render(cfg, status())
    local c = discs()
    eq(c[1][2] - 75, 2 + 4)  -- 8px buttons, 2px from the bar's top
    cfg.ui.hp_height, cfg.ui.hp_width, cfg.ui.text_size = 120, 80, 48  -- big text on a narrow bar: both still fit across it
    render(cfg, status())
    c = discs()
    eq({ c[1][1] - 18, c[2][1] + 18 }, { 108 + 80 - 2 - 36 - 4 - 36, 108 + 80 - 2 })  -- 36px buttons, from the bar's left to its right
end)

test('a button\'s tooltip replaces the card\'s', function ()
    close_settings()
    render(settings.defaults(), status())  -- the fake hovers everything: the buttons win
    eq({ tipped('Start automation'), tipped('Settings'), tipped('Me\nHP') }, { true, true, false })
    eq(tipped('A\nHP 62%'), true)
end)

test('the run button starts and stops automation, for this session only', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['##sk3_run'] = true }), 0)
    eq(st.running, true)
    eq(render(cfg, st, { ['##sk3_run'] = true }), 0)
    eq(st.running, false)
    eq(cfg, settings.defaults())
end)

test('the close button closes the HUD, remembers it, and hides SK Settings', function ()
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
    view.sections = nil  -- in SK Settings
    eq(type(draw(window, cfg, st, nil, view)), 'string')
    view = model.build(snap(), cat, cfg, st, NAMES)
    view.recent = nil  -- in SK Settings' UI / Log page, inside its scrolling child
    eq(type(draw(window, cfg, st, on('UI / Log'), view)), 'string')
    view = model.build(snap(), cat, cfg, st, NAMES)
    view.party = nil  -- in the HUD
    eq(type(draw(window, cfg, st, nil, view)), 'string')
end)

-- The widget ------------------------------------------------------------------------

local function widget_cfg()
    local cfg = settings.defaults()
    cfg.ui.widget = true
    return cfg
end

test('the widget is off at first; on, it shows the profile, the job and the state, its whole in the tooltip', function ()
    close_settings()
    render(settings.defaults(), status())
    eq(begun('SK Widget'), false)
    local cfg = widget_cfg()
    render(cfg, status({ open = false }))  -- the HUD closed, so the tooltip is the widget's
    eq({ begun('SK Widget'), button('##sk3_widget_profile'), drew('Default'), drew('WHM 75 / BLM 37'), drew('Stopped'),
         button('##sk3_widget_run'), drew(' Start ') }, { true, true, true, true, true, true, true })
    eq(tipped('Stopped: would: Cure IV -> A (heal: A at 62%)'), true)
    eq(frame.flags['SK Widget'] - ImGuiWindowFlags_NoTitleBar - ImGuiWindowFlags_NoResize - ImGuiWindowFlags_AlwaysAutoResize
        - ImGuiWindowFlags_NoScrollbar - ImGuiWindowFlags_NoScrollWithMouse - ImGuiWindowFlags_NoBackground, 0)
    eq(frame.extent['SK Widget'], calls('AddRectFilled')[1].args[2])  -- its items reach its panel's far corner
    render(cfg, status({ open = false, running = true, intent = false, why = 'casting' }))
    eq({ drew('Running'), tipped('(casting)'), drew(' Stop ') }, { true, true, true })
end)

test('the widget\'s Start/Stop runs this session only; Settings opens and closes SK Settings', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    remote_calls = {}
    eq(render(cfg, st, { ['##sk3_widget_run'] = true }), 0)
    eq({ st.running, remote_calls }, { true, {} })
    eq(render(cfg, st, { ['##sk3_widget_run'] = true }), 0)
    eq(st.running, false)
    render(cfg, st, { ['##sk3_widget_settings'] = true })
    render(cfg, st)
    eq(begun('SK Settings'), true)
    render(cfg, st, { ['##sk3_widget_settings'] = true })
    render(cfg, st)
    eq(begun('SK Settings'), false)
end)

test('the widget\'s profile drop-down lists the profiles: a click loads one, Default goes back', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    cfg.heal.danger = 40
    cfg.profiles['Sky##1'] = { heal = { danger = 20 } }
    eq(render(cfg, st, { ['##sk3_widget_profile_1'] = true }), 1)
    eq({ cfg.profile, cfg.heal.danger }, { 'Sky##1', 20 })
    render(cfg, st)
    eq({ drew('Sky##1'), tipped('Sky##1') }, { true, true })  -- whole, in its box and in its list
    render(cfg, st, { ['Default##sk3_widget_profile_default'] = true })
    eq({ cfg.profile, cfg.heal.danger }, { '', 40 })
end)

test('the widget offers Track for a player you target outside the alliance', function ()
    close_settings()
    local g = fake.snap({ { name = 'A' } }, { target = { sid = 900, tidx = 1200, name = 'Stranger' } })
    local cfg, st = widget_cfg(), status()
    tracking_calls = {}
    render(cfg, st, { ['##sk3_widget_track'] = true }, model.build(g, cat, cfg, st, NAMES))
    eq({ tracking_calls, drew('Track Stranger') }, { { { 'add', 'Stranger' } }, true })
    g.target = nil
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ button('##sk3_widget_track'), drew('Track Stranger') }, { false, false })
end)

test('UI / Log turns the widget on and off; Lock position keeps it still too', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log', { ['Widget##sk3_ui_widget'] = true })), 1)
    eq(cfg.ui.widget, true)
    render(cfg, st)
    local free = frame.flags['SK Widget']
    cfg.ui.locked = true
    render(cfg, st)
    eq(frame.flags['SK Widget'] - free, ImGuiWindowFlags_NoMove)
    eq(render(cfg, st, on('UI / Log', { ['Widget##sk3_ui_widget'] = true })), 1)
    eq(cfg.ui.widget, false)
    close_settings()
end)

test('with the HUD closed the widget still shows, and its Settings opens SK Settings; closing the HUD closes them', function ()
    close_settings()
    local cfg = widget_cfg()
    render(cfg, status({ open = false }))
    eq({ begun('Sidekick3'), begun('SK Widget') }, { false, true })
    render(cfg, status({ open = false }), { ['##sk3_widget_settings'] = true })
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
    close_settings()
    local cfg = widget_cfg()
    render(cfg, status({ open = false, running = true, intent = false, why = 'holding Valor Minuet IV for Pianissimo' }))
    eq({ drew('Running'), tipped('(holding Valor Minuet IV for Pianissimo)'), drew('holding') }, { true, true, false })
    local g = snap()
    g.afk = true
    local st = status({ open = false, running = true })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(drew('Asleep'), true)
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

-- SK Settings' pages for `cfg` (and `in_cat` in place of the catalog), in the list's order.
local function pages(cfg, in_cat)
    open_settings()
    local st = status()
    render(cfg, st, nil, in_cat and model.build(snap(), in_cat, cfg, st, NAMES))
    local out = {}
    for _, id in ipairs(frame.args.InvisibleButton) do
        local name = id:match('^##sk3_page_(.*)')
        if name then out[#out + 1] = name end
    end
    return out
end

test('SK Settings is one fixed width, the same for every job', function ()
    open_settings()
    render(settings.defaults(), status())
    local size = { kit.S(160) + kit.S(390) + 2 * kit.S(6), kit.S(580) + 2 * kit.S(6) }
    eq(frame.window_size, size)
    local pup = fake.catalog(18, 75, nil, 0, { 'Repair', 'Deploy' })
    render(settings.defaults(), status(), nil, model.build(snap(), pup, settings.defaults(), status(), NAMES))
    eq(frame.window_size, size)
end)

test('a page for each group of sections, in order, Profiles and UI / Log at the foot; one with every switch off a ring', function ()
    local cfg = settings.defaults()
    cfg.buff.on = false
    eq(pages(cfg), { 'Follow', 'Heal', 'Remove', 'Buff', 'Recover', 'Tracked', 'AFK', 'Profiles', 'UI / Log' })
    eq(#calls('AddCircle'), 2)  -- Follow and Buff: all off
    eq(pages(settings.defaults(), fake.catalog(18, 75, nil, 0, { 'Repair', 'Deploy' })),  -- PUP
        { 'Follow', 'Remove', 'Pet', 'Recover', 'Tracked', 'AFK', 'Profiles', 'UI / Log' })
    eq(#calls('AddCircle'), 2)  -- Follow and Recover
end)

test('a click on a page shows it; a click on a section\'s title folds it, and again unfolds it', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Heal'))
    eq({ button('##sk3_fold_heal'), button('##sk3_fold_revive'), button('##sk3_fold_buff') }, { true, true, false })
    eq({ button('Danger under##sk3_danger'), button('Cure##heal_Cure') }, { true, true })
    render(cfg, st, { ['##sk3_fold_heal'] = true })
    render(cfg, st)
    eq({ button('Danger under##sk3_danger'), button('Cure##heal_Cure'), button('##sk3_fold_revive') }, { false, false, true })
    render(cfg, st, { ['##sk3_fold_heal'] = true })
    render(cfg, st, on('Buff'))
    eq({ button('##sk3_fold_buff'), button('##sk3_fold_heal') }, { true, false })
    render(cfg, st, on('Heal'))
    eq(button('Cure##heal_Cure'), true)
end)

test('section switches write: Buffs, Follow, Wake sleepers, Resting', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Buff', { ['Buffs##sk3_on_buff'] = true })), 1)
    eq(render(cfg, st, on('Follow', { ['Follow##sk3_on_follow'] = true })), 1)
    eq(render(cfg, st, on('Remove', { ['Wake sleepers##sk3_on_wake'] = true })), 1)
    eq(render(cfg, st, on('Recover', { ['Resting##sk3_on_rest'] = true })), 1)
    eq({ cfg.buff.on, cfg.follow.on, cfg.wake.on, cfg.rest.on }, { false, true, false, true })
end)

test('a section switched off draws its rows faded, still settable', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Buff'))
    eq(fill('Protect'), u32(P.dim))  -- a buff row starts off: its name dimmed
    cfg.buff.on = false
    eq(render(cfg, st, on('Buff', { ['Protect##buff_Protect'] = true })), 1)
    eq({ fill('Protect'), cfg.rows.Protect.on }, { u32(P.dim, 0.55), true })
end)

test('a row, its pick and its targets each write and save', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Buff', { ['Protect##buff_Protect'] = true })), 1)
    eq(cfg.rows.Protect, { on = true })
    eq(render(cfg, st, on('Buff', { ['Protect II'] = true })), 1)
    eq(cfg.rows.Protect.pick, 'Protect II')
    eq(render(cfg, st, on('Buff', { ['P1##buff_Protect1'] = true })), 1)
    eq(cfg.rows.Protect.targets, { [0] = true, [1] = true })
    eq(render(cfg, st, on('Buff', { ['P4##buff_Protect4'] = true })), 0)  -- empty slot
    eq(cfg.rows.Protect.targets, { [0] = true, [1] = true })
    eq(render(cfg, st, on('Heal', { ['Cure##heal_Cure'] = true })), 1)
    eq(cfg.rows.Cure, { on = false })
    eq(render(cfg, st, on('Remove', { ['Echo Drops (0)###remove_Echo Drops'] = true })), 1)  -- an item, with how many you carry
    eq(cfg.rows['Echo Drops'], { on = true })
end)

test('items get a heading of their own, with no pick or targets', function ()
    open_settings()
    render(settings.defaults(), status(), on('Remove'))
    eq({ drew('I T E M S'), button('Echo Drops (0)###remove_Echo Drops'), button('##pick_remove_Echo Drops') }, { true, true, false })
    render(settings.defaults(), status(), on('Buff'))
    eq({ button('##pick_buff_Protect'), button('P1##buff_Protect1'), drew('I T E M S') }, { true, true, false })
end)

test('sliders, the focus and the options write the settings', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['Danger under##sk3_danger'] = 60 })), 1)
    eq(cfg.heal.danger, 60)
    eq(render(cfg, st, on('Heal', { ['A##sk3_focus_A'] = true })), 1)  -- the focus drop-down's member
    eq(cfg.heal.focus, 'A')
    eq(render(cfg, st, on('Heal', { ['None##sk3_focus_none'] = true })), 1)
    eq(cfg.heal.focus, '')
    eq(render(cfg, st, on('UI / Log', { ['Japanese client##sk3_japanese'] = true })), 1)
    eq(cfg.ui.japanese, true)
    eq(render(cfg, st, on('Heal', { ['Focus danger under##sk3_focus_danger'] = 65 })), 1)
    eq(cfg.heal.focus_danger, 65)
    render(cfg, st, on('Buff'))
    eq(frame.ids['SK Settings|Ask them to gather##sk3_gather'], nil)  -- only while holding
    eq(render(cfg, st, on('Buff', { ['Hold area buffs for the group##sk3_hold_aoe'] = true })), 1)
    eq(cfg.buff.hold_aoe, true)
    eq(render(cfg, st, on('Buff', { ['Ask them to gather##sk3_gather'] = true })), 1)
    eq(cfg.buff.gather, false)
end)

test('a heal line at or under its danger line says only danger heals go', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    local MINE, FOCUS = 'Heal under is at or under Danger under', 'Focus heal under is at or under Focus danger under'
    render(cfg, st, on('Heal'))
    eq({ drew(MINE), drew(FOCUS) }, { false, false })
    cfg.heal.threshold, cfg.heal.focus_threshold = cfg.heal.danger, cfg.heal.focus_danger - 1
    render(cfg, st, on('Heal'))
    eq({ drew(MINE), drew(FOCUS) }, { true, true })
end)

test('a slider\'s value, clicked, takes a typed number, held to its range', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['Danger under##sk3_danger.value'] = true, ['##Danger under##sk3_danger.typed'] = '45' })), 1)
    eq(cfg.heal.danger, 45)
    eq(render(cfg, st, on('Heal', { ['##Danger under##sk3_danger.typed'] = '250' })), 1)
    eq(cfg.heal.danger, 99)
    eq(render(cfg, st, on('Heal', { ['##Danger under##sk3_danger.typed'] = 'lots' })), 0)
end)

test('recovery, pet, follow and rest settings write through act', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Recover', { ['MP under##sk3_recover_mp'] = 40, ['TP under##sk3_recover_tp'] = 1500 })), 2)
    eq({ cfg.recover.mp, cfg.recover.tp }, { 40, 1500 })
    eq(render(cfg, st, on('Recover', { ['Spend TP from##sk3_recover_min_tp'] = 1500 })), 0)  -- no Chivalry here
    local pld = model.build(snap(), fake.catalog(7, 75, nil, 0, { 'Chivalry' }), cfg, st, NAMES)
    eq(render(cfg, st, on('Recover', { ['Spend TP from##sk3_recover_min_tp'] = 1500 }), pld), 1)
    eq(cfg.recover.min_tp, 1500)
    local pup = model.build(snap(), fake.catalog(18, 75, nil, 0, { 'Repair', 'Deploy' }), cfg, st, NAMES)
    eq(render(cfg, st, on('Pet', { ['Pet HP under##sk3_pet_heal'] = 70 }), pup), 1)
    eq(cfg.pet.heal, 70)
    eq(render(cfg, st, on('Follow', { ['A##sk3_follow_target_A'] = true, ['Follow past##sk3_follow_distance'] = 9 })), 2)
    eq({ cfg.follow.target, cfg.follow.distance, cfg.heal.focus }, { 'A', 9, '' })
    eq(render(cfg, st, on('Recover', { ['Rest after##sk3_rest_delay'] = 8, ['Stand past##sk3_rest_distance'] = 12 })), 2)
    eq({ cfg.rest.delay, cfg.rest.distance }, { 8, 12 })
end)

test('AFK sleep: its minutes, and how it stands while running', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('AFK', { ['Sleep after##sk3_afk_minutes'] = 20, ['AFK sleep##sk3_on_afk'] = true })), 2)
    eq(cfg.afk, { on = false, minutes = 20 })
    local g = snap()
    g.afk_in = 125
    render(cfg, st, on('AFK'), model.build(g, cat, cfg, st, NAMES))
    eq(drew('Sleeps in 3 min without movement or combat.'), true)
    g.afk, g.afk_in = true, nil
    render(cfg, st, on('AFK'), model.build(g, cat, cfg, st, NAMES))
    eq(drew('Asleep: move to wake.'), true)
end)

test('a member switched off under Heal is skipped by healing', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['A##sk3_heal_A'] = true })), 1)
    eq(cfg.heal.skip, { A = true })
    eq(render(cfg, st, on('Heal', { ['A##sk3_heal_A'] = true })), 1)
    eq(cfg.heal.skip, {})
end)

test('UI / Log: the sliders size the HUD and SK Settings, Lock position keeps the HUD still', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log', { ['HP bar width##sk3_ui_hp_width'] = 300, ['Name font size##sk3_ui_name_size'] = 30,
        ['TP bar width##sk3_ui_tp_width'] = 250, ['TP bar height##sk3_ui_tp_height'] = 12,
        ['Background opacity##sk3_ui_opacity'] = 50, ['Size##sk3_ui_scale'] = 150 })), 6)
    eq({ cfg.ui.hp_width, cfg.ui.name_size, cfg.ui.tp_width, cfg.ui.tp_height, cfg.ui.opacity, cfg.ui.scale },
       { 300, 30, 250, 12, 50, 150 })
    local free = frame.flags.Sidekick3
    eq(render(cfg, st, on('UI / Log', { ['Lock position##sk3_ui_locked'] = true })), 1)
    eq(cfg.ui.locked, true)
    render(cfg, st)
    eq(frame.flags.Sidekick3 - free, ImGuiWindowFlags_NoMove)
    cfg.ui.scale = nil
    render(cfg, st)
end)

test('UI / Log lists the last actions sent, and has no action log switch', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log')), 0)
    eq({ button('Action log##sk3_log'), drew('Cure IV -> A'), drew('heal: A at 62%') }, { false, true, true })
    eq({ cfg, st.log }, { settings.defaults(), true })  -- the page writes nothing, and leaves the session log as it was
    render(cfg, status({ sent = {} }), on('UI / Log'))
    eq(drew('Nothing sent yet.'), true)
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
    local writes = render(cfg, st, on('Tracked', { ['Untrack##sk3_untrack_Out'] = true, ['Track Stranger##sk3_track'] = true }),
        model.build(g, cat, cfg, st, NAMES))
    eq({ tracking_calls, writes }, { { { 'remove', 'Out' }, { 'add', 'Stranger' } }, 0 })
    eq(fill('T1') ~= nil, true)
    eq(tipped('Out (tracked, WHM 75 / BLM 37)\nHP 80%  5.0y'), true)
    eq({ drew('T1 Out  WHM 75 / BLM 37'), drew('P1 A  (in your party)') }, { true, true })
    g.target = nil
    render(cfg, st, on('Tracked'), model.build(g, cat, cfg, st, NAMES))
    eq(drew('Target a player outside your alliance to track them, or /sk3 track Name.'), true)
end)

test('Heal the alliance writes heal.alliance; alliance chips write their slot; Tracked lists one in the alliance', function ()
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea', tracked = true } })
    local cfg, st = settings.defaults(), status()
    open_settings()
    eq(render(cfg, st, on('Heal', { ['Heal the alliance##sk3_heal_alliance'] = true })), 1)
    eq(cfg.heal.alliance, true)
    eq(render(cfg, st, on('Buff', { ['B0##buff_Haste6'] = true }), model.build(g, cat, cfg, st, NAMES)), 1)
    eq(cfg.rows.Haste.targets, { [0] = true, [6] = true })
    eq({ fill('Bea'), fill('B0 Bea') }, { nil, u32(P.white) })  -- no card in the HUD: a row
    render(cfg, st, on('Tracked'), model.build(g, cat, cfg, st, NAMES))
    eq(drew('B0 Bea  (in your alliance)'), true)
    eq(render(cfg, st, on('Heal', { ['Bea##sk3_heal_Bea'] = true }), model.build(g, cat, cfg, st, NAMES)), 1)  -- listed: heal.alliance is on
    eq(cfg.heal.skip, { Bea = true })
end)

local function profiles_named(cfg) return require('core.profiles').names(cfg) end

test('Profiles: Save names the profile loaded, a click loads one, Default goes back; the list names it', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.heal.danger = 40
    render(cfg, st, on('Profiles', { ['Save as##sk3_profile_save_as'] = true }))  -- the name typed is blank: nothing saved
    eq(next(cfg.profiles), nil)
    cfg.profiles.Dynamis = { heal = { danger = 20 } }
    local writes = render(cfg, st, on('Profiles', { ['##sk3_profile_1'] = true }))
    eq({ cfg.profile, cfg.heal.danger, cfg.parked.heal.danger, writes }, { 'Dynamis', 20, 40, 1 })
    render(cfg, st, on('Profiles'))
    eq({ drew('loaded: Dynamis'), button('Delete##sk3_profile_delete') }, { true, true })
    cfg.heal.danger = 25
    render(cfg, st, on('Profiles', { ['Save##sk3_profile_save'] = true }))  -- the name field holds the one loaded
    eq(cfg.profiles.Dynamis.heal.danger, 25)
    render(cfg, st, on('Profiles', { ['Default##sk3_profile_default'] = true }))
    eq({ cfg.profile, cfg.heal.danger }, { '', 40 })
    render(cfg, st, on('Profiles'))
    eq(button('Delete##sk3_profile_delete'), false)
    render(cfg, st, on('Profiles', { ['##sk3_profile_1'] = true }))
    render(cfg, st, on('Profiles', { ['New##sk3_profile_new'] = true }))  -- the name loaded is cleared with it
    render(cfg, st, on('Profiles', { ['Save##sk3_profile_save'] = true }))
    eq({ profiles_named(cfg), cfg.profile }, { { 'Dynamis' }, '' })
    eq(render(cfg, st, on('Profiles', { ['##sk3_profile_name'] = ' Sky ' })), 0)  -- typed, then saved under it trimmed
    render(cfg, st, on('Profiles', { ['Save##sk3_profile_save'] = true }))
    eq(profiles_named(cfg), { 'Dynamis', 'Sky' })
end)

test('Profiles: a name with ## is drawn whole, each row its own; a taken name says so', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.profiles['Sky##2'], cfg.profiles['a###x'], cfg.profiles['b###x'] = {}, {}, {}
    render(cfg, st, on('Profiles', { ['##sk3_profile_2'] = true }))  -- names in order: a###x, b###x, Sky##2
    eq(cfg.profile, 'b###x')
    render(cfg, st, on('Profiles', { ['##sk3_profile_3'] = true }))
    eq(cfg.profile, 'Sky##2')
    render(cfg, st, on('Profiles'))
    eq({ drew('Sky##2'), drew('a###x'), drew('loaded: Sky##2') }, { true, true, true })
    render(cfg, st, on('Profiles', { ['##sk3_profile_name'] = 'a###x' }))
    render(cfg, st, on('Profiles'))
    eq(drew('a###x exists: Save as replaces it.'), true)
    render(cfg, st, on('Profiles', { ['Default##sk3_profile_default'] = true }))
    render(cfg, st, on('Profiles'))  -- the name field empties with Default
    eq(drew('exists: Save as replaces it.'), false)
end)

test('SCH: a buff row\'s stratagem chips follow its targets and each toggles', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Celerity', 'Accession', 'Perpetuance' })
    local cfg, st = settings.defaults(), status()
    local function view() return model.build(snap(), sch, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Acc##buff_Protect_mod_Accession'] = true }), view()), 1)
    eq(cfg.rows.Protect, { on = false, mods = { Accession = true } })
    eq(button('Pen##buff_Protect_mod_Penury'), true)
    eq(render(cfg, st, on('Buff', { ['Acc##buff_Protect_mod_Accession'] = true }), view()), 1)
    eq(cfg.rows.Protect.mods, {})
    eq(render(cfg, st, on('Buff', { ['Hold##buff_Protect_hold'] = true }), view()), 1)
    eq({ cfg.rows.Protect.hold, tipped('No modifier is on here: it waits for nothing.') }, { true, true })
    render(cfg, st, on('Buff'))
    eq({ button('Pen##buff_Protect_mod_Penury'), button('Hold##buff_Protect_hold') }, { false, false })  -- WHM: no stratagems
end)

test('SCH: Keep a stratagem for healing, under Heal, only for a job with stratagems', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Accession' })
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['Keep a stratagem for healing##sk3_heal_reserve'] = true }), model.build(snap(), sch, cfg, st, NAMES)), 1)
    eq(cfg.heal.reserve, true)
    eq(render(cfg, st, on('Heal', { ['Keep a stratagem for healing##sk3_heal_reserve'] = true })), 0)  -- WHM: not drawn
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
    eq(render(cfg, st, on('Buff', { ['Corsair\'s Roll (EXP+)##sk3_roll_first_Corsair\'s Roll'] = true }), view()), 1)
    eq(render(cfg, st, on('Buff', { ['Ninja Roll (EVA+)##sk3_roll_second_Ninja Roll'] = true }), view()), 1)
    eq(render(cfg, st, on('Buff', { ['Highest##sk3_roll_risk_highest'] = true, ['Rolls##sk3_on_roll'] = true }), view()), 2)
    eq(cfg.roll, { on = false, first = 'Corsair\'s Roll', second = 'Ninja Roll', risk = 'highest' })
    eq({ drew('Last: Ninja Roll 4 (lucky)'), tipped('Lucky 5, unlucky 9.'), tipped('Highest: 11 or nothing.') }, { true, true, true })
    cfg.roll.second = cfg.roll.first
    render(cfg, st, on('Buff'), view())
    eq(drew('Roll 2 is Roll 1: one roll kept up'), true)
    cfg.roll.first = 'Bolter\'s Roll'
    render(cfg, st, on('Buff'), view())
    eq({ button('Roll 1##sk3_roll_first'), drew('Bolter\'s Roll (not available)') }, { true, true })
    eq(has(frame.args.Selectable, 'None##sk3_roll_first_none'), true)
    render(cfg, st, on('Buff'), view(13, 17, fake.catalog(13, 75, 17, 37, jas)))  -- NIN / COR
    eq({ drew('Roll 2: Corsair main job only'), button('Roll 2##sk3_roll_second') }, { true, false })
end)

test('BRD: Songs under Buff: Area and each slot that is filled or has a pick, a drop-down per song slot', function ()
    open_settings()
    local brd = fake.catalog(10, 75, 3, 37, { 'Pianissimo' })
    local cfg, st = settings.defaults(), status()
    local function view(main, sub, list)
        local g = snap(); g.main, g.sub = main or 10, sub or 3
        return model.build(g, list or brd, cfg, st, NAMES)
    end
    local minuet = 'Valor Minuet IV (+ATK)##sk3_song_area_1_Valor Minuet IV'
    eq(render(cfg, st, on('Buff', { [minuet] = true, ['Mage\'s Ballad II (+Refresh)##sk3_song_p1_2_Mage\'s Ballad II'] = true }), view()), 2)
    eq({ cfg.song.area_1, cfg.song.p1_2 }, { 'Valor Minuet IV', 'Mage\'s Ballad II' })
    render(cfg, st, on('Buff'), view())
    -- Area, ME, P1 and P2 (B, a trust in another zone); P3 is no one. Two slots on a Bard main job.
    eq({ button('##sk3_song_area_2'), button('##sk3_song_me_1'), button('##sk3_song_p1_1'), button('##sk3_song_p2_1'),
         button('##sk3_song_p3_1') }, { true, true, true, true, false })
    eq({ drew('Pianissimo: ready'), button('##sk3_song_me_2') }, { true, true })
    eq(render(cfg, st, on('Buff', { ['Song Duration##sk3_song_duration'] = 170 }), view()), 1)  -- BRD 75 main
    eq(cfg.song.duration, 170)
    eq(render(cfg, st, on('Buff', { ['Pianissimo fast casting##sk3_song_fast'] = true }), view()), 1)
    eq(cfg.song.fast, true)
    cfg.song.p4_1 = 'Herb Pastoral'
    render(cfg, st, on('Buff'), view())
    eq({ button('##sk3_song_p4_1'), drew('no one') }, { true, true })  -- a pick keeps its line
    eq(render(cfg, st, on('Buff', { ['None##sk3_song_area_1_none'] = true, ['Songs##sk3_on_song'] = true }), view()), 2)
    eq({ cfg.song.area_1, cfg.song.on }, { '', false })
    render(cfg, st, on('Buff'), view(3, 10, fake.catalog(3, 75, 10, 15, {})))  -- WHM / BRD 15: one slot, no Pianissimo
    eq({ button('##sk3_song_area_2'), drew('Songs on one member need Pianissimo (Bard 20)') }, { false, true })
    eq(button('Song Duration##sk3_song_duration'), false)  -- a subjob has no timers
    eq(button('Pianissimo fast casting##sk3_song_fast'), false)  -- nor fast casting, with no Pianissimo
    eq(render(cfg, st, on('Buff', { [minuet] = true })), 0)  -- WHM: no Songs
end)

test('GEO: Geomancy under Buff: its rows, how far and how long, and Entrust\'s member and spell', function ()
    open_settings()
    local geo = fake.catalog(21, 75, nil, 0, { 'Full Circle', 'Blaze of Glory', 'Entrust' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 21; return model.build(g, geo, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Recall past##sk3_geo_distance'] = 12, ['Keep after combat##sk3_geo_linger'] = 8 }), view()), 2)
    eq({ cfg.geo.distance, cfg.geo.linger }, { 12, 8 })
    eq(render(cfg, st, on('Buff', { ['A##sk3_geo_entrust_A'] = true, ['Indi-Fury##sk3_geo_entrust_spell_Indi-Fury'] = true }), view()), 2)
    eq({ cfg.geo.entrust, cfg.geo.entrust_spell }, { 'A', 'Indi-Fury' })
    eq(render(cfg, st, on('Buff', { ['P1##geo_geo1'] = true }), view()), 1)  -- the Geo row's target chips
    eq(cfg.rows.geo.targets, { [0] = true, [1] = true })
    eq(button('##pick_geo_geo'), true)  -- its luopan's spell
    eq(render(cfg, st, on('Buff', { ['Recall past##sk3_geo_distance'] = 12 })), 0)  -- WHM: no Geomancy
end)

test('RUN: Runes under Buff: a line per set, a rune per slot by what it does, each ward\'s switch', function ()
    open_settings()
    local run = fake.catalog(22, 75, 4, 37, { 'Ignis', 'Gelus', 'Vallation', 'Pflug' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 22; return model.build(g, run, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Fire##sk3_rune_idle_1_Ignis'] = true, ['Wind##sk3_rune_vallation_2_Gelus'] = true }), view()), 2)
    eq({ cfg.rune.idle_1, cfg.rune.vallation_2 }, { 'Ignis', 'Gelus' })
    eq(has(frame.args.Selectable, 'Silence / Weight##sk3_rune_pflug_3_Gelus'), true, 'Pflug shows the ailments')
    eq(tipped('Ignis: adds Fire, resists Ice, against Paralyze / Bind.'), true)
    render(cfg, st, on('Buff'), view())
    eq({ button('##sk3_rune_idle_1'), button('##sk3_rune_idle_3'), drew('Idle') }, { true, true, true })  -- three slots
    eq(render(cfg, st, on('Buff', { ['Pflug##sk3_rune_pflug'] = true, ['Runes##sk3_on_rune'] = true }), view()), 2)
    eq({ cfg.rows.Pflug.on, cfg.rune.on }, { false, false })
    cfg.rune.idle_2 = 'Lux'
    render(cfg, st, on('Buff'), view())
    eq({ button('##sk3_rune_idle_2'), tipped('Lux (not available)\nEach rune by the element') }, { true, true })  -- cut to fit, whole on hover
    local sub = fake.catalog(1, 75, 22, 37, { 'Ignis', 'Vallation' })
    local g = snap(); g.main, g.sub = 1, 22
    render(cfg, st, on('Buff'), model.build(g, sub, cfg, st, NAMES))  -- WAR / RUN 37: two slots
    eq({ button('##sk3_rune_idle_2'), button('##sk3_rune_idle_3') }, { true, false })
    eq(render(cfg, st, on('Buff', { ['Fire##sk3_rune_idle_1_Ignis'] = true })), 0)  -- WHM: no Runes
end)

test('PUP: Maneuvers under Pet: a drop-down per slot by element, then whether they can go', function ()
    open_settings()
    local pup = fake.catalog(18, 75, 3, 37, { 'Fire Maneuver', 'Light Maneuver' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 18; return model.build(g, pup, cfg, st, NAMES) end
    eq(render(cfg, st, on('Pet', { ['Fire##sk3_maneuver_1_Fire Maneuver'] = true, ['Light##sk3_maneuver_3_Light Maneuver'] = true }), view()), 2)
    eq({ cfg.maneuver.slot_1, cfg.maneuver.slot_2, cfg.maneuver.slot_3 }, { 'Fire Maneuver', '', 'Light Maneuver' })
    render(cfg, st, on('Pet'), view())
    eq({ button('##sk3_maneuver_2'), drew('ready') }, { true, true })
    eq(render(cfg, st, on('Pet', { ['None##sk3_maneuver_1_none'] = true, ['Maneuvers##sk3_on_maneuver'] = true }), view()), 2)
    eq({ cfg.maneuver.slot_1, cfg.maneuver.on }, { '', false })
    eq(render(cfg, st, on('Pet', { ['Fire##sk3_maneuver_1_Fire Maneuver'] = true })), 0)  -- WHM: no Maneuvers
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

test('another session\'s card has its run button and cog: run starts it there, the cog shows its settings', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status()
    remote_calls = {}
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ button('##sk3_run_A'), button('##sk3_cog_A') }, { true, true })
    eq({ tipped('Start A\'s automation'), tipped('Settings for A'), tipped('A\nHP 62%') }, { true, true, false })
    eq(button('##sk3_run_B'), false)  -- a trust: no session
    eq(render(cfg, st, { ['##sk3_run_A'] = true }, model.build(snap(), cat, cfg, st, NAMES)), 0)
    eq({ remote_calls, st.running }, { { { 'A', 'run', true } }, false })  -- sent there, not run here
    st.sessions.A.running = true
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq(tipped('Stop A\'s automation'), true)
    render(cfg, st, { ['##sk3_cog_A'] = true }, model.build(snap(), cat, cfg, st, NAMES))
    eq({ st.watching, settings_shown }, { { A = true }, false })
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ begun('SK Settings: A###sk3_settings_A'), drew('Waiting for A\'s session...') }, { true, true })
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
    eq(frame_with(on('Heal', { ['Danger under##sk3_danger'] = 60, ['Cure##heal_Cure'] = true })), 0)
    eq(frame_with(on('Buff', { ['Buffs##sk3_on_buff'] = true })), 0)
    eq(frame_with(on('Profiles', { ['Save as##sk3_profile_save_as'] = true })), 0)
    eq(remote_calls, { { 'A', 'set', 'heal.danger', 60 }, { 'A', 'row', 'Cure', false }, { 'A', 'section', 'buff', false },
        { 'A', 'save_profile', '', true } })  -- in the order clicked
    eq(mine, settings.defaults())
    frame_with(on('UI / Log'))
    eq({ drew('WHM 75 / BLM 37'), drew('Running'), drew('Nothing sent yet.') }, { true, true, true })  -- its own status and log
    eq({ button('Action log##sk3_log'), button('Japanese client##sk3_japanese'), button('HP bar width##sk3_ui_hp_width') },
       { false, false, false })  -- no action log switch; the HUD is its own
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
    render(cfg, st, on('Profiles', { ['Save##sk3_profile_save'] = true }), model.build(snap(), cat, cfg, st, NAMES))
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
    render(cfg, st, on('Tracked'), model.build(snap(), cat, cfg, st, NAMES))
    eq(drew('Target a player outside the alliance in A\'s game to track them there.'), true)
    st.watching = {}
end)

test('a view from a session running another version is not drawn: it says to reload it', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    local v = remote_view(cfg)
    v.version = model.VIEW + 1
    st.views = { A = v }
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ drew('A runs another version of Sidekick3: /addon reload sidekick3 there.'), button('##sk3_page_Heal') },
       { true, false })
    st.watching = {}
end)

test('chips and Heal members send the state they\'re set to, here and to another session', function ()
    open_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    st.views = { A = remote_view(settings.defaults()) }
    remote_calls = {}
    render(cfg, st, on('Buff', { ['P1##buff_Protect1'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    render(cfg, st, on('Heal', { ['A##sk3_heal_A'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    eq({ cfg.rows.Protect.targets, cfg.heal.skip }, { { [0] = true, [1] = true }, { A = true } })
    eq(remote_calls, { { 'A', 'target', 'Protect', 1, true }, { 'A', 'skip', 'A', true } })
    st.watching = {}
    close_settings()
end)

-- The fake measures 7 pixels a byte at 13 pixels: each cut below is the longest that fits.
test('the kit cuts text to fit with an ellipsis, never inside a character', function ()
    eq({ kit.fit('Kupipi', 42, 'font', 13), kit.fit('Kupipi', 41, 'font', 13) }, { 'Kupipi', 'Ku...' })
    eq({ kit.fit('a\195\169bc', 28, 'font', 13), kit.fit('\195\169a', 10, 'font', 13) }, { 'a...', '...' })
end)
