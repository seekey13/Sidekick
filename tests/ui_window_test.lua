-- ui/window.lua (and every other theme in ui/: Classic, and yours) against a fake imgui:
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
    BeginTooltip = 'EndTooltip', PushStyleColor = 'PopStyleColor', PushItemWidth = 'PopItemWidth',
}
local ALWAYS = { Begin = true, BeginChild = true, PushStyleColor = true, PushItemWidth = true }
local IDS = { Checkbox = true, Button = true, InvisibleButton = true, SliderInt = true, BeginCombo = true,
              CollapsingHeader = true, BeginTabItem = true }

local frame  -- { stack, vars, texts, ids, args, flags, columns, drawn, window, cursor, extent, clicks, edited }

-- The fonts Ashita added at its start, as 1.81's GetIO().Fonts.Fonts lists them; a test sets others. Its own has no kana.
local AGAVE = { FontSize = 18, Glyphs = { { Codepoint = 0x41 }, { Codepoint = 0xF0C0 } } }
local atlas = { AGAVE }

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
                 AddCircleFilled = { 1 }, AddCircle = { 1 }, AddTriangleFilled = { 1, 2, 3 }, AddTriangle = { 1, 2, 3 },
                 AddImage = { 2, 3, 4, 5 } }

-- A draw list records each call as { list, name, args }. Its text is drawn as is,
-- AddText(pos, col, s) or AddText(font, size, pos, col, s).
local function draw_list(list)
    return setmetatable({}, { __index = function (_, name)
        return function (_, ...)
            local args = { ... }
            for _, i in ipairs(POINTS[name] or {}) do point(args[i], name) end
            if name == 'AddText' then
                local at = type(args[2]) == 'number' and 3 or 1  -- (a font may be a table: Ashita's in the fake)
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
    TextUnformatted = function (s)  -- the kit's tooltips, the one drawn each frame
        assert(type(s) == 'string', 'text must be a string')
        frame.texts[#frame.texts + 1] = s
        frame.tips[#frame.tips + 1] = s
    end,
    -- The fake is ImGui 1.81 (no IMGUI_VERSION_NUM), whose PushFont takes the face alone.
    PushFont = function (font, px)
        assert(font ~= nil and px == nil, 'PushFont: the face alone on 1.81')
        table.insert(frame.stack, 'PopFont')
    end,
    PopFont = function () pop('PopFont') end,
    SetWindowFontScale = function (k)
        frame.font_scales = frame.font_scales or {}
        frame.font_scales[#frame.font_scales + 1] = k
    end,
    IsItemHovered = function () return true end,
    -- The pointer is over no box of a window (kit.over) unless a test sets clicks.over = true: then over every one.
    IsMouseHoveringRect = function () return frame.clicks.over == true end,
    -- The HUD's chrome reads this. A test sets clicks.hover = false for the faded frame.
    IsWindowHovered = function () return frame.hover ~= false end,
    SetNextWindowSize = function (size)
        point(size, 'SetNextWindowSize')
        frame.window_size = size
    end,
    SetNextWindowPos = function (p)
        point(p, 'SetNextWindowPos')
        frame.window_pos = p
    end,
    CalcTextSize = function (s) return #s * 7, 13 end,
    GetFontSize = function () return 13 end,
    GetFont = function () return 'font' end,
    GetIO = function () return { Fonts = { Fonts = atlas } } end,
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
        if frame.cursor and frame.at then frame.at[label] = { frame.cursor[1], frame.cursor[2], size[1], size[2] } end
        assert(size[1] > 0 and size[2] > 0, label .. ': ImGui asserts on a zero size')
        return frame.clicks[label] == true
    end,
    Selectable = function (label) return frame.clicks[label] == true end,
    -- A right-click is clicks.mouse1 = true: over whatever is hovered, which in the fake is everything.
    IsMouseClicked = function (b) return frame.clicks['mouse' .. b] == true end,
    -- Every popup is open, so its list draws, unless a test sets clicks[id] = false.
    IsPopupOpen = function (id) return frame.clicks[id] ~= false end,
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
-- The fake hovers everything, so every tooltip is asked for each frame and, as in game, only the last is drawn:
-- each one asked for is kept with the texts too (frame.asked), so a test can find any.
local tooltip = kit.tooltip
kit.tooltip = function (s)
    if s and s ~= '' then
        frame.texts[#frame.texts + 1] = tostring(s)
        frame.asked[#frame.asked + 1] = tostring(s)
    end
    tooltip(s)
end

local cat = fake.catalog(3, 75, 4, 37, { 'Divine Seal', 'Martyr' })
local NAMES = { job = function (id) return ({ [3] = 'WHM', [4] = 'BLM' })[id] end, statuses = fake.res.statuses }
local SENT = { at = 990, command = '/ma "Cure IV" 101', action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }

-- Sidekick Settings stays open between frames, as in game (status.settings): each status() starts from the last
-- frame's.
local settings_shown = false

-- The themes Sidekick.lua finds (core/themes.lua's shown): Standard drawing, Classic, and one that failed to load.
local BROKEN = 'ui/broken.lua:3: unexpected symbol'
local THEMES = { current = 'window', list = {
    { key = 'window', name = 'Standard', file = 'ui/window.lua', standard = true },
    { key = 'classic', name = 'Classic', file = 'ui/classic.lua' },
    { key = 'broken', name = 'broken', file = 'ui/broken.lua', error = BROKEN },
} }

local function status(t)
    local s = { running = false, open = true, log = true, intent = SENT, sent = { SENT }, settings = settings_shown,
                themes = THEMES }
    for k, v in pairs(t or {}) do s[k] = v end
    return s
end

local function snap()
    return fake.snap({
        { name = 'A', hpp = 62, buffs = { [40] = true, [41] = true } },
        { name = 'B', kind = 'trust', in_zone = false },
    }, { bt = { name = 'Crab', hpp = 50, dist = 4.3 }, pet = { name = 'Carbuncle', hpp = 100, dist = 2, uses_mp = true },
         combat = true })
end

-- A target you could track: a player outside your party and alliance, not tracked yet.
local STRANGER = { sid = 900, tidx = 1200, name = 'Stranger' }

local function has(list, x)
    for _, v in ipairs(list or {}) do if v == x then return true end end
    return false
end

-- The last frame began this window.
local function begun(label) return has(frame.args.Begin, label) end

-- What Track and Untrack asked of Sidekick, in order.
local tracking_calls = {}
local TRACKING = {
    add = function (name) tracking_calls[#tracking_calls + 1] = { 'add', name } end,
    remove = function (name) tracking_calls[#tracking_calls + 1] = { 'remove', name } end,
}

-- The themes act.theme picked, in order.
local theme_calls = {}
local function pick_theme(key) theme_calls[#theme_calls + 1] = key end

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
              drawn = {}, extent = {}, clicks = clicks or {}, asked = {}, tips = {}, at = {} }
    frame.hover = frame.clicks.hover ~= false
    local writes = 0
    local act = model.actions(cfg, st, function () writes = writes + 1 end, TRACKING, send, pick_theme)
    local ok, err = pcall(ui.render, view or model.build(snap(), cat, cfg, st, NAMES), act)
    eq(frame.stack, {}, 'every ImGui scope closed')
    eq(frame.vars, 0, 'every style var popped')
    settings_shown = st.settings == true
    return not ok and err or nil, writes
end

-- One frame of the standard window; returns the number of settings writes.
local function render(cfg, st, clicks, view)
    local err, writes = draw(window, cfg, st, clicks, view)
    eq(err, nil, 'no Lua error')
    return writes
end

-- `clicks` with Sidekick Settings' page `name` clicked too: the list of pages is drawn
-- first, so the page shows in that same frame.
local function on(name, clicks)
    clicks = clicks or {}
    clicks['##sk_page_' .. name] = true
    return clicks
end

-- Sidekick Settings, opened through the HUD's cog (or closed with its X) unless it already is.
local function open_settings()
    if not settings_shown then render(settings.defaults(), status(), { ['##sk_cog'] = true }) end
    assert(settings_shown and begun('Sidekick Settings'), 'Sidekick Settings open')
end

local function close_settings()
    if settings_shown then render(settings.defaults(), status(), { close = 'Sidekick Settings' }) end
    assert(not settings_shown, 'Sidekick Settings closed')
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

-- Where a widget's button was made this frame: { x, y, w, h }, and its middle's height.
local function box(id)
    local b = assert(frame.at[id], 'no button ' .. id)
    return b, b[2] + b[4] / 2
end

local u32 = kit.u32

-- The HUD ---------------------------------------------------------------------------

test('the HUD draws running and stopped; Sidekick Settings only once the cog opens it, until its X', function ()
    close_settings()
    for _, running in ipairs({ true, false }) do  -- stopped last, for its tooltip
        eq(render(settings.defaults(), status({ running = running })), 0)
        eq({ begun('Sidekick'), begun('Sidekick Settings') }, { true, false })
    end
    eq(tipped('WHM 75 / BLM 37\nStopped: would: Cure IV -> A (heal: A at 62%)\n[combat]\nTarget: Crab  50%  4.3y'), true)
    eq(render(settings.defaults(), status(), { ['##sk_cog'] = true }), 0)
    eq({ begun('Sidekick Settings'), drew('Follow past') }, { true, true })  -- its first page: Follow
    render(settings.defaults(), status({ running = true, intent = false, why = 'casting' }))
    eq({ begun('Sidekick Settings'), tipped('Running: Cure IV -> A (heal: A at 62%)\n(casting)') }, { true, true })
    eq(render(settings.defaults(), status(), { close = 'Sidekick Settings' }), 0)
    render(settings.defaults(), status())
    eq(begun('Sidekick Settings'), false)
    open_settings()
    render(settings.defaults(), status(), { ['##sk_settings_close'] = true })  -- its own X
    eq(begun('Sidekick Settings'), true)
    render(settings.defaults(), status())
    eq(begun('Sidekick Settings'), false)
    open_settings()
    render(settings.defaults(), status(), { ['##sk_cog'] = true })  -- the cog closes it too
    eq(begun('Sidekick Settings'), false)
end)

test('a card per member: name and tag drawn as is, its HP %, MP % and TP and the rest in its tooltip', function ()
    close_settings()
    render(settings.defaults(), status())
    for _, s in ipairs({ 'Sidekick', 'Me', 'A', 'B', 'ME', 'P1', 'P2' }) do eq(fill(s) ~= nil, true, s) end
    eq({ fill('62%'), fill('100%') }, { nil, nil })
    eq(tipped('A\nHP 62%  MP 100%  TP 0  5.0y\nProtect\nShell'), true)
    eq(tipped('B (trust, away)\nHP 100%  MP 100%'), true)
end)

local BAR_FILL = 0.7        -- ui/window.lua's fill, at 70%
local BAR_TRACK_A = 0.7     -- each bar's gray background; it does not fade with the panel
local BAR_OFF = '#0c0c0c'   -- the empty track while the pointer is off the panel, and the stroke
local BAR_EDGE_A = 0.7      -- that 1px stroke, at the same 70%

local UNKNOWN = '#8E929A'  -- an HP bar whose job isn't known, with Job colors on (the fixtures' members but yours)

-- The HP fill drawn from (x, y), red or (its job not known) grey: its rectangle's far corner. Its colour by job is
-- Job colors' test's.
local function hp_fill(x, y)
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[1][1] == x and d.args[1][2] == y
            and (d.args[3] == u32(P.hp, BAR_FILL) or d.args[3] == u32(UNKNOWN, BAR_FILL)) then
            return d.args[2]
        end
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
    cfg.ui.hp_width, cfg.ui.hp_glow = 300, false  -- A, at 62%, would glow yellow: the HP glow's own tests are below
    render(cfg, status())
    local panel = calls('AddRectFilled')[1].args
    eq({ panel[1], panel[2][1], panel[3] }, { { 100, 50 }, 100 + 2 * 8 + 300, u32(P.bg) })  -- hovered: solid
    -- Title 25, then cards 40 + 3 + 18 + 3 + 8 high (your pet's 18 + 3 + 18 + 3 + 18, 4 under yours) and 8 apart:
    -- A's, the third (under yours and your pet's), from y 219; 62% of 300.
    eq(hp_fill(108, 219), { 108 + 186, 219 + 40 })
    local rest, glow = false, false  -- the whole bar has a 70% gray background and a 1px near-black stroke, no bloom
    for _, d in ipairs(calls('AddRectFilled')) do
        rest = rest or (d.args[1][1] == 108 and d.args[1][2] == 219 and d.args[2][1] == 108 + 300
            and d.args[2][2] == 219 + 40 and d.args[3] == u32(P.track, BAR_TRACK_A))
    end
    for _, d in ipairs(calls('AddRect')) do
        local x, y = d.args[1][1], d.args[1][2]
        glow = glow or (x >= 105 and x < 108 and y >= 216 and y < 219)
    end
    eq({ rest, glow, bar_edge(108, 219, 300, 40) }, { true, false, true })
    cfg.ui.tp_width = 400  -- the widest bar sets the panel's width
    render(cfg, status())
    eq(calls('AddRectFilled')[1].args[2][1], 100 + 2 * 8 + 400)
    cfg.ui.hp_width, cfg.ui.mp_width, cfg.ui.tp_width, cfg.ui.text_size = 80, 80, 80, 48  -- big text on short bars: the title row still fits
    render(cfg, status())
    eq(calls('AddRectFilled')[1].args[2][1], 100 + math.ceil(8 + #'Sidekick' * 7 * 48 / 13 + 8 + 60 + 8))
end)

test('the panel, frame, title and close fade out until the mouse is over the window; the bars stay', function ()
    close_settings()
    local cfg = settings.defaults()
    render(cfg, status(), { hover = false })
    eq(calls('AddRectFilled')[1].args[3], u32(P.bg, 0))
    eq(calls('AddRect')[1].args[3], u32(P.border, 0))
    eq(fill('Sidekick'), u32(P.white, 0))
    local rose, back = false, false  -- the panel around the bars is gone; each bar's background is near-black at 70%
    for _, d in ipairs(calls('AddLine')) do rose = rose or d.args[3] == u32(P.rose, 0) end
    for _, d in ipairs(calls('AddRectFilled')) do
        back = back or (d.args[1][1] == 108 and d.args[1][2] == 75 and d.args[2][1] == 108 + 220
            and d.args[2][2] == 75 + 40 and d.args[3] == u32(BAR_OFF, BAR_TRACK_A))
    end
    eq({ rose, hp_fill(108, 75) ~= nil, back, bar_edge(108, 75, 220, 40) }, { true, true, true, true })
    render(cfg, status())  -- over it again: solid
    eq({ calls('AddRectFilled')[1].args[3], fill('Sidekick') }, { u32(P.bg), u32(P.white) })
end)

test('the HUD\'s items reach exactly the panel\'s far corner, so its auto-size fits the panel', function ()
    close_settings()
    render(settings.defaults(), status())
    eq(frame.extent.Sidekick, calls('AddRectFilled')[1].args[2])
    eq(frame.extent.Sidekick, { 100 + 236, 50 + 25 + 3 * 72 + 60 + 4 + 2 * 8 + 8 })  -- yours, your pet's 4 under it, A's, B's
end)

test('sizes out of their sliders\' range, set by hand or by a custom UI, are held to it', function ()
    close_settings()  -- its sliders would show the values as they are
    local cfg = settings.defaults()
    cfg.ui.text_size, cfg.ui.hp_width = 0, 5000  -- a zero text size would make zero-size buttons
    render(cfg, status())
    eq(calls('AddRectFilled')[1].args[2][1], 100 + 2 * 8 + 600)
end)

test('a row\'s MP bar sizes out of range, or not numbers, are held to their sliders\' too', function ()
    close_settings()
    local cfg = settings.defaults()
    cfg.ui.ally_mp_width, cfg.ui.ally_mp_height, cfg.ui.ally_mp_offset = 5000, 0, 'abc'
    render(cfg, status(), nil, model.build(fake.snap({ { kind = 'alliance', name = 'Bea' } }), cat, cfg, status(), NAMES))
    eq(bar_edge(108, 155 + 18 + 1, 600, 2), true)  -- 600 wide, 2 high, set in by none
end)

test('a name turns yellow at 75% HP, orange at 50% and red at 25%; away greys it and the slot, low MP doesn\'t', function ()
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
        { u32(P.orange), u32(P.white), u32(P.orange), u32(P.red) })  -- Org's MP under the Recover line: still white
    eq({ fill('Gone'), fill('P5'), fill('T2') }, { u32(P.dim), u32(P.dim), u32(P.white) })  -- a row's slot as a card's
end)

-- Job colours and the HP glow ------------------------------------------------------------

-- The colours of the fills (AddRectFilled) drawn from (x, y): a bar's background, then its fill.
local function painted(x, y)
    local out = {}
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[1][1] == x and d.args[1][2] == y then out[#out + 1] = d.args[3] end
    end
    return out
end

-- A two-colour fill's pieces on the pixel row at y, left to right: { left, right, colour }, the blend's with each end's.
local function pieces(y)
    local out = {}
    for _, d in ipairs(frame.drawn) do
        local a, b = d.args[1], d.args[2]
        if d.name == 'AddRectFilled' and a[2] == y and b[2] == y + 1 then
            out[#out + 1] = { a[1], b[1], d.args[3] }
        elseif d.name == 'AddRectFilledMultiColor' and a[2] == y and b[2] == y + 1 then
            out[#out + 1] = { a[1], b[1], d.args[3], d.args[4] }
        end
    end
    table.sort(out, function (p, q) return p[1] < q[1] end)
    return out
end

local WAR, NIN, DRG, BLU = '#C69B6D', '#7A5C7A', '#33937F', '#0070DD'

test('Job colors: each HP bar its main job\'s colour, a pet\'s its owner\'s; one with none known grey; the switch off, '
    .. 'red', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    cfg.ui.sub_colors = false
    local g = fake.snap({ { name = 'A', jobs = { 1, 75, 13, 37 } }, { name = 'B' },
                          { kind = 'alliance', uses_mp = false, name = 'Bea', jobs = { 16, 75, 0, 0 } },
                          { kind = 'alliance', uses_mp = false, name = 'Anon', jobs = { 0, 0, 0, 0 } } },
        { pet = { name = 'Wyvern', hpp = 100, mpp = 0, tp = 0, dist = 2, uses_mp = false } })
    g.units[1].jobs = { 14, 75, 0, 0 }  -- you: DRG, your wyvern under you
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Your card from y 75, your wyvern's 4 under it from 151 (39 high: no MP bar), A's from 198, B's from 278,
    -- Bea's row from 358, Anon's (/anon) 21 under it.
    local grey = u32(UNKNOWN, BAR_FILL)
    eq({ has(painted(108, 75), u32(DRG, BAR_FILL)), has(painted(108, 151), u32(DRG, BAR_FILL)),
         has(painted(108, 198), u32(WAR, BAR_FILL)), has(painted(108, 278), grey), has(painted(108, 358), u32(BLU, BAR_FILL)),
         has(painted(108, 379), grey) },
       { true, true, true, true, true, true })
    cfg.ui.sub_colors = true  -- A's subjob blends in; your wyvern stays your main job's colour, whole
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ #pieces(198) > 0, #pieces(151), has(painted(108, 151), u32(DRG, BAR_FILL)) }, { true, 0, true })
    cfg.ui.job_colors = false  -- every one the HUD's red, known or not
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    local red = u32(P.hp, BAR_FILL)
    eq({ has(painted(108, 75), red), has(painted(108, 151), red), has(painted(108, 198), red), has(painted(108, 278), red),
         has(painted(108, 358), red), has(painted(108, 379), red) },
       { true, true, true, true, true, true })
end)

test('Subjob color: main then sub by Split and Blend, a pixel row at a time, set in to the corners', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    local main, sub = u32(WAR, BAR_FILL), u32(NIN, BAR_FILL)
    local g = fake.snap({})
    g.units[1].jobs = { 1, 75, 13, 37 }  -- you: WAR/NIN, your HP bar 220 by 40 from (108, 75)
    local function draw_with(split, blend, hpp)
        cfg.ui.split, cfg.ui.blend = split, blend
        g.units[1].hpp = hpp or 100
        render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    end
    local ins = 4 - math.sqrt(16 - 3.5 * 3.5)  -- the top row, set in to the corners' arcs
    -- Diagonal, a hard edge: the top row main to the top-right corner, a 45° line down from it: the bottom row main to
    -- 180 across, sub from 181, the pixel between blended.
    draw_with('diagonal', 0)
    eq(pieces(75), { { 108 + ins, 108 + 220 - ins, main } })
    local bottom = pieces(75 + 39)
    eq({ #bottom, bottom[1][2], bottom[1][3], bottom[3][1], bottom[3][3] }, { 3, 108 + 180, main, 108 + 181, sub })
    -- At 50%, the default, it fades half a bar's height each way of that line.
    draw_with('diagonal', 50)
    eq(pieces(75), { { 108 + ins, 108 + 199.5, main },
                     { 108 + 199.5, 108 + 220 - ins, main, u32(kit.mix(WAR, NIN, (220 - ins - 199.5) / 40), BAR_FILL) } })
    -- Horizontal, a hard edge: main over sub, the line across the middle; at 100% a fade from the top row to the bottom.
    draw_with('horizontal', 0)
    eq({ pieces(75 + 19)[1][3], pieces(75 + 20)[1][3] }, { main, sub })
    draw_with('horizontal', 100)
    eq({ pieces(75)[1][3], pieces(75 + 39)[1][3] },
       { u32(kit.mix(WAR, NIN, 0.5 / 40), BAR_FILL), u32(kit.mix(WAR, NIN, 39.5 / 40), BAR_FILL) })
    -- Vertical, a hard edge, at 50% HP: main then sub down the fill's middle; a part-filled bar's right end square.
    draw_with('vertical', 0, 50)
    local mid, top = pieces(75 + 20), pieces(75)
    eq({ mid[1][1], mid[1][2], mid[1][3], mid[3][1], mid[3][2], mid[3][3] }, { 108, 108 + 54.5, main, 108 + 55.5, 108 + 110, sub })
    eq({ top[1][1], top[#top][2] }, { 108 + ins, 108 + 110 })
    -- A split or a blend it doesn't take draws as the defaults: Diagonal, 50%.
    draw_with('sideways', 'lots')
    eq(pieces(75)[1], { 108 + ins, 108 + 199.5, main })
    cfg.ui.sub_colors = false  -- one colour, rounded as before
    draw_with('diagonal', 50)
    eq({ #pieces(75), has(painted(108, 75), main) }, { 0, true })
end)

-- The HP glow's rings round a bar w by h at (x, y), outermost first: each one's colour.
local function rings(x, y, w, h)
    local out = {}
    for e = 4, 0, -1 do
        for _, d in ipairs(calls('AddRect')) do
            local a, b = d.args[1], d.args[2]
            if a[1] == x - e and a[2] == y - e and b[1] == x + w + e and b[2] == y + h + e
                and d.args[3] ~= u32(BAR_OFF, BAR_EDGE_A) then
                out[#out + 1] = d.args[3]
            end
        end
    end
    return out
end

-- TargetBar's lock-on rings in `color` at `strength`, outermost first.
local function ring_colors(color, strength)
    local out = {}
    for _, a in ipairs({ 0.14, 0.22, 0.34, 0.50, 0.72 }) do out[#out + 1] = u32(color, a * strength) end
    return out
end

test('HP glow: TargetBar\'s fringe round the HP bar as the name changes colour; none dead or away; nothing grows', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    local g = fake.snap({
        { name = 'High', hpp = 76 }, { name = 'Yel', hpp = 75 }, { name = 'Org', hpp = 50 }, { name = 'Red', hpp = 25 },
        { name = 'Dead', hpp = 20, alive = false },
        { kind = 'alliance', uses_mp = false, name = 'Low', hpp = 10 },
        { kind = 'alliance', uses_mp = false, name = 'Gone', hpp = 10, in_zone = false },
    })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- The cards 80 apart from y 75 (yours, then High's from 155), their HP bars 220 by 40; then the rows, 220 by 18, 3
    -- apart, from 555.
    eq({ rings(108, 155, 220, 40), rings(108, 235, 220, 40), rings(108, 315, 220, 40), rings(108, 395, 220, 40),
         rings(108, 475, 220, 40) },
       { {}, ring_colors(P.yellow, 0.333), ring_colors(P.orange, 0.666), ring_colors('#FF4A40', 1), {} })
    eq({ rings(108, 555, 220, 18), rings(108, 576, 220, 18) }, { ring_colors('#FF4A40', 1), {} })
    -- Out past the bar, into the padding and the gaps: the panel and the bars stay as they were.
    local extent, panel = frame.extent.Sidekick, calls('AddRectFilled')[1].args[2]
    eq({ bar_edge(108, 235, 220, 40), bar_edge(108, 555, 220, 18) }, { true, true })
    cfg.ui.hp_glow = false
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ rings(108, 235, 220, 40), rings(108, 555, 220, 18), frame.extent.Sidekick, calls('AddRectFilled')[1].args[2] },
       { {}, {}, extent, panel })
    eq({ bar_edge(108, 235, 220, 40), bar_edge(108, 555, 220, 18) }, { true, true })
    cfg.ui.hp_glow = true  -- your pet's too, but none at 0%
    local p = fake.snap({}, { pet = { name = 'Ifrit', hpp = 20, mpp = 40, tp = 0, dist = 3, uses_mp = true } })
    render(cfg, st, nil, model.build(p, cat, cfg, st, NAMES))
    -- Its card 4 under yours, from y 151: its outermost ring from 147, where your TP bar (139 to 147) ends.
    eq(rings(108, 151, 220, 18), ring_colors('#FF4A40', 1))
    p.pet.hpp = 0
    render(cfg, st, nil, model.build(p, cat, cfg, st, NAMES))
    eq(rings(108, 151, 220, 18), {})
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
    local g = fake.snap({ { name = 'A' } }, { pet = { name = 'Ifrit', hpp = 50, mpp = 40, tp = 1000, dist = 3, uses_mp = true } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Its three bars an alliance row's size, 220 by 18, 3 apart, 4 under your card, from y 151; A's card 8 under
    -- them.
    eq({ hp_fill(108, 75), hp_fill(108, 151), hp_fill(108, 219) }, { { 328, 115 }, { 108 + 110, 169 }, { 328, 259 } })
    eq({ bar_edge(108, 151, 220, 18), bar_edge(108, 172, 220, 18) }, { true, true })
    eq({ fill('Ifrit'), fill('PET') }, { u32(P.orange), u32(P.white) })  -- 50% HP: the name is orange
    eq(tp_fills(), { { { 108, 193 }, { 179, 211 }, u32(P.tp, BAR_FILL) } })  -- 1000 TP: one part, full
    eq(tipped('Ifrit (pet)\nHP 50%  MP 40%  TP 1000  3.0y'), true)
    g.pet.hpp = 76
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ fill('Ifrit'), fill('Me') }, { u32('#C2FFFF'), u32(P.white) })  -- healthy: pale cyan, where yours is white
    g.pet = nil
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ fill('PET'), hp_fill(108, 155) }, { nil, { 328, 195 } })  -- no pet: A's card under yours
end)

-- Where `s` was last drawn: its fill's top left.
local function at(s)
    local p
    for _, d in ipairs(calls('AddText')) do
        if d.args[5] == s then p = d.args[3] end
    end
    return p
end

-- Tag `s`'s top, centred on a bar `top` down and `h` high.
local function tag_top(s, top, h)
    local _, th = kit.measure(s, kit.fonts.semi, 14)
    return math.floor(top + (h - th) / 2 + 0.5)
end

test('a member with no MP (0/0) has no MP bar, its TP bar up under its HP bar; each tag is on its TP bar', function ()
    close_settings()
    local cfg, st = settings.defaults(), status()
    local g = fake.snap({ { name = 'War', mpp = 0, uses_mp = false, tp = 1500 }, { kind = 'tracked', name = 'Out' } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Yours from y 75, its TP bar from 139; War's from 155, its TP bar from 198, 3 under its HP bar; Out's row from 214.
    eq({ at('ME'), at('P1') }, { { 114, tag_top('ME', 139, 8) }, { 114, tag_top('P1', 198, 8) } })
    eq({ bar_edge(108, 198, 220, 18) or false, bar_edge(108, 198, 71, 8) }, { false, true })
    eq(tp_fills()[1], { { 108, 198 }, { 179, 206 }, u32(P.tp, BAR_FILL) })
    eq(bar_edge(108, 214, 220, 18), true)  -- a tracked player's: a row, its HP alone
    eq(frame.extent.Sidekick, { 100 + 236, 50 + 25 + 72 + 51 + 18 + 2 * 8 + 8 })
    eq(tipped('War\nHP 100%  TP 1500  5.0y'), true)
    cfg.ui.hide_mp = false  -- HUD settings' switch off: every card keeps its MP bar
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ bar_edge(108, 198, 220, 18), at('P1') }, { true, { 114, tag_top('P1', 219, 8) } })
    eq(frame.extent.Sidekick, { 100 + 236, 50 + 25 + 2 * 72 + 18 + 2 * 8 + 8 })
end)

test('a pet with no MP, as a wyvern, has no MP bar; another session\'s once its file says so', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    local g = fake.snap({ { name = 'A' } },
        { pet = { name = 'Wyvern', hpp = 100, mpp = 0, tp = 1000, dist = 2, uses_mp = false } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Its HP bar 4 under your card, from y 151, its TP bar 3 under it with the tag on it; A's card 8 under that.
    eq({ hp_fill(108, 151), bar_edge(108, 172, 220, 18) or false, at('PET') }, { { 328, 169 }, false, { 114, tag_top('PET', 172, 18) } })
    eq({ tp_fills()[1], hp_fill(108, 198) }, { { { 108, 172 }, { 179, 190 }, u32(P.tp, BAR_FILL) }, { 328, 238 } })
    eq(tipped('Wyvern (pet)\nHP 100%  TP 1000  2.0y'), true)
    g.pet = nil
    st.sessions = { A = { running = false, members = { { sid = 101, name = 'A' } } } }
    g.units[2].pet = { sid = 0x1000701, tidx = 0x701, name = 'Wyvern', hpp = 100, dist = 6 }
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(bar_edge(108, 252, 220, 18), true)  -- A's (its card from 155, its pet's from 231), its file not naming it yet: unknown, so it stays
    st.sessions.A.pet = { sid = 0x1000701, name = 'Wyvern', mpp = 0, tp = 0, uses_mp = false }
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ bar_edge(108, 252, 220, 18) or false, frame.extent.Sidekick }, { false, { 100 + 236, 50 + 25 + 2 * 72 + 39 + 8 + 4 + 8 } })
end)

test('the arrow points at your pet\'s card for its care and sending it in', function ()
    close_settings()
    local cfg = settings.defaults()
    for _, b in ipairs({ 'pet', 'pet_send', 'heal' }) do
        local st = status({ intent = { at = 990, action = 'Healing Ruby', behavior = b, why = 'Carbuncle at 40%' } })
        render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
        local arrow = calls('AddTriangleFilled', 'background')
        eq({ #arrow, arrow[1].args[1][2] }, { 1, b == 'heal' and 75 + 36 or 151 + 30 }, b)  -- yours for a heal of no one
    end
end)

test('the alliance gets a thin HP row each under the cards, a gap before each party; the arrow points at one', function ()
    close_settings()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', uses_mp = false, name = 'Bea', hpp = 20 },
        { kind = 'alliance', uses_mp = false, name = 'Bo', slot = 7, hpp = 75 }, { kind = 'alliance', uses_mp = false, name = 'Cy', slot = 12, in_zone = false } })
    local st = status({ intent = { at = 990, action = 'Cure IV', target = 'Bo', behavior = 'heal', why = 'Bo' } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    local cards = 25 + 2 * 72 + 8               -- title, two cards and the gap between them
    local b, c = cards + 8, cards + 8 + 18 + 3 + 18 + 8  -- each party's first bar top: after a gap
    eq(frame.extent.Sidekick, { 100 + 236, 50 + c + 18 + 8 })  -- the panel still fits its items exactly
    eq(calls('AddRectFilled')[1].args[2][2], 50 + c + 18 + 8)
    -- The name coloured by its HP, the slot white (grey away), the name after it on the same line.
    eq({ fill('Bea'), fill('Bo'), fill('Cy'), fill('20%') }, { u32(P.red), u32(P.yellow), u32(P.dim), nil })
    eq({ fill('B0'), fill('B1'), fill('C0') }, { u32(P.white), u32(P.white), u32(P.dim) })
    local after = math.floor(114 + kit.measure('B0 ', kit.fonts.semi, 14) + 0.5)
    eq({ at('B0'), at('Bea') }, { { 114, tag_top('B0', 50 + b, 18) }, { after, tag_top('Bea', 50 + b, 18) } })
    eq(tipped('Bea (alliance)\nHP 20%  TP 0  5.0y'), true)  -- no MP: not yet seen with it
    local arrow = calls('AddTriangleFilled', 'background')
    eq({ #arrow, arrow[1].args[1] }, { 1, { 100 + 236 + 2, 50 + b + 18 + 3 + 9 } })  -- its point: Bo's row, its middle
    eq(fill('Heal:Cure IV', 'background') ~= nil, true)
end)

test('a tracked player gets a row as the alliance\'s, after theirs: HP alone; another session\'s has run and the cog', function ()
    close_settings()
    local cfg = settings.defaults()
    local st = status({ intent = { at = 990, action = 'Cure IV', target = 'Far', behavior = 'heal', why = 'Far' }, sent = {} })
    st.sessions = { Out = { running = false, members = { { sid = 202, name = 'Out' } } } }
    local g = fake.snap({ { kind = 'tracked', name = 'Far', hpp = 40 }, { kind = 'tracked', name = 'Out' },
        { kind = 'alliance', uses_mp = false, name = 'Bea' } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Your card from y 75; Bea's row a gap under it, from 155; the tracked ones a gap under that, 3 apart: 181 and 202.
    eq({ bar_edge(108, 155, 220, 18), bar_edge(108, 181, 220, 18), bar_edge(108, 202, 220, 18) }, { true, true, true })
    eq(frame.extent.Sidekick, { 100 + 236, 202 + 18 + 8 })  -- no MP or TP bar under them
    eq({ fill('Far'), fill('T1'), fill('T2'), tipped('Far (tracked)\nHP 40%  5.0y') },
       { u32(P.orange), u32(P.white), u32(P.white), true })
    eq({ button('##sk_run_Far'), (box('##sk_run_Out')), (box('##sk_cog_Out')) },
       { false, { 108 + 220 - 6 - 34, 202, 17, 17 }, { 108 + 220 - 2 - 17, 202, 17, 17 } })
    eq(calls('AddTriangleFilled', 'background')[1].args[1], { 100 + 236 + 2, 181 + 9 })  -- the arrow at Far's row
end)

test('a tracked player a session file gives MP for has a thin MP strip under their row; the rows under come down', function ()
    close_settings()
    local cfg = settings.defaults()
    local g = fake.snap({ { kind = 'tracked', name = 'Far', hpp = 40 }, { kind = 'tracked', name = 'Out' },
        { kind = 'alliance', uses_mp = false, name = 'Bea' } })
    g.units[2].mpp, g.units[2].mp, g.units[2].uses_mp = 60, 600, true
    render(cfg, status(), nil, model.build(g, cat, cfg, status(), NAMES))
    -- Far's row at 181, its strip 1 under (18 / 3 = 6 high); Out's row 3 under that, with none.
    eq({ bar_edge(108, 181, 220, 18), bar_edge(108, 181 + 18 + 1, 220, 6), bar_edge(108, 209, 220, 18),
         bar_edge(108, 209 + 18 + 1, 220, 6) }, { true, true, true, nil })
    eq(frame.extent.Sidekick, { 100 + 236, 209 + 18 + 8 })
end)

test('an alliance member with MP has an MP bar under their row, sized and set in by its own settings', function ()
    close_settings()
    local cfg = settings.defaults()
    local g = fake.snap({ { kind = 'alliance', name = 'Bea', mpp = 50 }, { kind = 'alliance', name = 'Bo', uses_mp = false } })
    render(cfg, status(), nil, model.build(g, cat, cfg, status(), NAMES))
    -- Bea's row from 155 (after your card), her MP bar 1 under it, 220 by 6; Bo's row 3 under that, with none.
    local bo = 155 + 18 + 1 + 6 + 3
    eq({ bar_edge(108, 155, 220, 18), bar_edge(108, 155 + 18 + 1, 220, 6), bar_edge(108, bo, 220, 18),
         bar_edge(108, bo + 18 + 1, 220, 6) }, { true, true, true, nil })
    local mp_fill
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[1][1] == 108 and d.args[1][2] == 155 + 18 + 1 and d.args[3] == u32(P.mp, BAR_FILL) then mp_fill = d.args[2] end
    end
    eq(mp_fill, { 108 + 110, 155 + 18 + 1 + 6 })  -- half full
    cfg.ui.ally_mp_width, cfg.ui.ally_mp_height, cfg.ui.ally_mp_offset = 300, 10, 40
    render(cfg, status(), nil, model.build(g, cat, cfg, status(), NAMES))
    bo = 155 + 18 + 1 + 10 + 3
    eq({ bar_edge(148, 155 + 18 + 1, 300, 10), bar_edge(108, bo, 220, 18) }, { true, true })
    eq(frame.extent.Sidekick, { 100 + 8 + 40 + 300 + 8, bo + 18 + 8 })  -- the panel reaches past the wider bar
end)

test('a tracked player\'s tooltip gives their MP while a session file does', function ()
    close_settings()
    local cfg = settings.defaults()
    local g = fake.snap({ { kind = 'tracked', name = 'Far', hpp = 40 } })
    g.units[2].mpp, g.units[2].mp, g.units[2].uses_mp = 60, 600, true
    render(cfg, status(), nil, model.build(g, cat, cfg, status(), NAMES))
    eq(tipped('Far (tracked)\nHP 40%  MP 60%  5.0y'), true)
end)

test('the MP and TP bars sit their offsets in from the HP bar\'s left, the slot on the TP bar; the panel fits them', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    cfg.ui.mp_offset, cfg.ui.tp_offset = 20, 40
    render(cfg, st, nil, model.build(fake.snap({}), cat, cfg, st, NAMES))
    -- Your card from y 75: HP from x 108, MP from 128 at y 118, TP from 148 at y 139, ME on it.
    eq({ bar_edge(108, 75, 220, 40), bar_edge(128, 118, 220, 18), bar_edge(148, 139, 71, 8) }, { true, true, true })
    eq(at('ME'), { 154, tag_top('ME', 139, 8) })
    eq(frame.extent.Sidekick, { 100 + 2 * 8 + 40 + 220, 75 + 72 + 8 })
end)

test('Show player slot off leaves the slot off every card, row and pet\'s card; each name stays where it was', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea' }, { kind = 'tracked', name = 'Far' } },
        { pet = { name = 'Ifrit', hpp = 100, mpp = 40, tp = 0, dist = 3, uses_mp = true } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    local names = { at('Me'), at('A'), at('Ifrit'), at('Far')[2] }
    cfg.ui.show_slot = false
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ fill('ME'), fill('P1'), fill('PET'), fill('B0'), fill('T1') }, { nil, nil, nil, nil, nil })
    eq({ at('Me'), at('A'), at('Ifrit'), at('Far')[2] }, names)
    eq({ at('Bea')[1], at('Far')[1] }, { 114, 114 })  -- a row's name at its start
end)

test('Alliance / Tracked\'s sizes size the rows and their text, a pet\'s text too, not its bars; the MP bar\'s no longer', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    cfg.ui.ally_hp_width, cfg.ui.ally_hp_height, cfg.ui.ally_text_size, cfg.ui.mp_height = 150, 10, 11, 30
    local g = fake.snap({ { kind = 'alliance', uses_mp = false, name = 'Bea', hpp = 50 } },
        { pet = { name = 'Ifrit', hpp = 50, mpp = 40, tp = 1000, dist = 3, uses_mp = true } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Your card 40 + 3 + 30 + 3 + 8 from y 75; your pet's bars 220 by 18, 3 apart, 4 under it from 163; Bea's row
    -- from 231.
    eq({ bar_edge(108, 163, 220, 18), bar_edge(108, 184, 220, 18), bar_edge(108, 231, 150, 10) }, { true, true, true })
    eq(hp_fill(108, 231), { 108 + 75, 241 })
    local _, h = kit.measure('Bea', kit.fonts.semi, 11)
    eq({ at('B0'), at('Bea')[2], at('Ifrit')[2] },
       { { 114, math.floor(231 + (10 - h) / 2 + 0.5) }, math.floor(231 + (10 - h) / 2 + 0.5), math.floor(163 + (18 - h) / 2 + 0.5) })
    eq(frame.extent.Sidekick, { 100 + 236, 231 + 10 + 8 })
end)

test('Pet\'s settings size each of a pet\'s bars and set each its offset in from the cards\' left; the panel fits them', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    local ui = cfg.ui
    ui.pet_hp_width, ui.pet_hp_height, ui.pet_hp_offset = 250, 12, 20
    ui.pet_mp_width, ui.pet_mp_height, ui.pet_mp_offset = 150, 6, 30
    ui.pet_tp_width, ui.pet_tp_height, ui.pet_tp_offset = 120, 5, 40
    local g = fake.snap({}, { pet = { name = 'Ifrit', hpp = 100, mpp = 40, tp = 1000, dist = 3, uses_mp = true } })
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Your pet's card 4 under yours, from y 151: HP from x 128, MP from 138 at y 166, TP from 148 at y 175 (its
    -- first part 38 wide).
    eq({ bar_edge(128, 151, 250, 12), bar_edge(138, 166, 150, 6), bar_edge(148, 175, 38, 5) }, { true, true, true })
    eq({ bar_edge(108, 75, 220, 40), bar_edge(108, 118, 220, 18) }, { true, true })  -- your card as it was
    eq({ at('Ifrit')[1], at('PET') }, { 134, { 154, tag_top('PET', 175, 5) } })
    eq(frame.extent.Sidekick, { 100 + 2 * 8 + 20 + 250, 151 + 12 + 3 + 6 + 3 + 5 + 8 })
end)

test('the panel is as wide as a pet\'s or a row\'s bars only while one is drawn', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    cfg.ui.pet_hp_offset, cfg.ui.ally_hp_width = 100, 300
    local pet = { name = 'Ifrit', hpp = 100, mpp = 40, tp = 1000, dist = 3, uses_mp = true }
    local function width(members, opts)
        render(cfg, st, nil, model.build(fake.snap(members, opts), cat, cfg, st, NAMES))
        return frame.extent.Sidekick[1] - 100
    end
    eq({ width({}), width({}, { pet = pet }), width({ { kind = 'alliance', name = 'Bea' } }),
         width({ { kind = 'tracked', name = 'Far' } }) }, { 236, 2 * 8 + 100 + 220, 2 * 8 + 300, 2 * 8 + 300 })
end)

test('the arrow\'s label points at the card the next action is for: amber running, grey stopped, none idle', function ()
    close_settings()
    render(settings.defaults(), status())
    local arrow = calls('AddTriangleFilled', 'background')[1].args
    eq({ arrow[1], arrow[4] }, { { 100 + 236 + 2, 50 + 25 + 72 + 4 + 68 + 36 }, u32(P.seg) })  -- A's card, under your pet's: its middle
    eq(fill('Heal:Cure IV', 'background'), u32(P.text2))
    render(settings.defaults(), status({ running = true }))
    eq(calls('AddTriangleFilled', 'background')[1].args[4], u32(P.amber))
    eq(fill('Heal:Cure IV', 'background'), u32(P.ink))
    render(settings.defaults(), status({ intent = false }))
    eq(#calls('AddTriangleFilled', 'background'), 0)
end)

-- The pills drawn in `color` on the background list (or `list`): each one's AddRectFilled arguments.
local function pills(color, list)
    local out = {}
    for _, d in ipairs(calls('AddRectFilled', list or 'background')) do
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

-- The Add Tracked pill's fill, lit (the fake hovers everything): its AddRectFilled arguments, the first in that colour
-- (its plus is cut out in it too, after).
local function add_pill()
    local body = u32(kit.mix(P.accent_bg, P.accent_lo, 0.6))
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[3] == body then return d.args end
    end
end

test('targeting a player you could track, Add Tracked points at your card first, in a window just its size: a click '
    .. 'anywhere on it tracks them', function ()
    close_settings()
    local cfg = settings.defaults()
    local st = status({ intent = { at = 990, action = 'Cure IV', target = 'Me', behavior = 'heal', why = 'Me at 50%' } })
    local g = snap()
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ begun('Sidekick Add Tracked'), drew('Add Tracked'), add_pill() }, { false, false, nil })
    g.target = STRANGER
    tracking_calls = {}
    eq(render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES)), 0)
    eq({ begun('Sidekick Add Tracked'), tracking_calls }, { true, {} })
    local pill = add_pill()
    local x, y, w, h = pill[1][1], pill[1][2], pill[2][1] - pill[1][1], pill[2][2] - pill[1][2]
    eq({ x, y, h }, { 100 + 236 + 2 + 9, 75 + 36 - 11, 22 })  -- at your card's middle, an action label's size at text 14
    eq({ frame.window_pos, frame.window_size, frame.extent['Sidekick Add Tracked'] }, { { x, y }, { w, h }, { x + w, y + h } })
    -- The HUD's window, kept where it's put, out of imgui.ini and taking no focus as it comes.
    eq(frame.flags['Sidekick Add Tracked'] - frame.flags.Sidekick,
       ImGuiWindowFlags_NoMove + ImGuiWindowFlags_NoSavedSettings + ImGuiWindowFlags_NoFocusOnAppearing)
    eq({ fill('Add Tracked'), tipped('Track Stranger\nHeal, clear, raise and buff them too') }, { u32(P.white), true })
    local plus = calls('AddCircleFilled')
    eq({ plus[#plus].args[3], plus[#plus].args[1][1] < x + w, plus[#plus].args[1][2] }, { u32(P.white), true, y + h / 2 })
    -- The point is its; the action at your card comes after it, in line.
    local tri = calls('AddTriangleFilled', 'background')
    eq({ #tri, tri[1].args[1], tri[1].args[4] }, { 1, { 100 + 236 + 2, 75 + 36 }, u32(P.accent_lo) })
    local grey = pills(P.seg)
    eq({ #grey, grey[1][1] }, { 1, { x + w + 6, y } })
    eq(render(cfg, st, { ['##sk_add_tracked_Stranger'] = true }, model.build(g, cat, cfg, st, NAMES)), 0)
    eq(tracking_calls, { { 'add', 'Stranger' } })
    -- Down once clicked, till a snapshot shows them tracked: a second click before it would /check them again.
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ begun('Sidekick Add Tracked'), add_pill(), #pills(P.seg), pills(P.seg)[1][1] }, { false, nil, 1, { x, y } })
    g.target = nil  -- tracked (or no one targeted); untracked and targeted again, it's back
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    g.target = STRANGER
    st.intent = false
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ #calls('AddTriangleFilled', 'background'), add_pill()[1] }, { 1, { x, y } })  -- alone at your card, where it was
    cfg.ui.text_size = 11  -- labels 17 high at your card's middle, y 105: their top half a pixel off a whole one
    st.intent = { at = 990, action = 'Cure IV', target = 'Me', behavior = 'heal', why = 'Me at 50%' }
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    tri, grey = calls('AddTriangleFilled', 'background'), pills(P.seg)
    -- Its window's top as ImGui floors it, and the action after it on that pixel too, the point at their middle.
    eq({ frame.window_pos[2], add_pill()[1][2], frame.window_size[2], grey[1][1][2], tri[1].args[1][2] },
       { 96, 96, 17, 96, 96 + 17 / 2 })
    g.target = nil  -- no one to track now: no pill, nor its window
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ begun('Sidekick Add Tracked'), add_pill(), drew('Add Tracked'), #pills(P.seg) }, { false, nil, false, 1 })
end)

test('another session\'s pet has a card under that session\'s: its MP and TP once its file names it; its care points there', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    st.sessions = { A = { running = false, members = { { sid = 101, name = 'A' } } } }
    local g = fake.snap({ { name = 'A' } })
    g.units[2].pet = { sid = 0x1000701, tidx = 0x701, name = 'Garuda', hpp = 50, dist = 6 }
    local function mp_fill(y)
        for _, d in ipairs(calls('AddRectFilled')) do
            if d.args[1][1] == 108 and d.args[1][2] == y and d.args[3] == u32(P.mp, BAR_FILL) then return d.args[2] end
        end
    end
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Yours from y 75, A's from 155 and its pet's three bars 4 under it from 231, each 220 by 18, 3 apart.
    eq({ hp_fill(108, 155), hp_fill(108, 231), fill('Garuda'), fill('PET') },
       { { 328, 195 }, { 108 + 110, 249 }, u32(P.orange), u32(P.white) })
    eq({ mp_fill(252), tp_fills(), tipped('Garuda (pet)\nHP 50%  6.0y') }, { nil, {}, true })  -- not known yet: empty
    eq(frame.extent.Sidekick, { 100 + 236, 50 + 25 + 2 * 72 + 60 + 8 + 4 + 8 })  -- yours, A's and its pet's
    st.sessions.A.pet = { sid = 0x1000701, name = 'Garuda', mpp = 40, tp = 1000, uses_mp = true }
    st.sessions.A.act = { behavior = 'pet', action = 'Healing Ruby' }
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ mp_fill(252), tp_fills(), tipped('Garuda (pet)\nHP 50%  MP 40%  TP 1000  6.0y') },
       { { 108 + 88, 270 }, { { { 108, 273 }, { 179, 291 }, u32(P.tp, BAR_FILL) } }, true })
    local theirs = pills(P.accent)
    eq({ #theirs, (theirs[1][1][2] + theirs[1][2][2]) / 2 }, { 1, 231 + 30 })  -- the pet card's middle
    eq(calls('AddTriangleFilled', 'background')[1].args[1][2], 231 + 30)
end)

test('your pet\'s care points at your pet\'s card alone, not at another session\'s pet', function ()
    close_settings()
    local cfg = settings.defaults()
    local st = status({ intent = { at = 990, action = 'Healing Ruby', behavior = 'pet', why = 'Carbuncle at 40%' } })
    st.sessions = { A = { running = false, members = { { sid = 101, name = 'A' } } } }
    local g = snap()
    g.units[2].pet = { sid = 0x1000701, tidx = 0x701, name = 'Garuda', hpp = 50, dist = 6 }
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    -- Yours from y 75, your pet's from 151, A's from 219 and its pet's from 295: one arrow, at your pet's middle.
    local arrow = calls('AddTriangleFilled', 'background')
    eq({ #arrow, arrow[1].args[1][2] }, { 1, 151 + 30 })
end)

test('two sessions\' pets of one name keep their own bars', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    st.sessions = { A = { running = false, members = { { sid = 101, name = 'A' } } },
                    B = { running = false, members = { { sid = 102, name = 'B' } } } }
    local g = fake.snap({ { name = 'A' }, { name = 'B' } })
    g.units[2].pet = { sid = 0x1000701, tidx = 0x701, name = 'Fenrir', hpp = 30, dist = 6 }
    g.units[3].pet = { sid = 0x1000702, tidx = 0x702, name = 'Fenrir', hpp = 90, dist = 6 }
    local step = kit.clock
    kit.clock = function () return tick end  -- time stands: a fill the two shared would show the first's at both
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    kit.clock = step
    -- A's pet's HP bar from y 231, B's card from 299 and its pet's HP bar from 375, each 220 wide.
    eq({ hp_fill(108, 231), hp_fill(108, 375) }, { { 108 + 66, 249 }, { 108 + 198, 393 } })
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

test('run and the cog sit at the bottom right of your own HP bar, the title row keeps close; lit while on', function ()
    close_settings()
    render(settings.defaults(), status())
    -- Text 14: buttons 17px. Your card's HP bar runs x 108-328 from y 75 to 115: they end 2 above its bottom. Close is an
    -- X in the title row, no disc.
    local c = discs()
    eq(close_x(), { 100 + 236 - 8 - 8.5, 50 + 12.5 })
    eq({ c[1][1], c[1][2], c[2][1], c[2][2] }, { 328 - 2 - 17 - 4 - 17 + 8.5, 115 - 2 - 8.5, 328 - 2 - 17 + 8.5, 115 - 2 - 8.5 })
    eq(#frame.args.InvisibleButton, 3)
    -- The fake hovers everything: run unlit is the accent's low shade, lit its light one; the cog lit while Sidekick Settings shows.
    eq({ c[1][3], c[2][3] }, { u32(P.accent_lo), u32(P.accent_lo) })
    render(settings.defaults(), status({ running = true }))
    eq(discs()[1][3], u32(P.accent2))
    open_settings()
    render(settings.defaults(), status())
    eq(discs()[2][3], u32(P.accent2))
    eq(close_x() ~= nil, true)  -- Sidekick Settings' X, rose under the pointer, and no disc of its own
    close_settings()
end)

test('the buttons are the icon size whatever the bar\'s height: on a thinner bar they spill past it, centred on it', function ()
    close_settings()
    local cfg = settings.defaults()
    cfg.ui.icon_size = 24
    render(cfg, status())
    eq(discs()[1][2], 75 + 40 - 2 - 12)  -- 24px, 2px up from the 40px bar's bottom
    cfg.ui.hp_height = 12
    render(cfg, status())
    -- Centred on your 12px bar, 6 over it above and below: your card comes down 6 so they clear the title row.
    eq({ hp_fill(108, 81) ~= nil, discs()[1][2] }, { true, 81 + 6 })
    eq(hp_fill(108, 81 + 12 + 3 + 18 + 3 + 8 + 4) ~= nil, true)  -- your pet's card 4 under yours
    cfg.ui.hp_height, cfg.ui.hp_width, cfg.ui.icon_size = 120, 80, 64  -- big icons on a narrow bar: both still fit across it
    render(cfg, status())
    local c = discs()
    eq({ c[1][1] - 18, c[2][1] + 18 }, { 108 + 80 - 2 - 36 - 4 - 36, 108 + 80 - 2 })  -- 36px buttons, from the bar's left to its right
end)

test('the panel reaches past buttons spilling under the last line, so its auto-size fits them', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    st.sessions = { A = { running = false, members = { { sid = 301, name = 'A' } } } }  -- A's session, in the alliance
    cfg.ui.ally_hp_height, cfg.ui.icon_size = 4, 40
    render(cfg, st, nil, model.build(fake.snap({ { name = 'P' }, { kind = 'alliance', name = 'A' } }), cat, cfg, st, NAMES))
    -- Yours and P's cards, then A's row 4 high from y 25 + 72 + 8 + 72 + 8: 40px buttons from 18 over it to 18 under.
    local top = 50 + 25 + 72 + 8 + 72 + 8
    eq({ box('##sk_run_A')[2], box('##sk_run_A')[4] }, { top - 18, 40 })
    eq(frame.extent.Sidekick, { 100 + 236, top - 18 + 40 + 8 })
    eq(calls('AddRectFilled')[1].args[2][2], top - 18 + 40 + 8)
end)

test('two sessions\' rows one after another: the second comes down for its buttons to clear the first\'s', function ()
    close_settings()
    local cfg, st = settings.defaults(), status({ intent = false, sent = {} })
    st.sessions = { A = { running = false, members = { { sid = 301, name = 'A' } } },
                    B = { running = false, members = { { sid = 302, name = 'B' } } } }
    cfg.ui.ally_hp_height, cfg.ui.icon_size = 10, 24
    local function hud()
        render(cfg, st, nil, model.build(fake.snap({ { name = 'P' }, { kind = 'alliance', uses_mp = false, name = 'A' },
            { kind = 'alliance', uses_mp = false, name = 'B' }, { kind = 'alliance', uses_mp = false, name = 'C' } }), cat, cfg, st, NAMES))
    end
    hud()
    -- 24px buttons on a 10px row, 7 over it above and below. A's row from y 50 + 25 + 72 + 8 + 72 + 8, its buttons from
    -- 7 over it; B's comes down from 3 under A's (not 13 to its buttons' 4 over A's) to 3 under A's buttons.
    local a = 50 + 25 + 72 + 8 + 72 + 8
    eq({ box('##sk_run_A')[2], box('##sk_run_B')[2], box('##sk_cog_B')[2] }, { a - 7, a - 7 + 24 + 3, a - 7 + 24 + 3 })
    -- B's buttons spill onto C's row, 3 under B's 10px bar: there they keep their tooltip (the fake hovers everything).
    eq({ tipped('Start B\'s automation'), tipped('C (alliance') }, { true, false })
    cfg.ui.icon_size = 8  -- buttons inside the bar: C's row has its own tooltip
    hud()
    eq(tipped('C (alliance'), true)
end)

test('a button\'s tooltip replaces the card\'s', function ()
    close_settings()
    render(settings.defaults(), status())  -- the fake hovers everything: the buttons win
    eq({ tipped('Start automation'), tipped('Settings'), tipped('Me\nHP') }, { true, true, false })
    eq(tipped('A\nHP 62%'), true)
end)

-- Buff icons ------------------------------------------------------------------------

local icons = require('core.icons')
local util = require('core.util')

-- The HUD drawn from `g` (a fake snapshot) with each status icon a texture, 5000 + its id (offline there are none), and
-- the icons drawn: { id, top-left, bottom-right } each, in the order drawn.
local function buff_hud(cfg, g, clicks)
    local st = status({ intent = false, sent = {} })
    local real = icons.status
    icons.status = function (id) return 5000 + id end
    local ok, err = pcall(render, cfg, st, clicks, model.build(g, cat, cfg, st, NAMES))
    icons.status = real
    assert(ok, err)
    local out = {}
    for _, d in ipairs(calls('AddImage')) do out[#out + 1] = { d.args[1] - 5000, d.args[2], d.args[3] } end
    return out
end

-- Where `s` was last drawn: its own text, after its halo.
local function text_at(s)
    local pos
    for _, d in ipairs(calls('AddText')) do if d.args[5] == s then pos = d.args[3] end end
    return pos
end

test('buff icons straddle each party card\'s HP bar top from its left, in order; none on a pet\'s card or a row', function ()
    close_settings()
    local g = fake.snap({ { name = 'A', icons = { { id = 40 }, { id = 41 } } },
                          { name = 'B', kind = 'trust', buffs = { [43] = true, [33] = true } },
                          { kind = 'alliance', name = 'C', buffs = { [44] = true } },
                          { kind = 'tracked', name = 'T', buffs = { [45] = true } } },
                        { pet = { name = 'Carbuncle', hpp = 100, dist = 2, uses_mp = true, buffs = { [46] = true } } })
    g.units[1].icons = { { id = 34 }, { id = 33 } }
    -- 16px, 2 apart, their middles on the HP bar's top edge (x 108): yours from y 75; your pet's card 4 under yours
    -- (60 high), A's 8 under it, B's 8 under A's (each card 72 high). B's by id: a trust's statuses come in no order.
    local a, b = 75 + 72 + 4 + 60 + 8, 75 + 72 + 4 + 60 + 8 + 72 + 8
    eq(buff_hud(settings.defaults(), g), {
        { 34, { 108, 67 }, { 124, 83 } }, { 33, { 126, 67 }, { 142, 83 } },
        { 40, { 108, a - 8 }, { 124, a + 8 } }, { 41, { 126, a - 8 }, { 142, a + 8 } },
        { 33, { 108, b - 8 }, { 124, b + 8 } }, { 43, { 126, b - 8 }, { 142, b + 8 } } })
    eq({ hp_fill(108, a) ~= nil, hp_fill(108, b) ~= nil }, { true, true })  -- A's and B's HP bars, where they're said to be
    local cfg = settings.defaults()
    cfg.ui.buff_icons = false
    eq(buff_hud(cfg, g), {})
end)

test('buff icons: Buff icon height moves them up past the bar or down into it, never past the window', function ()
    close_settings()
    local cfg, g = settings.defaults(), fake.snap({})
    g.units[1].icons = { { id = 40 } }
    cfg.ui.buff_offset = 10
    eq(buff_hud(cfg, g)[1][2], { 108, 75 - 10 - 8 })
    cfg.ui.buff_offset = -10
    eq(buff_hud(cfg, g)[1][2], { 108, 75 + 10 - 8 })
    cfg.ui.buff_size, cfg.ui.buff_offset = 30, 40  -- 55 over the bar's top: your card comes down from the title row's 25
    eq({ buff_hud(cfg, g)[1][2], hp_fill(108, 50 + 55) ~= nil }, { { 108, 50 }, true })
    cfg.ui.buff_size, cfg.ui.buff_offset = 64, -64  -- 96 under its top, past your card's 72: the panel reaches past them
    eq(buff_hud(cfg, g)[1][3], { 172, 75 + 96 })
    eq({ frame.extent.Sidekick, calls('AddRectFilled')[1].args[2][2] }, { { 336, 75 + 96 + 8 }, 75 + 96 + 8 })
    cfg.ui.buff_offset = nil  -- none set: 0, not the slider's least (-64 would put them 32 into your bar, from y 107)
    eq({ buff_hud(cfg, g)[1][2], hp_fill(108, 50 + 32) ~= nil }, { { 108, 50 }, true })
end)

test('buff icons: your own show the time left, its largest unit alone; no one else\'s has one', function ()
    close_settings()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A', icons = { { id = 40, left = 100 } } } })
    g.units[1].icons = { { id = 33, left = 3 * 3600 + 59 * 60 }, { id = 34, left = 25 * 60 + 59 }, { id = 35, left = 47 },
                         { id = 36, left = 0 }, { id = 37 } }
    eq(#buff_hud(cfg, g), 6)
    eq({ drew('3h'), drew('25m'), drew('47s'), drew('0s'), drew('1m') }, { true, true, true, true, false })
    -- 10px over the bottom of the third icon (x 144 to 160, y 67 to 83), across its middle.
    local w, h = kit.measure('47s', kit.fonts.semi, 10)
    eq(text_at('47s'), { util.round(144 + (16 - w) / 2), util.round(83 - h) })
    cfg.ui.buff_timer_size = 14
    buff_hud(cfg, g)
    h = select(2, kit.measure('47s', kit.fonts.semi, 14))
    eq(text_at('47s')[2], util.round(83 - h))
    cfg.ui.buff_timers = false
    eq(#buff_hud(cfg, g), 6)
    eq({ drew('3h'), drew('47s') }, { false, false })
end)

test('buff icons: those past the bar\'s end are counted in its last place, their names in its tooltip', function ()
    close_settings()
    local cfg, g = settings.defaults(), fake.snap({})
    g.units[1].icons = {}
    for id = 40, 59 do g.units[1].icons[#g.units[1].icons + 1] = { id = id } end
    -- 220 across holds 12 of 16 (and 2 between): 11 icons, then +9.
    local drawn = buff_hud(cfg, g, { over = true })
    eq({ #drawn, drawn[11][1], drawn[11][2], drew('+9') }, { 11, 50, { 108 + 10 * 18, 67 }, true })
    local names = {}
    for id = 51, 59 do names[#names + 1] = fake.res.statuses[id] and fake.res.statuses[id].en or tostring(id) end
    eq(frame.tips[#frame.tips], table.concat(names, '\n'))
end)

test('buff icons: one under the pointer has its name, and on yours its time, in place of the card\'s tooltip', function ()
    close_settings()
    local g = fake.snap({})
    g.units[1].icons = { { id = 40, left = 1500 } }
    buff_hud(settings.defaults(), g, { over = true })
    eq({ tipped('Protect  25m'), tipped('Me\nHP') }, { true, false })
end)

test('buff icons: a dark square in place of an icon the client can\'t give', function ()
    close_settings()
    local g, st, cfg = fake.snap({}), status({ intent = false, sent = {} }), settings.defaults()
    g.units[1].icons = { { id = 40 } }
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))  -- offline: no textures
    eq(#calls('AddImage'), 0)
    local square = false
    for _, d in ipairs(calls('AddRectFilled')) do
        if d.args[1][1] == 108 and d.args[1][2] == 67 and d.args[2][1] == 124 and d.args[2][2] == 83
            and d.args[3] == u32(P.well, 0.85) then square = true end
    end
    eq(square, true)
end)

-- A row's help covers its label's half, where a ward's switch, a rune or a Risk segment can sit with a tooltip of its
-- own: two in one frame show one, never both stacked.
test('only the last tooltip asked for in a frame is drawn, as SetTooltip shows one', function ()
    close_settings()
    render(settings.defaults(), status())
    eq({ #frame.asked > 1, frame.tips }, { true, { frame.asked[#frame.asked] } })
    kit.tooltip('Left over')  -- asked for after a UI's last kit.tooltips: the next kit.frame draws it
    render(settings.defaults(), status())
    eq({ frame.tips[1], #frame.tips }, { 'Left over', 2 })
end)

test('the run button starts and stops automation, for this session only', function ()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, { ['##sk_run'] = true }), 0)
    eq(st.running, true)
    eq(render(cfg, st, { ['##sk_run'] = true }), 0)
    eq(st.running, false)
    eq(cfg, settings.defaults())
end)

test('the close button closes the HUD and remembers it; Sidekick Settings stay, /sk\'s alone', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.ui.open = true
    eq(render(cfg, st, { ['##sk_close'] = true }), 1)
    eq({ st.open, cfg.ui.open, st.settings, begun('Sidekick Settings') }, { false, false, true, true })
    render(cfg, st)
    eq({ begun('Sidekick'), begun('Sidekick Settings') }, { false, true })
    close_settings()
end)

test('hidden, only the windows are begun and ended', function ()
    open_settings()
    eq(render(settings.defaults(), status(), { Begin = false }), 0)
    eq({ #frame.texts, #frame.drawn, begun('Sidekick Settings') }, { 0, 0, true })
end)

test('a Lua error while drawing still ends both windows, then is raised', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    local view = model.build(snap(), cat, cfg, st, NAMES)
    view.sections = nil  -- in Sidekick Settings
    eq(type(draw(window, cfg, st, nil, view)), 'string')
    view = model.build(snap(), cat, cfg, st, NAMES)
    view.recent = nil  -- in Sidekick Settings' UI / Log page, inside its scrolling child
    eq(type(draw(window, cfg, st, on('UI / Log'), view)), 'string')
    view = model.build(snap(), cat, cfg, st, NAMES)
    view.party = nil  -- in the HUD
    eq(type(draw(window, cfg, st, nil, view)), 'string')
end)

-- The widget ------------------------------------------------------------------------

-- A's a session too, for the widget's tests and the remote control's.
local function remote_status(t)
    local st = status(t)
    st.sessions = { A = { running = false, members = { { sid = 101, name = 'A' } } } }
    st.watching = st.watching or {}
    return st
end

local function widget_cfg()
    local cfg = settings.defaults()
    cfg.ui.widget = true
    return cfg
end

test('the widget is off at first; on, it is one row: your name, run and cog, what it does in the name\'s tooltip', function ()
    close_settings()
    render(settings.defaults(), status())
    eq(begun('SK Widget'), false)
    local cfg = widget_cfg()
    render(cfg, status({ open = false }))  -- the HUD closed, so the tooltip is the widget's
    eq({ begun('SK Widget'), drew('Me'), button('##sk_widget_run'), button('##sk_widget_cog'), tipped('Start automation') },
       { true, true, true, true, true })
    eq({ drew('WHM 75 / BLM 37'), drew('Stopped'), drew('Default'), button('##sk_widget_settings') }, { false, false, false, false })
    eq({ tipped('Stopped: would: Cure IV -> A (heal: A at 62%)'), tipped('Right-click to load a profile') }, { true, true })
    eq(frame.flags['SK Widget'] - ImGuiWindowFlags_NoTitleBar - ImGuiWindowFlags_NoResize - ImGuiWindowFlags_AlwaysAutoResize
        - ImGuiWindowFlags_NoScrollbar - ImGuiWindowFlags_NoScrollWithMouse - ImGuiWindowFlags_NoBackground, 0)
    eq(frame.extent['SK Widget'], calls('AddRectFilled')[1].args[2])  -- its items reach its panel's far corner
    render(cfg, status({ open = false, running = true, intent = false, why = 'casting' }))
    eq({ tipped('(casting)'), tipped('Stop automation') }, { true, true })
end)

test('the widget\'s height is its size setting, held to its range', function ()
    close_settings()
    local cfg = widget_cfg()
    local function height()
        render(cfg, status({ open = false }))
        local r = calls('AddRectFilled')[1].args
        return r[2][2] - r[1][2]
    end
    local base = height()
    cfg.ui.widget_size = 32
    eq(height() > base, true)
    local big = height()
    cfg.ui.widget_size = 500
    eq(height(), 48 + 7 * 2 + 14 * 2)  -- its pill's margin round the buttons, the panel's round the pill
    cfg.ui.widget_size = 'what'
    eq(height(), base)
    eq(big, 32 + 5 * 2 + 10 * 2)
end)

test('each character\'s pill is red while stopped and green while running', function ()
    close_settings()
    local cfg, st = widget_cfg(), remote_status({ open = false })
    local function pill_colours()
        render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
        local out = {}
        for _, d in ipairs(calls('AddRectFilled')) do  -- yours, then A's; not the panel nor a stop glyph
            local c = d.args[3]
            if c == u32(kit.P.go) or c == u32(kit.P.halt) then out[#out + 1] = c end
        end
        return out
    end
    eq(pill_colours(), { u32(kit.P.halt), u32(kit.P.halt) })
    st.running = true
    eq(pill_colours(), { u32(kit.P.go), u32(kit.P.halt) })
    st.sessions.A.running = true
    eq(pill_colours(), { u32(kit.P.go), u32(kit.P.go) })
end)

test('a pill is blue while something holds automation, yours and another session\'s; its tooltip says what', function ()
    close_settings()
    local cfg, st = widget_cfg(), remote_status({ open = false, running = true })
    st.sessions.A.running, st.sessions.A.halted = true, 'mounted'
    local function blue()
        local n = 0
        for _, d in ipairs(calls('AddRectFilled')) do
            if d.args[3] == u32(kit.P.held) then n = n + 1 end
        end
        return n
    end
    local g = snap()
    g.afk = true
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ blue(), tipped('A: Halted (mounted)') }, { 2, true })
    g.afk, g.mounted = nil, true
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(blue(), 2)
    g.mounted, g.casting, g.moving = nil, true, true  -- a moment's hold only: still green
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(blue(), 1)
    st.sessions.A.running = false  -- stopped: red, whatever its file says
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ blue(), tipped('A: Stopped') }, { 0, true })
end)

test('the widget shows every session on this PC from its file, in your party or not', function ()
    close_settings()
    local cfg, st = widget_cfg(), remote_status({ open = false })
    st.sessions.Zed = { running = true, members = { { sid = 950, name = 'Zed' } } }  -- not in any list here
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ button('##sk_widget_A_run'), button('##sk_widget_Zed_run'), tipped('Zed: Running') }, { true, true, true })
    local g = snap()
    g.units = { g.units[1] }  -- your party's lines not read yet: A stays
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq(button('##sk_widget_A_run'), true)
end)

test('the widget\'s run button runs this session only; its cog opens and closes Sidekick Settings', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    remote_calls = {}
    eq(render(cfg, st, { ['##sk_widget_run'] = true }), 0)
    eq({ st.running, remote_calls }, { true, {} })
    eq(render(cfg, st, { ['##sk_widget_run'] = true }), 0)
    eq(st.running, false)
    render(cfg, st, { ['##sk_widget_cog'] = true })
    render(cfg, st)
    eq(begun('Sidekick Settings'), true)
    render(cfg, st, { ['##sk_widget_cog'] = true })
    render(cfg, st)
    eq(begun('Sidekick Settings'), false)
end)

test('right-clicking a name lists its profiles: a click loads one, Default goes back', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    cfg.heal.danger = 40
    cfg.profiles['Sky##1'] = { heal = { danger = 20 } }
    render(cfg, st)
    eq(has(frame.args.OpenPopup, '##sk_widget_profiles'), false)
    render(cfg, st, { mouse1 = true })
    eq(has(frame.args.OpenPopup, '##sk_widget_profiles'), true)
    eq(render(cfg, st, { ['##sk_widget_profiles_1'] = true }), 1)
    eq({ cfg.profile, cfg.heal.danger }, { 'Sky##1', 20 })
    render(cfg, st)
    eq({ tipped('Sky##1'), tipped('(profile Sky##1)') }, { true, true })  -- whole, in its list and the name's tooltip
    render(cfg, st, { ['Default##sk_widget_profiles_default'] = true })
    eq({ cfg.profile, cfg.heal.danger }, { '', 40 })
end)

test('the widget names each other session after you: its run, its cog and its profiles reach it', function ()
    close_settings()
    local cfg, st = widget_cfg(), remote_status({ open = false })
    st.sessions.A.profiles = { active = 'Melee', names = { 'Melee', 'Mage' } }
    local function view() return model.build(snap(), cat, cfg, st, NAMES) end
    remote_calls = {}
    render(cfg, st, nil, view())
    eq({ drew('Me'), drew('A'), button('##sk_widget_A_run'), button('##sk_widget_A_cog'), button('##sk_widget_B_run') },
       { true, true, true, true, false })  -- B's a trust: no session
    eq({ tipped('A: Stopped\nProfile: Melee'), tipped('Start A\'s automation') }, { true, true })
    eq(render(cfg, st, { ['##sk_widget_A_run'] = true }, view()), 0)
    eq({ remote_calls, st.running }, { { { 'A', 'run', true } }, false })  -- sent there, not run here
    remote_calls = {}
    render(cfg, st, { ['##sk_widget_A_profiles_2'] = true }, view())
    render(cfg, st, { ['Default##sk_widget_A_profiles_default'] = true }, view())
    eq(remote_calls, { { 'A', 'profile', 'Mage' }, { 'A', 'profile', nil } })
    render(cfg, st, { ['##sk_widget_A_cog'] = true }, view())
    eq(st.watching, { A = true })
    render(cfg, st, nil, view())  -- the HUD closed, its Sidekick Settings show from the widget
    eq(begun('Sidekick Settings: A###sk_settings_A'), true)
    render(cfg, st, { ['##sk_widget_A_cog'] = true }, view())
    eq(st.watching, {})
end)

test('a session whose profiles never came has no profile menu, nor says Default', function ()
    close_settings()
    local cfg, st = widget_cfg(), remote_status({ open = false })
    render(cfg, st, { mouse1 = true }, model.build(snap(), cat, cfg, st, NAMES))
    eq({ has(frame.args.OpenPopup, '##sk_widget_A_profiles'), has(frame.args.OpenPopup, '##sk_widget_profiles') },
       { false, true })
    eq({ tipped('A: Stopped'), tipped('A: Stopped\nProfile') }, { true, false })
end)

test('UI / Log turns the widget on and off; Lock position keeps it still too', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log', { ['Show the widget##sk_ui_widget'] = true })), 1)
    eq(cfg.ui.widget, true)
    render(cfg, st)
    local free = frame.flags['SK Widget']
    cfg.ui.locked = true
    render(cfg, st)
    eq(frame.flags['SK Widget'] - free, ImGuiWindowFlags_NoMove)
    eq(render(cfg, st, on('UI / Log', { ['Show the widget##sk_ui_widget'] = true })), 1)
    eq(cfg.ui.widget, false)
    close_settings()
end)

test('UI / Log shows and hides the HUD, as /sk hud, and remembers it; Sidekick Settings stay', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.ui.open = true
    eq(render(cfg, st, on('UI / Log', { ['Show the HUD##sk_ui_open'] = true })), 1)
    eq({ st.open, cfg.ui.open }, { false, false })
    render(cfg, st)
    eq({ begun('Sidekick'), begun('Sidekick Settings') }, { false, true })
    eq(render(cfg, st, on('UI / Log', { ['Show the HUD##sk_ui_open'] = true })), 1)
    eq({ st.open, cfg.ui.open }, { true, true })
    render(cfg, st)
    eq(begun('Sidekick'), true)
    close_settings()
end)

test('with the HUD closed the widget still shows, and its cog opens Sidekick Settings; they stand apart from the HUD', function ()
    close_settings()
    local cfg = widget_cfg()
    render(cfg, status({ open = false }))
    eq({ begun('Sidekick'), begun('SK Widget') }, { false, true })
    render(cfg, status({ open = false }), { ['##sk_widget_cog'] = true })
    render(cfg, status({ open = false }))
    eq({ begun('Sidekick'), begun('Sidekick Settings') }, { false, true })
    render(cfg, status())
    render(cfg, status({ open = false }))  -- /sk hud closed the HUD: they stay
    eq(begun('Sidekick Settings'), true)
    render(cfg, status(), { ['##sk_close'] = true })  -- the HUD's own close too
    render(cfg, status({ open = false }))
    eq(begun('Sidekick Settings'), true)
    local plain = settings.defaults()
    render(plain, status({ open = false }))  -- no widget nor HUD: still up, /sk's alone
    eq({ begun('Sidekick'), begun('SK Widget'), begun('Sidekick Settings') }, { false, false, true })
    render(plain, status({ open = false }), { close = 'Sidekick Settings' })  -- their X: /sk opens them again
    render(plain, status({ open = false }))
    eq({ settings_shown, begun('Sidekick Settings') }, { false, false })
    render(plain, status({ open = false, settings = true }))  -- /sk
    eq({ begun('Sidekick'), begun('SK Widget'), begun('Sidekick Settings') }, { false, false, true })
    close_settings()
end)

test('the widget\'s name tooltip says what it does or why it waits; nothing of it is drawn', function ()
    close_settings()
    local cfg = widget_cfg()
    render(cfg, status({ open = false, running = true, intent = false, why = 'holding Valor Minuet IV for Pianissimo' }))
    eq({ tipped('Running'), tipped('(holding Valor Minuet IV for Pianissimo)'), drew('holding'), drew('Running') },
       { true, true, false, false })
end)

test('targeting a player you could track, the widget ends its row with Add Tracked, as tall as a character\'s pill: a '
    .. 'click anywhere on it tracks them', function ()
    close_settings()
    local cfg, st = widget_cfg(), status({ open = false })  -- the HUD closed: the widget's pill alone
    local g = snap()
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    local narrow = calls('AddRectFilled')[1].args[2]  -- the panel's far corner
    eq({ button('##sk_widget_track_Stranger'), drew('Add Tracked') }, { false, false })
    g.target = STRANGER
    tracking_calls = {}
    eq(render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES)), 0)
    eq({ button('##sk_widget_track_Stranger'), begun('Sidekick Add Tracked'), fill('Add Tracked'), tracking_calls },
       { true, false, u32(P.white), {} })
    local panel, mine, pill = calls('AddRectFilled')[1].args[2], pills(P.halt, 'window')[1], add_pill()
    eq({ panel[1] > narrow[1], panel[2], frame.extent['SK Widget'] }, { true, narrow[2], panel })  -- wider; it fits it
    eq({ pill[1][1], pill[1][2], pill[2][2] }, { mine[2][1] + 6, mine[1][2], mine[2][2] })  -- after yours, in line
    eq(tipped('Track Stranger\nHeal, clear, raise and buff them too'), true)
    eq(render(cfg, st, { ['##sk_widget_track_Stranger'] = true }, model.build(g, cat, cfg, st, NAMES)), 0)
    eq(tracking_calls, { { 'add', 'Stranger' } })
    st.open = true  -- the HUD up too: clicked in either, neither shows it again till a snapshot shows them tracked
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ button('##sk_widget_track_Stranger'), begun('Sidekick Add Tracked'), frame.extent['SK Widget'] },
       { false, false, narrow })  -- the widget as narrow as without it
    g.target = nil
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    g.target = STRANGER  -- untracked and targeted again: a pill in each, either tracks
    render(cfg, st, nil, model.build(g, cat, cfg, st, NAMES))
    eq({ button('##sk_widget_track_Stranger'), begun('Sidekick Add Tracked') }, { true, true })
end)

test('a Lua error in the widget still ends every window, then is raised', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    local view = model.build(snap(), cat, cfg, st, NAMES)
    view.profiles = nil  -- read by the widget (and the HUD title's tooltip)
    local err = draw(window, cfg, st, nil, view)
    eq({ type(err), begun('Sidekick'), begun('SK Widget') }, { 'string', true, true })
end)

-- Sidekick Settings -----------------------------------------------------------------------

-- Sidekick Settings' pages for `cfg` (and `in_cat` in place of the catalog), in the list's order.
local function pages(cfg, in_cat)
    open_settings()
    local st = status()
    render(cfg, st, nil, in_cat and model.build(snap(), in_cat, cfg, st, NAMES))
    local out = {}
    for _, id in ipairs(frame.args.InvisibleButton) do
        local name = id:match('^##sk_page_(.*)')
        if name then out[#out + 1] = name end
    end
    return out
end

test('Sidekick Settings is one fixed width, the same for every job', function ()
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
    eq({ button('##sk_fold_heal'), button('##sk_fold_revive'), button('##sk_fold_buff') }, { true, true, false })
    eq({ button('Danger under##sk_heal_danger'), button('Cure##heal_Cure') }, { true, true })
    render(cfg, st, { ['##sk_fold_heal'] = true })
    render(cfg, st)
    eq({ button('Danger under##sk_heal_danger'), button('Cure##heal_Cure'), button('##sk_fold_revive') }, { false, false, true })
    render(cfg, st, { ['##sk_fold_heal'] = true })
    render(cfg, st, on('Buff'))
    eq({ button('##sk_fold_buff'), button('##sk_fold_heal') }, { true, false })
    render(cfg, st, on('Heal'))
    eq(button('Cure##heal_Cure'), true)
end)

test('section switches write: Buffs, Follow, Wake sleepers, Resting', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Buff', { ['Buffs##sk_on_buff'] = true })), 1)
    eq(render(cfg, st, on('Follow', { ['Follow##sk_on_follow'] = true })), 1)
    eq(render(cfg, st, on('Remove', { ['Wake sleepers##sk_on_wake'] = true })), 1)
    eq(render(cfg, st, on('Recover', { ['Resting##sk_on_rest'] = true })), 1)
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
    eq({ cfg.rows.Protect.targets, button('P4##buff_Protect4') }, { { [0] = true, [1] = true }, false })
    eq(render(cfg, st, on('Heal', { ['Cure##heal_Cure'] = true })), 1)
    eq(cfg.rows.Cure, { on = false })
    eq(render(cfg, st, on('Remove', { ['Echo Drops (0)###remove_Echo Drops'] = true })), 1)  -- an item, with how many you carry
    eq(cfg.rows['Echo Drops'], { on = true })
    eq(render(cfg, st, on('Remove', { ['Paralysis##remove_*_paralysis'] = true })), 1)  -- Everyone's tab, a debuff by name
    eq({ cfg.remove.skip, cfg.remove.own, cfg.rows.paralysis }, { { paralysis = true }, {}, nil })
    eq(render(cfg, st, on('Remove', { ['Erase##remove_with_Erase'] = true })), 1)  -- a remover's checkbox, unticked
    eq(cfg.rows.Erase, { on = false })
    eq(render(cfg, st, on('Heal', { ['Cure II##sk_heal_spell_Cure II'] = true })), 1)  -- one heal, its row aside
    eq(cfg.heal.never, { ['Cure II'] = true })
    eq(render(cfg, st, on('Remove', { ['Dia##remove_*_Dia'] = true })), 0)  -- only Erase removes it: greyed, no click
    eq(render(cfg, st, on('Remove', { ['Doom##remove_*_doom'] = true })), 1)  -- Doom too
    eq(cfg.remove.skip, { paralysis = true, doom = true })
end)

test('items get a heading of their own, with no pick or targets', function ()
    open_settings()
    render(settings.defaults(), status(), on('Remove'))
    eq({ drew('I T E M S'), button('Echo Drops (0)###remove_Echo Drops'), button('##pick_remove_Echo Drops') }, { true, true, false })
    eq({ drew('D E B U F F S'), button('None##remove_debuff_none'), button('All##remove_debuff_all'),
         button('Paralysis##remove_*_paralysis'), button('Everyone##remove_tab_*'), button('ME##remove_tab_0'),
         button('Paralyna##remove_Paralyna') },
       { true, true, true, true, true, true, false })
    eq({ drew('R E M O V E R S'), button('Erase##remove_with_Erase') }, { true, true })
    render(settings.defaults(), status(), on('Buff'))
    eq({ button('##pick_buff_Protect'), button('P1##buff_Protect1'), drew('I T E M S') }, { true, true, false })
end)

test('sliders, the focus and the options write the settings', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['Danger under##sk_heal_danger'] = 60 })), 1)
    eq(cfg.heal.danger, 60)
    eq(render(cfg, st, on('Heal', { ['A##sk_focus_A'] = true })), 1)  -- the focus drop-down's member
    eq(cfg.heal.focus, 'A')
    eq(render(cfg, st, on('Heal', { ['None##sk_focus_none'] = true })), 1)
    eq(cfg.heal.focus, '')
    eq(render(cfg, st, on('UI / Log', { ['Japanese client##sk_japanese'] = true })), 1)
    eq(cfg.ui.japanese, true)
    eq(render(cfg, st, on('Heal', { ['Focus danger under##sk_heal_focus_danger'] = 65 })), 1)
    eq(cfg.heal.focus_danger, 65)
    render(cfg, st, on('Buff'))
    eq(frame.ids['Sidekick Settings|Ask them to gather##sk_buff_gather'], nil)  -- only while holding
    eq(render(cfg, st, on('Buff', { ['Hold area buffs for the group##sk_buff_hold_aoe'] = true })), 1)
    eq(cfg.buff.hold_aoe, true)
    eq(render(cfg, st, on('Buff', { ['Ask them to gather##sk_buff_gather'] = true })), 1)
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

test('with every efficient heal off, Heal under and Focus heal under are greyed and dead, and say why', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    local MINE = 'All efficient healing abilities are disabled, so Heal under can\'t work.'
    local FOCUS = 'All efficient healing abilities that can reach the focus member are disabled, so Focus heal under '
        .. 'can\'t work.'
    render(cfg, st, on('Heal', { over = true }))
    eq({ tipped(MINE), tipped(FOCUS) }, { false, false })
    for _, a in ipairs(cat) do  -- Regen's tiers unticked; the other heal rows off
        if a.role == 'heal' and a.family == 'Regen' then cfg.heal.never[a.name] = true
        elseif a.role == 'heal' then cfg.rows[settings.key(a)] = { on = false } end
    end
    cfg.heal.threshold = cfg.heal.danger  -- the danger note gives way to the reason
    eq(render(cfg, st, on('Heal', { ['Heal under##sk_heal_threshold'] = 60, ['Focus heal under##sk_heal_focus_threshold'] = 60,
        ['Danger under##sk_heal_danger'] = 40, over = true })), 1)
    eq({ cfg.heal.threshold, cfg.heal.focus_threshold, cfg.heal.danger }, { 50, 85, 40 })
    eq({ tipped(MINE), tipped(FOCUS), drew('Heal under is at or under Danger under') }, { true, true, false })
    cfg.rows.Drain = nil  -- Drain back: it heals only you, so only the focus member's line stays greyed
    render(cfg, st, on('Heal', { over = true }))
    eq({ tipped(MINE), tipped(FOCUS) }, { false, true })
    cfg.heal.never['Regen II'] = nil  -- one tier back: efficient healing has it
    render(cfg, st, on('Heal', { over = true }))
    eq({ tipped(MINE), tipped(FOCUS) }, { false, false })
end)

test('a slider\'s value, clicked, takes a typed number, held to its range', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['Danger under##sk_heal_danger.value'] = true, ['##Danger under##sk_heal_danger.typed'] = '45' })), 1)
    eq(cfg.heal.danger, 45)
    eq(render(cfg, st, on('Heal', { ['##Danger under##sk_heal_danger.typed'] = '250' })), 1)
    eq(cfg.heal.danger, 99)
    eq(render(cfg, st, on('Heal', { ['##Danger under##sk_heal_danger.typed'] = 'lots' })), 0)
end)

test('recovery, pet, follow and rest settings write through act', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Recover', { ['MP under##sk_recover_mp'] = 40, ['TP under##sk_recover_tp'] = 1500 })), 2)
    eq({ cfg.recover.mp, cfg.recover.tp }, { 40, 1500 })
    eq(render(cfg, st, on('Recover', { ['Spend TP from##sk_recover_min_tp'] = 1500 })), 0)  -- no Chivalry here
    local pld = model.build(snap(), fake.catalog(7, 75, nil, 0, { 'Chivalry' }), cfg, st, NAMES)
    eq(render(cfg, st, on('Recover', { ['Spend TP from##sk_recover_min_tp'] = 1500 }), pld), 1)
    eq(cfg.recover.min_tp, 1500)
    local pup = model.build(snap(), fake.catalog(18, 75, nil, 0, { 'Repair', 'Deploy' }), cfg, st, NAMES)
    eq(render(cfg, st, on('Pet', { ['Pet HP under##sk_pet_heal'] = 70 }), pup), 1)
    eq(cfg.pet.heal, 70)
    eq(render(cfg, st, on('Follow', { ['A##sk_follow_target_A'] = true, ['Follow past##sk_follow_distance'] = 9 })), 2)
    eq({ cfg.follow.target, cfg.follow.distance, cfg.heal.focus }, { 'A', 9, '' })
    eq(render(cfg, st, on('Recover', { ['Rest under##sk_rest_mp'] = 60, ['Stand past##sk_rest_distance'] = 12 })), 2)
    eq({ cfg.rest.mp, cfg.rest.distance }, { 60, 12 })
end)

test('recovery aims Devotion: a drop-down only for a job with it, Lowest MP for no one in particular', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Recover'))
    eq(drew('Devotion on'), false)  -- no Devotion here
    local whm = model.build(snap(), fake.catalog(3, 75, nil, 0, { 'Devotion' }), cfg, st, NAMES)
    render(cfg, st, on('Recover'), whm)
    eq({ drew('Devotion on'), drew('Lowest MP') }, { true, true })
    eq(render(cfg, st, on('Recover', { ['A##sk_recover_target_A'] = true }), whm), 1)
    eq(cfg.recover.target, 'A')
    eq(render(cfg, st, on('Recover', { ['Lowest MP##sk_recover_target_none'] = true }), whm), 1)
    eq(cfg.recover.target, '')
    cfg.recover.target = 'Gone'  -- not in the party now: shown by name, not as Lowest MP
    render(cfg, st, on('Recover'), model.build(snap(), fake.catalog(3, 75, nil, 0, { 'Devotion' }), cfg, st, NAMES))
    eq({ drew('Gone'), drew('Lowest MP') }, { true, false })
end)

test('resting shows Follow\'s leader and sets it too', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.follow.target = 'A'
    render(cfg, st, on('Recover'))
    eq(drew('Leader'), true)
    eq(render(cfg, st, on('Recover', { ['None##sk_rest_leader_none'] = true })), 1)
    eq(cfg.follow.target, '')
    eq(render(cfg, st, on('Recover', { ['A##sk_rest_leader_A'] = true })), 1)
    eq(cfg.follow.target, 'A')
end)

test('AFK sleep: its minutes, and how it stands while running', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('AFK', { ['Sleep after##sk_afk_minutes'] = 20, ['AFK sleep##sk_on_afk'] = true })), 2)
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
    eq(render(cfg, st, on('Heal', { ['P1##sk_heal_1'] = true })), 1)
    eq(cfg.heal.skip, { A = true })
    eq(render(cfg, st, on('Heal', { ['P1##sk_heal_1'] = true })), 1)
    eq(cfg.heal.skip, {})
    eq(render(cfg, st, on('Heal', { ['P4##sk_heal_4'] = true })), 0)  -- empty slot
    eq(button('P4##sk_heal_4'), false)
end)

test('Heal, Remove and Buff leave empty slots out, but not a buff target still on in one', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Heal'))
    eq({ button('ME##sk_heal_0'), button('P2##sk_heal_2'), button('P3##sk_heal_3'), button('B0##sk_heal_6') },
       { true, true, false, false })
    render(cfg, st, on('Remove'))
    eq({ button('P1##sk_remove_who_1'), button('P3##sk_remove_who_3'), button('C0##sk_remove_who_12') },
       { true, false, false })
    render(cfg, st, on('Buff'))
    eq({ button('P1##buff_Haste1'), button('P5##buff_Haste5'), button('B0##buff_Haste6') }, { true, false, false })
    cfg.rows.Haste = { on = true, targets = { [0] = true, [5] = true } }  -- P5 picked, and since gone
    eq(render(cfg, st, on('Buff', { ['P5##buff_Haste5'] = true })), 1)
    eq(cfg.rows.Haste.targets, { [0] = true })
    eq(button('P5##buff_Haste5'), true)  -- drawn the frame it's clicked off; gone from the next
    render(cfg, st, on('Buff'))
    eq(button('P5##buff_Haste5'), false)
end)

test('UI / Log: the sliders size the HUD and Sidekick Settings, Lock position keeps the HUD still', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log', { ['HP bar width##sk_ui_hp_width'] = 300, ['Name text size##sk_ui_name_size'] = 30,
        ['TP bar width##sk_ui_tp_width'] = 250, ['TP bar height##sk_ui_tp_height'] = 12,
        ['Size##sk_ui_scale'] = 150 })), 5)
    eq({ cfg.ui.hp_width, cfg.ui.name_size, cfg.ui.tp_width, cfg.ui.tp_height, cfg.ui.scale }, { 300, 30, 250, 12, 150 })
    -- General's, Party's and Alliance / Tracked's, each under its own heading.
    eq(render(cfg, st, on('UI / Log', { ['Icon size##sk_ui_icon_size'] = 20, ['Slot text size##sk_ui_text_size'] = 12,
        ['MP bar offset##sk_ui_mp_offset'] = 10, ['TP bar offset##sk_ui_tp_offset'] = 20,
        ['Name/slot text size##sk_ui_ally_text_size'] = 11, ['HP bar width##sk_ui_ally_hp_width'] = 150,
        ['HP bar height##sk_ui_ally_hp_height'] = 9, ['Show player slot##sk_ui_show_slot'] = true,
        ['HP bar offset##sk_ui_pet_hp_offset'] = 12, ['TP bar height##sk_ui_pet_tp_height'] = 6 })), 10)
    eq({ cfg.ui.icon_size, cfg.ui.text_size, cfg.ui.mp_offset, cfg.ui.tp_offset, cfg.ui.ally_text_size,
         cfg.ui.ally_hp_width, cfg.ui.ally_hp_height, cfg.ui.show_slot, cfg.ui.pet_hp_offset, cfg.ui.pet_tp_height },
       { 20, 12, 10, 20, 11, 150, 9, false, 12, 6 })
    eq({ cfg.ui.hp_width, cfg.ui.tp_height }, { 300, 12 })  -- Pet's are its own: the cards' stay
    local letters = {}  -- a heading is drawn a letter at a time
    for _, d in ipairs(calls('AddText')) do letters[#letters + 1] = d.args[5] end
    letters = table.concat(letters)
    local function place(s) return letters:find(s, 1, true) or false end
    -- In order, Alliance / Tracked last, as their rows are in the HUD; then the widget's.
    local order = { place('HUD - GENERAL'), place('HUD - PARTY'), place('HUD - BUFFS'), place('HUD - PET'),
                    place('HUD - ALLIANCE / TRACKED'), place('WIDGET') }
    for i = 2, #order do eq(order[i - 1] and order[i] and order[i - 1] < order[i], true, 'heading ' .. i) end
    eq(button('Background opacity##sk_ui_opacity'), false)  -- the panel is solid while hovered: nothing to set
    local free = frame.flags.Sidekick
    eq(render(cfg, st, on('UI / Log', { ['Lock position##sk_ui_locked'] = true })), 1)
    eq(cfg.ui.locked, true)
    render(cfg, st)
    eq(frame.flags.Sidekick - free, ImGuiWindowFlags_NoMove)
    eq(render(cfg, st, on('UI / Log', { ['Hide unused MP bars##sk_ui_hide_mp'] = true })), 1)
    eq(cfg.ui.hide_mp, false)
    cfg.ui.scale = nil
    render(cfg, st)
end)

test('UI / Log: HUD - Buffs switches the icons and their timers and sizes and lifts them; greyed while off', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq({ cfg.ui.buff_icons, cfg.ui.buff_size, cfg.ui.buff_offset, cfg.ui.buff_timers, cfg.ui.buff_timer_size },
       { true, 16, 0, true, 10 })
    eq(render(cfg, st, on('UI / Log', { ['Buff icon size##sk_ui_buff_size'] = 30,
        ['Buff icon height##sk_ui_buff_offset'] = -12, ['Timer text size##sk_ui_buff_timer_size'] = 14 })), 3)
    eq({ cfg.ui.buff_size, cfg.ui.buff_offset, cfg.ui.buff_timer_size }, { 30, -12, 14 })
    eq(render(cfg, st, on('UI / Log', { ['Buff timers##sk_ui_buff_timers'] = true })), 1)
    eq(cfg.ui.buff_timers, false)
    eq(render(cfg, st, on('UI / Log', { ['Timer text size##sk_ui_buff_timer_size'] = 20, over = true })), 0)
    eq({ cfg.ui.buff_timer_size, tipped('Needs Buff timers on.') }, { 14, true })
    eq(render(cfg, st, on('UI / Log', { ['Buff icons##sk_ui_buff_icons'] = true })), 1)
    eq(cfg.ui.buff_icons, false)
    eq(render(cfg, st, on('UI / Log', { ['Buff icon size##sk_ui_buff_size'] = 40,
        ['Buff icon height##sk_ui_buff_offset'] = 5, over = true })), 0)
    eq({ cfg.ui.buff_size, cfg.ui.buff_offset, tipped('Needs Buff icons on.') }, { 30, -12, true })
end)

test('UI / Log: HUD - Colors switches Job colors, Subjob color and HP glow, picks the Split and slides the Blend', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq({ cfg.ui.job_colors, cfg.ui.sub_colors, cfg.ui.hp_glow, cfg.ui.split, cfg.ui.blend }, { true, true, true, 'diagonal', 50 })
    eq(render(cfg, st, on('UI / Log', { ['Job colors##sk_ui_job_colors'] = true, ['Subjob color##sk_ui_sub_colors'] = true,
        ['HP glow##sk_ui_hp_glow'] = true })), 3)
    eq({ cfg.ui.job_colors, cfg.ui.sub_colors, cfg.ui.hp_glow }, { false, false, false })
    eq(render(cfg, st, on('UI / Log', { ['Blend##sk_ui_blend'] = 80, ['Horizontal##sk_ui_split_horizontal'] = true,
        over = true })), 0)  -- Split and Blend greyed: nothing to blend
    eq({ cfg.ui.blend, cfg.ui.split, tipped('Needs Job colors and Subjob color on.') }, { 50, 'diagonal', true })
    cfg.ui.job_colors = true  -- one of the two isn't enough
    eq(render(cfg, st, on('UI / Log', { ['Blend##sk_ui_blend'] = 80, ['Horizontal##sk_ui_split_horizontal'] = true })), 0)
    cfg.ui.job_colors = false
    cfg.ui.job_colors, cfg.ui.sub_colors = true, true
    eq(render(cfg, st, on('UI / Log', { ['Blend##sk_ui_blend'] = 80, ['Horizontal##sk_ui_split_horizontal'] = true })), 2)
    eq({ cfg.ui.blend, cfg.ui.split }, { 80, 'horizontal' })
end)

test('UI / Log lists the last actions sent, and has no action log switch', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log')), 0)
    eq({ button('Action log##sk_log'), drew('Cure IV -> A'), drew('heal: A at 62%') }, { false, true, true })
    eq({ cfg, st.log }, { settings.defaults(), true })  -- the page writes nothing, and leaves the session log as it was
    render(cfg, status({ sent = {} }), on('UI / Log'))
    eq(drew('Nothing sent yet.'), true)
end)

test('UI / Log lists the themes, Standard first, the one drawing lit: a click on another picks it, one that failed '
    .. 'says why and isn\'t taken', function ()
    open_settings()
    theme_calls = {}
    local clicks = { ['##sk_theme_window'] = true, ['##sk_theme_classic'] = true, ['##sk_theme_broken'] = true }
    eq(render(settings.defaults(), status(), on('UI / Log', clicks)), 0)  -- not a setting: nothing written
    eq(theme_calls, { 'classic' })
    eq({ drew('T H E M E'), drew('Standard'), drew('Classic'), drew('broken (failed to load)') }, { true, true, true, true })
    eq({ tipped('ui/classic.lua'), tipped('Failed to load: ' .. BROKEN) }, { true, true })
    eq(fill('Standard') ~= fill('Classic'), true)  -- lit: drawing now
    render(settings.defaults(), status({ themes = { list = {} } }), on('UI / Log'))
    eq(drew('T H E M E'), false)  -- none known: no list
    render(settings.defaults(), status(), on('UI / Log'), model.build(snap(), cat, settings.defaults(), status({ themes = false }), NAMES))
    eq(drew('T H E M E'), false)
end)

-- Every theme in ui/ (Sidekick's Classic, and any of yours) gets the same checks as the standard window: it
-- loads, and draws running and stopped, its HUD and Sidekick Settings shown and hidden, closing every scope. The fake
-- answers false to any call it has no handler for; add one if yours needs it.
local themes = require('core.themes')
local in_ui = {}
for file in io.popen(package.config:sub(1, 1) == '\\' and 'dir /b ui' or 'ls ui'):lines() do in_ui[#in_ui + 1] = file end
local real_files = themes.files
themes.files = function () return in_ui end
themes.init(window)
themes.files = real_files
for _, th in ipairs(themes.list) do
    if th.key ~= themes.STANDARD then
        test(th.file .. ' loads and draws running and stopped, its HUD and Sidekick Settings shown and hidden, every '
            .. 'scope closed', function ()
            assert(th.ui, th.error)
            local was_shown = settings_shown
            local ok, err = pcall(function ()
                for _, settings_on in ipairs({ false, true }) do  -- its Sidekick Settings
                    for _, hud in ipairs({ false, true }) do
                        for _, running in ipairs({ false, true }) do
                            eq(draw(th.ui, settings.defaults(), status({ running = running, open = hud, settings = settings_on })),
                               nil, 'no Lua error')
                        end
                    end
                end
            end)
            -- The tests after this one take up the standard window where it was, failed or not: draw it once more.
            render(settings.defaults(), status({ settings = was_shown }))
            assert(ok, err)
        end)
    end
end

test('a trust that can\'t be hurt: its buff, heal and removal chips are greyed and take no click; Classic\'s too', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    local g = fake.snap({ { name = 'Moogle', kind = 'trust', immune = true } })
    local view = function () return model.build(g, cat, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['P1##buff_Protect1'] = true }), view()), 0)
    eq(render(cfg, st, on('Heal', { ['P1##sk_heal_1'] = true }), view()), 0)
    eq(render(cfg, st, on('Remove', { ['P1##sk_remove_who_1'] = true }), view()), 0)
    local d = settings.defaults()
    eq({ cfg.rows.Protect, cfg.heal.skip, cfg.remove.off }, { nil, d.heal.skip, d.remove.off })
    local classic = themes.get('classic')
    local was_shown = settings_shown
    eq(draw(classic.ui, cfg, status({ settings = true }), nil, view()), nil)
    render(settings.defaults(), status({ settings = was_shown }))
end)

test('Classic is ui/classic.lua; Party State\'s Theme lists every theme, a click on another picks it', function ()
    local classic = themes.get('classic')
    eq({ classic and classic.name, classic and classic.error }, { 'Classic', nil })
    local was_shown = settings_shown
    theme_calls = {}
    local th = { current = 'classic', list = THEMES.list }
    local err = draw(classic.ui, settings.defaults(), status({ open = true, themes = th }),
        { ['Standard##sk_ps_theme_window'] = true, ['Classic##sk_ps_theme_classic'] = true,
          ['broken (failed to load)##sk_ps_theme_broken'] = true })
    local combo = has(frame.args.BeginCombo, 'Theme##sk_ps_theme')
    render(settings.defaults(), status({ settings = was_shown }))
    eq({ err, combo, theme_calls }, { nil, true, { 'window' } })
end)

test('a tracked player\'s row has its slot; Tracked lists them to untrack, and offers your target', function ()
    local g = fake.snap({ { name = 'A', tracked = true }, { kind = 'tracked', name = 'Out', hpp = 80, main = 3, main_lv = 75, sub = 4, sub_lv = 37 } },
        { target = { sid = 900, tidx = 1200, name = 'Stranger' } })
    local cfg, st = settings.defaults(), status()
    open_settings()
    tracking_calls = {}
    local writes = render(cfg, st, on('Tracked', { ['Untrack##sk_untrack_Out'] = true, ['Track Stranger##sk_track'] = true }),
        model.build(g, cat, cfg, st, NAMES))
    eq({ tracking_calls, writes }, { { { 'remove', 'Out' }, { 'add', 'Stranger' } }, 0 })
    eq(fill('T1') ~= nil, true)
    eq(tipped('Out (tracked, WHM 75 / BLM 37)\nHP 80%  5.0y'), true)
    eq({ drew('T1 Out  WHM 75 / BLM 37'), drew('P1 A  (in your party)') }, { true, true })
    g.target = nil
    render(cfg, st, on('Tracked'), model.build(g, cat, cfg, st, NAMES))
    eq(drew('Target a player outside your alliance to track them, or /sk track Name.'), true)
end)

test('alliance members are listed under Heal and Buff; Tracked lists one in the alliance', function ()
    local g = fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea', tracked = true } })
    local cfg, st = settings.defaults(), status()
    open_settings()
    eq(render(cfg, st, on('Heal', { ['B0##sk_heal_6'] = true }), model.build(g, cat, cfg, st, NAMES)), 1)
    eq(cfg.heal.skip, { Bea = true })
    eq({ button('B1##sk_heal_7'), button('C0##sk_heal_12') }, { false, false })  -- their empty slots aren't
    eq(render(cfg, st, on('Buff', { ['B0##buff_Haste6'] = true }), model.build(g, cat, cfg, st, NAMES)), 1)
    eq(cfg.rows.Haste.targets, { [0] = true, [6] = true })
    eq({ fill('Bea'), hp_fill(108, 50 + 25 + 2 * 72 + 8 + 8) ~= nil }, { u32(P.white), true })  -- a row in the HUD
    render(cfg, st, on('Tracked'), model.build(g, cat, cfg, st, NAMES))
    eq(drew('B0 Bea  (in your alliance)'), true)
    eq(button('Heal the alliance##sk_heal_alliance'), false)
end)

test('Remove: a tab for everyone and one per player that is on, and None and All for the tab picked', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Remove', { ['P1##sk_remove_who_1'] = true })), 1)
    eq(cfg.remove.off, { A = true })  -- by name
    render(cfg, st, on('Remove'))
    eq({ button('Everyone##remove_tab_*'), button('P1##remove_tab_1'), button('P2##remove_tab_2') }, { true, false, true })
    eq(render(cfg, st, on('Remove', { ['Paralysis##remove_*_paralysis'] = true })), 1)
    eq(cfg.remove.skip, { paralysis = true })
    eq(render(cfg, st, on('Remove', { ['P2##remove_tab_2'] = true })), 0)  -- the tab is this window's, not a setting
    eq(render(cfg, st, on('Remove', { ['None##remove_debuff_none'] = true })), 1)
    eq({ cfg.remove.own.B.set, cfg.remove.own.B.skip.paralysis, cfg.remove.own.B.skip.doom, cfg.remove.skip },
       { true, true, true, { paralysis = true } })
    eq(render(cfg, st, on('Remove', { ['All##remove_debuff_all'] = true })), 1)
    eq(cfg.remove.own.B.skip, {})
    eq(render(cfg, st, on('Remove', { ['Paralysis##remove_B_paralysis'] = true })), 1)
    eq({ cfg.remove.own.B.skip, cfg.remove.skip }, { { paralysis = true }, { paralysis = true } })
    eq(render(cfg, st, on('Remove', { ['Everyone##remove_tab_*'] = true })), 0)  -- back to Everyone for the tests after this
end)

local function profiles_named(cfg) return require('core.profiles').names(cfg) end

test('Profiles: Save names the profile loaded, a click loads one, Default goes back; the list names it', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.heal.danger = 40
    render(cfg, st, on('Profiles', { ['Save as##sk_profile_save_as'] = true }))  -- the name typed is blank: nothing saved
    eq(next(cfg.profiles), nil)
    cfg.profiles.Dynamis = { heal = { danger = 20 } }
    local writes = render(cfg, st, on('Profiles', { ['##sk_profile_1'] = true }))
    eq({ cfg.profile, cfg.heal.danger, cfg.parked.heal.danger, writes }, { 'Dynamis', 20, 40, 1 })
    render(cfg, st, on('Profiles'))
    eq({ drew('loaded: Dynamis'), button('Delete##sk_profile_delete') }, { true, true })
    cfg.heal.danger = 25
    render(cfg, st, on('Profiles', { ['Save##sk_profile_save'] = true }))  -- the name field holds the one loaded
    eq(cfg.profiles.Dynamis.heal.danger, 25)
    render(cfg, st, on('Profiles', { ['Default##sk_profile_default'] = true }))
    eq({ cfg.profile, cfg.heal.danger }, { '', 40 })
    render(cfg, st, on('Profiles'))
    eq(button('Delete##sk_profile_delete'), false)
    render(cfg, st, on('Profiles', { ['##sk_profile_1'] = true }))
    render(cfg, st, on('Profiles', { ['New##sk_profile_new'] = true }))  -- the name loaded is cleared with it
    render(cfg, st, on('Profiles', { ['Save##sk_profile_save'] = true }))
    eq({ profiles_named(cfg), cfg.profile }, { { 'Dynamis' }, '' })
    eq(render(cfg, st, on('Profiles', { ['##sk_profile_name'] = ' Sky ' })), 0)  -- typed, then saved under it trimmed
    render(cfg, st, on('Profiles', { ['Save##sk_profile_save'] = true }))
    eq(profiles_named(cfg), { 'Dynamis', 'Sky' })
end)

test('Profiles: a name with ## is drawn whole, each row its own; a taken name says so', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    cfg.profiles['Sky##2'], cfg.profiles['a###x'], cfg.profiles['b###x'] = {}, {}, {}
    render(cfg, st, on('Profiles', { ['##sk_profile_2'] = true }))  -- names in order: a###x, b###x, Sky##2
    eq(cfg.profile, 'b###x')
    render(cfg, st, on('Profiles', { ['##sk_profile_3'] = true }))
    eq(cfg.profile, 'Sky##2')
    render(cfg, st, on('Profiles'))
    eq({ drew('Sky##2'), drew('a###x'), drew('loaded: Sky##2') }, { true, true, true })
    render(cfg, st, on('Profiles', { ['##sk_profile_name'] = 'a###x' }))
    render(cfg, st, on('Profiles'))
    eq(drew('a###x exists: Save as replaces it.'), true)
    render(cfg, st, on('Profiles', { ['Default##sk_profile_default'] = true }))
    render(cfg, st, on('Profiles'))  -- the name field empties with Default
    eq(drew('exists: Save as replaces it.'), false)
end)

test('SCH: a buff row\'s stratagem chips follow its targets and each toggles', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Celerity', 'Accession', 'Perpetuance' })
    local cfg, st = settings.defaults(), status()
    local function view() return model.build(snap(), sch, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Accession##buff_Protect_mod_Accession'] = true }), view()), 1)
    eq(cfg.rows.Protect, { on = false, mods = { Accession = true } })
    eq(button('Penury##buff_Protect_mod_Penury'), true)
    eq(render(cfg, st, on('Buff', { ['Accession##buff_Protect_mod_Accession'] = true }), view()), 1)
    eq(cfg.rows.Protect.mods, {})
    eq(render(cfg, st, on('Buff', { ['Hold##buff_Protect_hold'] = true }), view()), 1)
    eq({ cfg.rows.Protect.hold, tipped('No modifier is on here: it waits for nothing.') }, { true, true })
    render(cfg, st, on('Buff'))
    eq({ button('Penury##buff_Protect_mod_Penury'), button('Hold##buff_Protect_hold') }, { false, false })  -- WHM: no stratagems
end)

test('SCH: the storm row\'s list has Auto first, which turns Match on; a tier picked turns it off', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts' })
    local cfg, st = settings.defaults(), status()
    local function view() return model.build(snap(), sch, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Auto (weather)'] = true }), view()), 1)
    eq({ cfg.rows.storm, tipped('Cast the storm matching the zone\'s weather.') }, { { on = false, match = true }, true })
    eq(render(cfg, st, on('Buff', { ['Firestorm'] = true }), view()), 1)
    eq(cfg.rows.storm, { on = false, pick = 'Firestorm' })
    eq({ has(frame.args.Selectable, 'Auto (weather/day)'), button('Match##buff_storm_match') }, { true, false })  -- RDM sub
end)

test('Classic: an enspell or storm row\'s list has Auto first; picking a tier leaves it', function ()
    local classic = themes.get('classic')
    local was_shown = settings_shown
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts' })
    local cfg = settings.defaults()
    local st = status({ settings = true })
    handlers.CollapsingHeader = function () return true end  -- the fake's headers are shut: open them, here alone
    local err = draw(classic.ui, cfg, st, { ['Auto (weather)##sk_pick_buff_storm_match'] = true },
        model.build(snap(), sch, cfg, st, NAMES))
    local matched = cfg.rows.storm and cfg.rows.storm.match
    local enspell = has(frame.args.Selectable, 'Auto (weather/day)##sk_pick_buff_enspell_match')
    local bar = has(frame.args.Selectable, 'Auto (weather)##sk_pick_buff_barelement_match')
    local err2 = draw(classic.ui, cfg, st, { ['Hailstorm##sk_pick_buff_storm_Hailstorm'] = true },
        model.build(snap(), sch, cfg, st, NAMES))
    handlers.CollapsingHeader = nil
    render(settings.defaults(), status({ settings = was_shown }))
    eq({ err, err2, matched, enspell, bar, cfg.rows.storm }, { nil, nil, true, true, false, { on = false, pick = 'Hailstorm' } })
end)

test('Classic: Resource Recovery aims Devotion, Lowest MP for no one in particular, only for a job with it', function ()
    local classic = themes.get('classic')
    local was_shown = settings_shown
    local whm = fake.catalog(3, 75, nil, 0, { 'Devotion' })
    local cfg = settings.defaults()
    local st = status({ settings = true })
    handlers.CollapsingHeader = function () return true end  -- the fake's headers are shut: open them, here alone
    local err = draw(classic.ui, cfg, st, { ['A##sk_recover_target_A'] = true }, model.build(snap(), whm, cfg, st, NAMES))
    local picked = cfg.recover.target
    local listed = has(frame.args.Selectable, 'Lowest MP##sk_recover_target_none')
    local err2 = draw(classic.ui, cfg, st, { ['Lowest MP##sk_recover_target_none'] = true },
        model.build(snap(), whm, cfg, st, NAMES))
    local err3 = draw(classic.ui, cfg, st, {}, model.build(snap(), cat, cfg, st, NAMES))  -- no Devotion
    local without = has(frame.args.BeginCombo, 'Devotion Target##sk_recover_target')
    handlers.CollapsingHeader = nil
    render(settings.defaults(), status({ settings = was_shown }))
    eq({ err, err2, err3, picked, listed, cfg.recover.target, without }, { nil, nil, nil, 'A', true, '', false })
end)

test('SCH: Keep a stratagem for healing, under Heal, only for a job with stratagems', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Accession' })
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('Heal', { ['Keep a stratagem for healing##sk_heal_reserve'] = true }), model.build(snap(), sch, cfg, st, NAMES)), 1)
    eq(cfg.heal.reserve, true)
    eq(render(cfg, st, on('Heal', { ['Keep a stratagem for healing##sk_heal_reserve'] = true })), 0)  -- WHM: not drawn
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
    eq(render(cfg, st, on('Buff', { ['Corsair\'s Roll (EXP+)##sk_roll_first_Corsair\'s Roll'] = true }), view()), 1)
    eq(render(cfg, st, on('Buff', { ['Ninja Roll (EVA+)##sk_roll_second_Ninja Roll'] = true }), view()), 1)
    eq(render(cfg, st, on('Buff', { ['Highest##sk_roll_risk_highest'] = true, ['Rolls##sk_on_roll'] = true }), view()), 2)
    eq(cfg.roll, { on = false, first = 'Corsair\'s Roll', second = 'Ninja Roll', risk = 'highest', max_at_11 = false })
    eq({ drew('Last: Ninja Roll 4 (lucky)'), tipped('Lucky 5, unlucky 9.'), tipped('Highest: 11 or nothing.') }, { true, true, true })
    cfg.roll.second = cfg.roll.first
    render(cfg, st, on('Buff'), view())
    eq(drew('Roll 2 is Roll 1: one roll kept up'), true)
    cfg.roll.first = 'Bolter\'s Roll'
    render(cfg, st, on('Buff'), view())
    eq({ button('Roll 1##sk_roll_first'), drew('Bolter\'s Roll (not available)') }, { true, true })
    eq(has(frame.args.Selectable, 'None##sk_roll_first_none'), true)
    render(cfg, st, on('Buff'), view(13, 17, fake.catalog(13, 75, 17, 37, jas)))  -- NIN / COR
    eq({ drew('Roll 2: Corsair main job only'), button('Roll 2##sk_roll_second') }, { true, false })
    eq(button('Max risk while an 11 is up##sk_roll_max_at_11'), false)
end)

test('COR: Max risk while an 11 is up, on a Corsair main job; says when it is in effect', function ()
    open_settings()
    local cor = fake.catalog(17, 75, 3, 37, { 'Corsair\'s Roll', 'Ninja Roll', 'Double-Up', 'Snake Eye', 'Fold' })
    local cfg, st = settings.defaults(), status()
    cfg.roll.first, cfg.roll.second = 'Corsair\'s Roll', 'Ninja Roll'
    local function view()
        local g = snap()
        g.main, g.sub = 17, 3
        g.roll, g.roll_totals = { id = 626, total = 11, at = 990 }, { [626] = 11 }
        g.me.buffs[326] = true  -- Corsair's Roll on you, at 11
        return model.build(g, cor, cfg, st, NAMES)
    end
    eq(render(cfg, st, on('Buff', { ['Max risk while an 11 is up##sk_roll_max_at_11'] = true }), view()), 1)
    eq(cfg.roll.max_at_11, true)
    render(cfg, st, on('Buff'), view())
    eq({ drew('Risk at max: Corsair\'s Roll is at 11'), button('Max risk while an 11 is up##sk_roll_max_at_11') }, { true, true })
end)

test('BRD: Songs under Buff: Area and each slot that is filled or has a pick, a drop-down per song slot', function ()
    open_settings()
    local brd = fake.catalog(10, 75, 3, 37, { 'Pianissimo' })
    local cfg, st = settings.defaults(), status()
    local function view(main, sub, list)
        local g = snap(); g.main, g.sub = main or 10, sub or 3
        return model.build(g, list or brd, cfg, st, NAMES)
    end
    local minuet = 'Valor Minuet IV (+ATK)##sk_song_area_1_Valor Minuet IV'
    eq(render(cfg, st, on('Buff', { [minuet] = true, ['Mage\'s Ballad II (+Refresh)##sk_song_p1_2_Mage\'s Ballad II'] = true }), view()), 2)
    eq({ cfg.song.area_1, cfg.song.p1_2 }, { 'Valor Minuet IV', 'Mage\'s Ballad II' })
    render(cfg, st, on('Buff'), view())
    -- Area, ME, P1 and P2 (B, a trust in another zone); P3 is no one. Two slots on a Bard main job.
    eq({ button('##sk_song_area_2'), button('##sk_song_me_1'), button('##sk_song_p1_1'), button('##sk_song_p2_1'),
         button('##sk_song_p3_1') }, { true, true, true, true, false })
    eq({ drew('Pianissimo: ready'), button('##sk_song_me_2') }, { true, true })
    eq(render(cfg, st, on('Buff', { ['Song Duration##sk_song_duration'] = 170 }), view()), 1)  -- BRD 75 main
    eq(cfg.song.duration, 170)
    eq(render(cfg, st, on('Buff', { ['Pianissimo fast casting##sk_song_fast'] = true }), view()), 1)
    eq(cfg.song.fast, true)
    cfg.song.p4_1 = 'Herb Pastoral'
    render(cfg, st, on('Buff'), view())
    eq({ button('##sk_song_p4_1'), drew('no one') }, { true, true })  -- a pick keeps its line
    eq(render(cfg, st, on('Buff', { ['None##sk_song_area_1_none'] = true, ['Songs##sk_on_song'] = true }), view()), 2)
    eq({ cfg.song.area_1, cfg.song.on }, { '', false })
    render(cfg, st, on('Buff'), view(3, 10, fake.catalog(3, 75, 10, 15, {})))  -- WHM / BRD 15: one slot, no Pianissimo
    eq({ button('##sk_song_area_2'), drew('Songs on one member need Pianissimo (Bard 20)') }, { false, true })
    eq(button('Song Duration##sk_song_duration'), false)  -- a subjob has no timers
    eq(button('Pianissimo fast casting##sk_song_fast'), false)  -- nor fast casting, with no Pianissimo
    eq(render(cfg, st, on('Buff', { [minuet] = true })), 0)  -- WHM: no Songs
end)

test('GEO: Geomancy under Buff: its rows, how far and how long, and Entrust\'s member and spell', function ()
    open_settings()
    local geo = fake.catalog(21, 75, nil, 0, { 'Full Circle', 'Blaze of Glory', 'Entrust' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 21; return model.build(g, geo, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Recall past##sk_geo_distance'] = 12, ['Keep after combat##sk_geo_linger'] = 8 }), view()), 2)
    eq({ cfg.geo.distance, cfg.geo.linger }, { 12, 8 })
    eq(render(cfg, st, on('Buff', { ['A##sk_geo_entrust_A'] = true, ['Indi-Fury##sk_geo_entrust_spell_Indi-Fury'] = true }), view()), 2)
    eq({ cfg.geo.entrust, cfg.geo.entrust_spell }, { 'A', 'Indi-Fury' })
    eq(render(cfg, st, on('Buff', { ['P1##geo_geo1'] = true }), view()), 1)  -- the Geo row's target chips
    eq(cfg.rows.geo.targets, { [0] = true, [1] = true })
    eq(button('##pick_geo_geo'), true)  -- its luopan's spell
    eq(render(cfg, st, on('Buff', { ['Recall past##sk_geo_distance'] = 12 })), 0)  -- WHM: no Geomancy
end)

test('RUN: Runes under Buff: a line per set, a rune per slot by what it does, each ward\'s switch', function ()
    open_settings()
    local run = fake.catalog(22, 75, 4, 37, { 'Ignis', 'Gelus', 'Vallation', 'Pflug' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 22; return model.build(g, run, cfg, st, NAMES) end
    eq(render(cfg, st, on('Buff', { ['Fire##sk_rune_idle_1_Ignis'] = true, ['Wind##sk_rune_vallation_2_Gelus'] = true }), view()), 2)
    eq({ cfg.rune.idle_1, cfg.rune.vallation_2 }, { 'Ignis', 'Gelus' })
    eq(has(frame.args.Selectable, 'Silence / Weight##sk_rune_pflug_3_Gelus'), true, 'Pflug shows the ailments')
    eq(tipped('Ignis: adds Fire, resists Ice, against Paralyze / Bind.'), true)
    render(cfg, st, on('Buff'), view())
    eq({ button('##sk_rune_idle_1'), button('##sk_rune_idle_3'), drew('Idle') }, { true, true, true })  -- three slots
    eq(render(cfg, st, on('Buff', { ['Pflug##sk_rune_pflug'] = true, ['Runes##sk_on_rune'] = true }), view()), 2)
    eq({ cfg.rows.Pflug.on, cfg.rune.on }, { false, false })
    cfg.rune.idle_2 = 'Lux'
    render(cfg, st, on('Buff'), view())
    eq({ button('##sk_rune_idle_2'), tipped('Lux (not available)\nEach rune by the element') }, { true, true })  -- cut to fit, whole on hover
    local sub = fake.catalog(1, 75, 22, 37, { 'Ignis', 'Vallation' })
    local g = snap(); g.main, g.sub = 1, 22
    render(cfg, st, on('Buff'), model.build(g, sub, cfg, st, NAMES))  -- WAR / RUN 37: two slots
    eq({ button('##sk_rune_idle_2'), button('##sk_rune_idle_3') }, { true, false })
    eq(render(cfg, st, on('Buff', { ['Fire##sk_rune_idle_1_Ignis'] = true })), 0)  -- WHM: no Runes
end)

test('PUP: Maneuvers under Pet: a drop-down per slot by element, then whether they can go', function ()
    open_settings()
    local pup = fake.catalog(18, 75, 3, 37, { 'Fire Maneuver', 'Light Maneuver' })
    local cfg, st = settings.defaults(), status()
    local function view() local g = snap(); g.main = 18; return model.build(g, pup, cfg, st, NAMES) end
    eq(render(cfg, st, on('Pet', { ['Fire##sk_maneuver_1_Fire Maneuver'] = true, ['Light##sk_maneuver_3_Light Maneuver'] = true }), view()), 2)
    eq({ cfg.maneuver.slot_1, cfg.maneuver.slot_2, cfg.maneuver.slot_3 }, { 'Fire Maneuver', '', 'Light Maneuver' })
    render(cfg, st, on('Pet'), view())
    eq({ button('##sk_maneuver_2'), drew('ready') }, { true, true })
    eq(render(cfg, st, on('Pet', { ['None##sk_maneuver_1_none'] = true, ['Maneuvers##sk_on_maneuver'] = true }), view()), 2)
    eq({ cfg.maneuver.slot_1, cfg.maneuver.on }, { '', false })
    eq(render(cfg, st, on('Pet', { ['Fire##sk_maneuver_1_Fire Maneuver'] = true })), 0)  -- WHM: no Maneuvers
end)

-- Remote control -------------------------------------------------------------------

-- A's view as its own session publishes it (with its own settings).
local function remote_view(cfg)
    local st = status({ running = true, sent = {} })
    return model.published(model.build(snap(), cat, cfg, st, NAMES))
end

test('another session\'s card has its run button and cog: run starts it there, the cog shows its settings', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status()
    remote_calls = {}
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ button('##sk_run_A'), button('##sk_cog_A') }, { true, true })
    eq({ tipped('Start A\'s automation'), tipped('Settings for A'), tipped('A\nHP 62%') }, { true, true, false })
    eq(button('##sk_run_B'), false)  -- a trust: no session
    eq(render(cfg, st, { ['##sk_run_A'] = true }, model.build(snap(), cat, cfg, st, NAMES)), 0)
    eq({ remote_calls, st.running }, { { { 'A', 'run', true } }, false })  -- sent there, not run here
    st.sessions.A.running = true
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq(tipped('Stop A\'s automation'), true)
    render(cfg, st, { ['##sk_cog_A'] = true }, model.build(snap(), cat, cfg, st, NAMES))
    eq({ st.watching, settings_shown }, { { A = true }, false })
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ begun('Sidekick Settings: A###sk_settings_A'), drew('Waiting for A\'s session...') }, { true, true })
    render(cfg, st, { ['##sk_cog_A'] = true }, model.build(snap(), cat, cfg, st, NAMES))  -- the cog again hides it
    eq(st.watching, {})
end)

test('another session\'s Sidekick Settings draw its view; changes go to it, never to your settings', function ()
    close_settings()
    local mine, theirs = settings.defaults(), settings.defaults()
    theirs.heal.danger = 33
    local st = remote_status({ watching = { A = true } })
    st.views = { A = remote_view(theirs) }
    remote_calls = {}
    local function frame_with(clicks) return render(mine, st, clicks, model.build(snap(), cat, mine, st, NAMES)) end
    eq(frame_with(on('Heal', { ['Danger under##sk_heal_danger'] = 60, ['Cure##heal_Cure'] = true })), 0)
    eq(frame_with(on('Buff', { ['Buffs##sk_on_buff'] = true })), 0)
    eq(frame_with(on('Profiles', { ['Save as##sk_profile_save_as'] = true })), 0)
    eq(remote_calls, { { 'A', 'set', 'heal.danger', 60 }, { 'A', 'row', 'Cure', false }, { 'A', 'section', 'buff', false },
        { 'A', 'save_profile', '', true } })  -- in the order clicked
    eq(mine, settings.defaults())
    frame_with(on('UI / Log'))
    eq({ drew('WHM 75 / BLM 37'), drew('Running'), drew('Nothing sent yet.') }, { true, true, true })  -- its own status and log
    eq({ button('Action log##sk_log'), button('Japanese client##sk_japanese'), button('HP bar width##sk_ui_hp_width') },
       { false, false, false })  -- no action log switch; the HUD is its own
    frame_with({ close = 'Sidekick Settings: A###sk_settings_A' })
    eq(st.watching, {})
end)

test('your Sidekick Settings and another session\'s draw side by side, each its own profile name', function ()
    open_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    cfg.profiles.Mine = {}
    cfg.profile = 'Mine'
    st.views = { A = remote_view(settings.defaults()) }
    remote_calls = {}
    render(cfg, st, on('Profiles', { ['Save##sk_profile_save'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    eq({ begun('Sidekick Settings'), begun('Sidekick Settings: A###sk_settings_A') }, { true, true })
    eq(remote_calls, { { 'A', 'save_profile', '' } })  -- A's name field: blank, A has no profile loaded
    eq(cfg.profiles.Mine.heal ~= nil, true)  -- the click also landed in your own window: saved there under Mine
end)

test('another session\'s Sidekick Settings (/sk alt) show with the HUD, the widget and yours closed', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status({ open = false, watching = { A = true } })
    st.views = { A = remote_view(settings.defaults()) }
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ begun('Sidekick'), begun('SK Widget'), begun('Sidekick Settings'), begun('Sidekick Settings: A###sk_settings_A') },
       { false, false, false, true })
end)

test('a view that won\'t draw closes its window and is not shown again; the HUD comes back', function ()
    close_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    st.views = { A = { job = 'WHM 75', status = { state = 'Stopped' }, version = model.VIEW } }  -- broken: no sections
    local err = draw(window, cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq({ type(err), st.watching }, { 'string', {} })
    render(cfg, st, nil, model.build(snap(), cat, cfg, st, NAMES))
    eq(begun('Sidekick Settings: A###sk_settings_A'), false)
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
    eq({ drew('A runs another version of Sidekick: /addon reload sidekick there.'), button('##sk_page_Heal') },
       { true, false })
    st.watching = {}
end)

test('chips and Heal members send the state they\'re set to, here and to another session', function ()
    open_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    st.views = { A = remote_view(settings.defaults()) }
    remote_calls = {}
    render(cfg, st, on('Buff', { ['P1##buff_Protect1'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    render(cfg, st, on('Heal', { ['P1##sk_heal_1'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    eq({ cfg.rows.Protect.targets, cfg.heal.skip }, { { [0] = true, [1] = true }, { A = true } })
    eq(remote_calls, { { 'A', 'target', 'Protect', 1, true }, { 'A', 'skip', 'A', true } })
    st.watching = {}
    close_settings()
end)

test('a row hovered shows Combat then Idle after its name; a click sets one, the other goes, again clears it', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Buff'))
    eq({ button('Combat##buff_Haste_gate'), button('Idle##buff_Haste_gate') }, { false, false })  -- neither set: none
    render(cfg, st, on('Buff', { over = true }))
    eq({ button('Combat##buff_Haste_gate'), button('Idle##buff_Haste_gate') }, { true, true })
    local switch, scy = box('Haste##buff_Haste')
    local combat, ccy = box('Combat##buff_Haste_gate')
    local idle, icy = box('Idle##buff_Haste_gate')
    eq({ ccy, icy }, { scy, scy })  -- on the name's line
    eq(combat[1] < idle[1] and idle[1] + idle[3] < switch[1], true)
    eq(render(cfg, st, on('Buff', { over = true, ['Combat##buff_Haste_gate'] = true })), 1)
    eq({ cfg.gates, cfg.rows.Haste }, { { Haste = 'combat' }, nil })  -- no row made: Haste stays as it was
    eq(render(cfg, st, on('Buff', { over = true, ['Idle##buff_Haste_gate'] = true })), 1)
    eq(cfg.gates, { Haste = 'idle' })  -- one or the other, never both
    render(cfg, st, on('Buff', { over = true }))  -- the pointer still there: neither moved from under it
    eq({ box('Combat##buff_Haste_gate')[1], box('Idle##buff_Haste_gate')[1] }, { combat[1], idle[1] })
    eq(render(cfg, st, on('Buff', { over = true, ['Idle##buff_Haste_gate'] = true })), 1)  -- so a second click clears it
    eq(cfg.gates, {})
    render(cfg, st, on('Buff', { over = true, ['Idle##buff_Haste_gate'] = true }))
    render(cfg, st, on('Buff'))  -- the pointer gone: the one set alone, first; Haste off, dimmed as its name
    eq({ button('Combat##buff_Haste_gate'), button('Idle##buff_Haste_gate'), fill('Idle') },
       { false, true, u32(P.teal, 0.5) })
    eq(box('Idle##buff_Haste_gate')[1], combat[1])
    render(cfg, st, on('Buff', { over = true }))  -- back: the one set stays put, first, the other after it
    eq({ box('Idle##buff_Haste_gate')[1], box('Combat##buff_Haste_gate')[1] > combat[1] }, { combat[1], true })
    eq(render(cfg, st, on('Buff', { over = true, ['Idle##buff_Haste_gate'] = true })), 1)  -- clicked again: any time
    eq(cfg.gates, {})
    cfg.gates.Haste, cfg.rows.Haste = 'combat', { on = true }  -- on: lit
    render(cfg, st, on('Buff'))
    eq({ fill('Combat'), tipped('Only in combat'), tipped('Click again to let it go any time.') }, { u32(P.rose), true, true })
end)

test('a held row\'s long reason gives way, cut: its name stays, its gate pills keep clear of it', function ()
    open_settings()
    local sch = fake.catalog(20, 75, 5, 37, { 'Light Arts', 'Penury', 'Celerity', 'Accession', 'Perpetuance' })
    local cfg, st = settings.defaults(), status()
    cfg.rows.Protect = { on = true, targets = { [0] = true }, mods = { Perpetuance = true }, hold = true }
    local view = model.build(snap(), sch, cfg, st, NAMES)
    local avail
    for _, s in ipairs(view.sections) do
        for _, r in ipairs(s.id == 'buff' and s.rows or {}) do if r.key == 'Protect' then avail = r.avail end end
    end
    eq(avail:find('^waits for Perpetuance: ') ~= nil, true)
    render(cfg, st, on('Buff', { over = true }), view)
    local idle = box('Idle##buff_Protect_gate')
    local reason, name
    for _, d in ipairs(calls('AddText')) do
        local s = d.args[5]
        if s:find('^waits for') then reason = d end
        if s:find('^Prot') and math.abs(d.args[3][2] - idle[2]) < kit.S(12) then name = s end
    end
    eq({ reason.args[5] ~= avail, reason.args[3][1] > idle[1] + idle[3], name }, { true, true, 'Protect' })
end)

test('a row with a pick has its gate\'s pills on its name\'s line, not the drop-down\'s', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Buff', { over = true }))
    local switch, scy = box('Protect##buff_Protect')
    local pick, pcy = box('##pick_buff_Protect')
    local combat, ccy = box('Combat##buff_Protect_gate')
    local idle = box('Idle##buff_Protect_gate')
    eq({ ccy, ccy < pcy, idle[1] > combat[1], idle[1] + idle[3] < switch[1] }, { scy, true, true, true })
    eq(pick[3], kit.S(220))  -- the drop-down its full width (PICK_W), with nothing beside it
    eq(render(cfg, st, on('Buff', { over = true, ['Idle##buff_Protect_gate'] = true })), 1)
    eq(cfg.gates, { Protect = 'idle' })
end)

test('a gate built in shows its pill always, hovered or not, and nothing changes it; nor the other shows', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Buff'))
    eq({ button('Idle##buff_Sneak_gate'), fill('Idle') }, { true, u32(P.teal, 0.5) })  -- Sneak: out of combat, built in; off
    eq(render(cfg, st, on('Buff', { over = true, ['Idle##buff_Sneak_gate'] = true, ['Combat##buff_Sneak_gate'] = true })), 0)
    eq({ button('Idle##buff_Sneak_gate'), button('Combat##buff_Sneak_gate'), cfg.gates },
       { true, false, {} })
    eq(tipped('Built in: it only goes out of combat.'), true)
    render(cfg, st, on('Heal', { over = true }))
    eq({ button('Combat##heal_Drain_gate'), button('Idle##heal_Drain_gate') }, { true, false })  -- on the enemy: combat
    eq(tipped('Built in: it only goes in combat.'), true)
end)

test('Debuff removal\'s spells have a gate too, after the name by their checkbox; items theirs', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    render(cfg, st, on('Remove', { over = true }))
    local _, kcy = box('Erase##remove_with_Erase')
    local _, ccy = box('Combat##remove_Erase_gate')
    eq({ ccy, button('Idle##remove_Erase_gate'), button('Idle##remove_Echo Drops_gate') }, { kcy, true, true })
    eq(render(cfg, st, on('Remove', { over = true, ['Combat##remove_Erase_gate'] = true })), 1)
    eq(render(cfg, st, on('Remove', { over = true, ['Idle##remove_Echo Drops_gate'] = true })), 1)
    eq({ cfg.gates, cfg.rows.Erase, cfg.rows['Echo Drops'] }, { { Erase = 'combat', ['Echo Drops'] = 'idle' }, nil, nil })
    render(cfg, st, on('Remove', { over = true }))
    eq({ button('Combat##remove_paralysis_gate'), button('Idle##remove_*_paralysis_gate') }, { false, false })  -- a debuff: none
end)

test('another session\'s rows set its gate, to the state clicked', function ()
    open_settings()
    local cfg, st = settings.defaults(), remote_status({ watching = { A = true } })
    local theirs = settings.defaults()
    theirs.gates.Haste = 'combat'
    st.views = { A = remote_view(theirs) }
    remote_calls = {}
    render(cfg, st, on('Buff', { over = true, ['Idle##buff_Haste_gate'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    eq(cfg.gates, { Haste = 'idle' })  -- yours, with none set
    eq(remote_calls, { { 'A', 'gate', 'Haste', 'idle' } })  -- theirs, set to combat: to idle
    remote_calls = {}
    render(cfg, st, on('Buff', { over = true, ['Combat##buff_Haste_gate'] = true }), model.build(snap(), cat, cfg, st, NAMES))
    eq({ cfg.gates, remote_calls }, { { Haste = 'combat' }, { { 'A', 'gate', 'Haste', nil } } })  -- theirs cleared
    st.watching = {}
    close_settings()
end)

-- The fake measures 7 pixels a byte at 13 pixels: each cut below is the longest that fits.
test('the kit cuts text to fit with an ellipsis, never inside a character', function ()
    eq({ kit.fit('Kupipi', 42, 'font', 13), kit.fit('Kupipi', 41, 'font', 13) }, { 'Kupipi', 'Ku...' })
    eq({ kit.fit('a\195\169bc', 28, 'font', 13), kit.fit('\195\169a', 10, 'font', 13) }, { 'a...', '...' })
end)

test('a drop-down whose list raises closes every scope it opened, then raises the error', function ()
    frame = { stack = {}, vars = 0, texts = {}, ids = {}, args = {}, flags = {}, columns = {}, drawn = {}, extent = {},
              clicks = {}, window = 'T' }
    local ok, err = pcall(kit.dropdown, '##sk_t', 0, 10, 100, 'x', true, 1, function () error('boom', 0) end)
    eq({ ok, err, frame.stack, frame.vars }, { false, 'boom', {}, 0 })
end)

test('UI / Log: Drop-down rows sets how many choices a drop-down shows, held to its range', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render(cfg, st, on('UI / Log', { ['Drop-down rows##sk_ui_list_rows'] = 5 })), 1)
    eq(cfg.ui.list_rows, 5)
    close_settings()
    render(cfg, st)  -- taken up the next frame, before any window draws
    eq(kit.list_rows, 5)
    local function rows(n)
        cfg.ui.list_rows = n
        render(cfg, st)
        return kit.list_rows
    end
    eq({ rows(nil), rows(4), rows(500), rows(1), rows('what') }, { 8, 4, 30, 3, 8 })
end)

test('UI / Log: After zone stop (off by default) and Always load stopped (on) switch, each its own', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq({ cfg.ui.zone_stop, cfg.ui.load_stopped }, { false, true })
    eq(render(cfg, st, on('UI / Log', { ['After zone stop##sk_ui_zone_stop'] = true })), 1)
    eq({ cfg.ui.zone_stop, cfg.ui.load_stopped }, { true, true })
    eq(render(cfg, st, on('UI / Log', { ['Always load stopped##sk_ui_load_stopped'] = true })), 1)
    eq({ cfg.ui.zone_stop, cfg.ui.load_stopped, st.running }, { true, false, false })  -- neither starts or stops it
    cfg.ui.load_stopped = nil  -- a file from before it: on
    render(cfg, st, on('UI / Log', { ['Always load stopped##sk_ui_load_stopped'] = true }))
    eq(cfg.ui.load_stopped, false)
end)

-- `fn()` with the fake's `name` calls going to `handler`, and kit.list_rows and kit.custom put back after, a failure too.
local function with_handler(name, handler, fn)
    local real, rows, custom = handlers[name], kit.list_rows, kit.custom
    handlers[name] = handler
    local ok, err = pcall(fn)
    handlers[name], kit.list_rows, kit.custom = real, rows, custom
    if not ok then error(err, 0) end
end

local function bare_frame()
    frame = { stack = {}, vars = 0, texts = {}, ids = {}, args = {}, flags = {}, columns = {}, drawn = {}, extent = {},
              clicks = {}, window = 'T' }
end

test('a drop-down\'s list grows to kit.list_rows lines, in its own font or ImGui\'s, then scrolls', function ()
    local high
    with_handler('SetNextWindowSizeConstraints', function (_, max) high = max[2] end, function ()
        local function height(n, custom)
            kit.list_rows, kit.custom = n, custom
            bare_frame()
            kit.dropdown('##sk_rows', 0, 10, 100, 'x', true, 1, function () end)
            return high
        end
        -- kit.popup's top padding and spacing, the list ending half a spacing under its last line
        local pad, gap, line = kit.S(8), kit.S(6), kit.S(kit.BODY - 1)
        local tail = gap - math.floor(gap / 2)
        eq({ height(8, false), height(3, false) },
            { pad + 8 * 13 + 7 * gap + tail, pad + 3 * 13 + 2 * gap + tail })  -- the fake's 13px font
        eq(height(8, true), pad + 8 * line + 7 * gap + tail)  -- Segoe UI's, drawn at the size asked
        eq({ height(nil, false), height('x', false), height(99, false) },
            { height(8, false), height(8, false), height(30, false) })  -- a custom UI's bad value is held too
    end)
end)

test('the widget\'s profile menu is as tall as Drop-down rows, at the widget\'s size, then scrolls', function ()
    close_settings()
    local cfg, st = widget_cfg(), status()
    cfg.ui.list_rows = 4
    for i = 1, 12 do cfg.profiles['P' .. i] = { heal = {} } end
    local high
    with_handler('SetNextWindowSizeConstraints', function (_, max) high = max[2] end, function ()
        render(cfg, st, { mouse1 = true })
        render(cfg, st)
        eq(high, kit.list_height(4, 16))  -- (the fake's own font: its 13px, whatever the size asked)
        kit.custom = true
        eq(kit.list_height(4, 16) - kit.list_height(3, 16), 16 + kit.S(6))  -- a line of the widget's 16px a row
    end)
end)

test('a drop-down\'s list opens scrolled to its ticked choice, and only as it opens', function ()
    local scrolled, appearing = {}, true
    with_handler('SetScrollHereY', function (k) scrolled[#scrolled + 1] = k end, function ()
        with_handler('IsWindowAppearing', function () return appearing end, function ()
            bare_frame()
            kit.selectable('a', false)
            kit.selectable('b', true)
            appearing = false
            kit.selectable('b', true)
        end)
    end)
    eq(scrolled, { 0.5 })
end)

-- Last, as Segoe UI stays in once it's baked. The fake is ImGui 1.81, as Ashita 4.16's.
test('on ImGui 1.81 Segoe UI is added at load and drawn; a tooltip\'s is sized by its window\'s font scale', function ()
    close_settings()
    local added, real_open = {}, io.open
    handlers.AddFontFromFileTTF = function (path, px)
        local file = path:match('[^\\/]+$')
        added[#added + 1] = file .. ' ' .. px
        return file
    end
    rawset(io, 'open', function () return { close = function () end } end)  -- every face is there
    local ok, err = pcall(window.load)
    rawset(io, 'open', real_open)
    assert(ok, err)
    eq(added, { 'segoeui.ttf 18', 'seguisb.ttf 18', 'segoeuiz.ttf 18', 'seguisbi.ttf 18' })
    render(settings.defaults(), status())
    local faces = {}
    for _, d in ipairs(calls('AddText')) do
        if type(d.args[1]) == 'string' then faces[d.args[1]] = true end
    end
    eq({ kit.custom, faces['seguisb.ttf'], faces.font }, { true, true, nil }, 'the HUD drawn in Segoe semibold')
    eq(tipped('A\nHP 62%  MP 100%  TP 0  5.0y\nProtect\nShell'), true)
    local scales = frame.font_scales or {}
    eq({ has(scales, kit.S(kit.SMALL + 0.5) / 18), scales[#scales] }, { true, 1 }, 'its 18px bake scaled, then put back')
    eq(kit.fit('Kupipi', 41, 'font', 13), 'Ku...', 'no \226\128\166 in a Latin-1 bake')
end)

-- On a Japanese client ----------------------------------------------------------------------

local lang = require('core.lang')
local JA_FONTS = { text = 'meiryo.ttc', semi = 'meiryob.ttc', bold_italic = 'meiryob.ttc', semi_italic = 'meiryob.ttc' }
local JA_NAMES = { job = function (id) return ({ [3] = 'WHM', [4] = 'BLM', [10] = 'BRD', [13] = 'NIN', [17] = 'COR',
                       [18] = 'PUP', [19] = 'DNC', [20] = 'SCH', [21] = 'GEO', [22] = 'RUN', [9] = 'BST' })[id] end,
                   statuses = fake.res.statuses, spells = fake.res.spells, abilities = fake.res.abilities }

-- One frame of the standard window on a Japanese client, its Japanese faces in (as ImGui 1.92 adds them; a frame
-- before found them, so the view is built in Japanese): `list` a catalog for `main`/`sub`, the WHM/BLM one unless given.
local function render_ja(cfg, st, clicks, list, main, sub, over)
    cfg.ui.japanese, kit.ja, lang.drawable = true, JA_FONTS, true
    local g = snap()
    g.main, g.sub = main or g.main, sub or g.sub
    for k, v in pairs(over or {}) do g[k] = v end
    return render(cfg, st, clicks, model.build(g, list or cat, cfg, st, JA_NAMES))
end

-- The pages of a view, by their English names.
local function headers(view)
    local out, seen = {}, {}
    for _, s in ipairs(view.sections) do
        if not seen[s.header] then seen[s.header] = true; out[#out + 1] = s.header end
    end
    return out
end

test('on a Japanese client every page, tooltip and list is in Japanese, every job\'s too: no word is left English', function ()
    open_settings()
    lang.misses = {}
    local jobs = {
        { cat },
        { fake.catalog(3, 75, 4, 37, { 'Devotion' }) },
        { fake.catalog(10, 75, 3, 37, { 'Pianissimo', 'Nightingale', 'Troubadour' }), 10, 3 },
        { fake.catalog(17, 75, 13, 37, { 'Corsair\'s Roll', 'Chaos Roll', 'Double-Up', 'Fold', 'Snake Eye' }), 17, 13 },
        { fake.catalog(20, 75, 3, 37, { 'Light Arts', 'Dark Arts', 'Penury', 'Celerity', 'Accession', 'Addendum: White',
                                        'Sublimation', 'Rapture' }), 20, 3 },
        { fake.catalog(22, 75, 13, 37, { 'Ignis', 'Gelus', 'Flabra', 'Vallation', 'Valiance', 'Pflug', 'Embolden' }), 22, 13 },
        { fake.catalog(18, 75, 19, 37, { 'Fire Maneuver', 'Ice Maneuver', 'Repair', 'Maintenance', 'Deploy' }), 18, 19 },
        { fake.catalog(21, 75, 3, 37, { 'Full Circle', 'Entrust', 'Blaze of Glory', 'Radial Arcana' }), 21, 3 },
        { fake.catalog(9, 75, 3, 37, { 'Reward', 'Fight', 'Call Beast' }), 9, 3 },
    }
    local cfg = settings.defaults()
    cfg.ui.widget, cfg.heal.threshold, cfg.heal.focus_threshold = true, 40, 50  -- the notes under the heal lines too
    cfg.profiles.Healer, cfg.profile = {}, 'Healer'
    local st = status({ running = true, why = 'nothing to do', sessions = { Other = { running = true, halted = 'mounted',
        members = { { sid = 900, name = 'Other' } }, act = { behavior = 'buff', action = 'Haste', target = 'A' } } } })
    for _, j in ipairs(jobs) do
        local v = model.build(snap(), j[1], cfg, st, JA_NAMES)
        for _, page in ipairs(headers(v)) do
            render_ja(cfg, st, on(page), j[1], j[2], j[3], { safe = true, target = STRANGER })  -- Add Tracked, Track Stranger
            render_ja(cfg, status(), on(page), j[1], j[2], j[3])  -- stopped: what it would do
        end
    end
    eq(lang.misses, {})
    render_ja(cfg, st, on('Heal'), nil, nil, nil, { target = STRANGER })
    eq({ drew('回復ライン'), drew('Heal under'), drew('回復'), drew('白75/黒37'), drew('追跡に追加'), drew('Add Tracked') },
       { true, false, true, true, true, false })
    cfg.ui.japanese, cfg.ui.widget = false, false
end)

test('on a Japanese client UI / Log\'s HUD - Colors is in Japanese, its greyed Blend\'s note too', function ()
    open_settings()
    lang.misses = {}
    local cfg = settings.defaults()
    cfg.ui.sub_colors = false
    render_ja(cfg, status(), on('UI / Log'))
    eq({ lang.misses, drew('ジョブの色'), drew('斜め'), drew('Job colors') }, { {}, true, true, false })
    cfg.ui.japanese = false
end)

test('in Japanese each control keeps its English id: a click still sets its setting', function ()
    open_settings()
    local cfg, st = settings.defaults(), status()
    eq(render_ja(cfg, st, on('Heal', { ['Heal under##sk_heal_threshold'] = 60 })), 1)
    eq(render_ja(cfg, st, on('Buff', { ['Buffs##sk_on_buff'] = true })), 1)
    eq({ cfg.heal.threshold, cfg.buff.on }, { 60, false })
    eq(render_ja(cfg, st, on('Buff', { ['Lowest##sk_roll_risk_lowest'] = true }),
        fake.catalog(17, 75, 13, 37, { 'Corsair\'s Roll' }), 17, 13), 1)
    eq(cfg.roll.risk, 'lowest')
    eq(drew('最低'), true)
end)

test('in Japanese the HUD\'s tooltips and labels are Japanese, and a trust\'s name from the game is drawn as UTF-8', function ()
    close_settings()
    local cfg = settings.defaults()
    cfg.ui.japanese, kit.ja, lang.drawable = true, JA_FONTS, true
    local g = fake.snap({ { name = 'A', hpp = 62 }, { name = fake.sjis('クピピ'), kind = 'trust' } },
        { bt = { name = fake.sjis('ゴブリン'), hpp = 50, dist = 4.3 }, combat = true })
    render(cfg, status(), nil, model.build(g, cat, cfg, status(), JA_NAMES))
    eq({ fill('クピピ') ~= nil, tipped('クピピ (フェイス)'), tipped('ターゲット: ゴブリン  50%  4.3y') }, { true, true, true })
    eq(tipped('白75/黒37\n停止中: 予定: ケアルIV → A（回復: '), true)
    cfg.ui.japanese = false
    render(cfg, status(), nil, model.build(g, cat, cfg, status(), JA_NAMES))
    eq({ fill('クピピ') ~= nil, tipped('クピピ (trust)') }, { true, true })  -- in English too: the game's text, readable
end)

test('without a Japanese font (none in Windows, or in Ashita\'s boot config) the window stays English and UI / Log says why',
    function ()
    open_settings()
    local cfg = settings.defaults()
    cfg.ui.japanese, kit.ja = true, false
    render(cfg, status(), on('UI / Log'))
    eq({ lang.drawable, lang.on, drew('Japanese client'), drew('This window stays in English') }, { false, false, true, true })
    kit.ja = nil  -- the fake is ImGui 1.81, its fonts Ashita's own: no kana
    render(cfg, status(), on('UI / Log'))
    eq({ kit.ja, lang.drawable, drew('Ashita\'s boot config'), drew('couldn\'t be read') }, { false, false, true, false })
    local heal = model.build(snap(), cat, cfg, status(), JA_NAMES).sections[3]
    eq({ heal.id, heal.rows[1].label }, { 'heal', 'Cure' })  -- the next view, English
    cfg.ui.japanese = false
    render(cfg, status(), on('UI / Log'))
    eq({ lang.drawable, drew('This window stays in English') }, { true, false })
end)

-- A Japanese font as Ashita adds it from its boot config (`is_jp`): `size` pixels, with '→' and '…' when `full` (ImGui
-- 1.81's Japanese set has neither).
local function ja_face(size, full)
    local glyphs = { { Codepoint = 0x41 }, { Codepoint = 0x3042 }, { Codepoint = 0x56DE } }
    if full then glyphs[4], glyphs[5] = { Codepoint = 0x2192 }, { Codepoint = 0x2026 } end
    return { FontSize = size, Glyphs = glyphs }
end

test('on ImGui 1.81 the window is Japanese in the font Ashita\'s boot config added, scaled from its size', function ()
    open_settings()
    local cfg = settings.defaults()
    local text, bold = ja_face(14), ja_face(14)
    atlas, kit.ja, cfg.ui.japanese = { AGAVE, ja_face(32), text, bold }, nil, true  -- 14 is nearer the 18 baked
    render(cfg, status(), on('UI / Log'))
    eq({ kit.ja.text == text, kit.ja.semi == bold, kit.ja.size, lang.drawable }, { true, true, 14, true })
    render(cfg, status(), on('UI / Log'))
    eq({ kit.fonts.text == text, drew('日本語クライアント'), drew('This window stays in English') }, { true, true, false })
    eq({ drew('→'), drew('ケアルIV -> A') }, { false, true })  -- the last action sent, its arrow one the font has
    kit.push_font(kit.fonts.text, 28)
    eq(frame.font_scales[#frame.font_scales], 2)  -- 28 pixels from 14
    kit.pop_font()
    atlas, kit.ja = { AGAVE, ja_face(18, true) }, nil
    render(cfg, status(), on('UI / Log'))
    render(cfg, status(), on('UI / Log'))
    eq({ kit.ja.size, drew('ケアルIV → A') }, { 18, true })
    atlas, kit.ja = false, nil  -- a list Lua can't read: UI / Log says why
    render(cfg, status(), on('UI / Log'))
    eq({ kit.ja, lang.drawable, drew('Ashita\'s fonts couldn\'t be read') }, { false, false, true })
    atlas, kit.ja, kit.ja_error, cfg.ui.japanese = { AGAVE }, nil, nil, false
    render(cfg, status(), on('UI / Log'))
end)

test('the kit wraps Japanese between characters, never before closing punctuation nor after an opening bracket, and '
    .. 'keeps a line\'s spaces', function ()
    local s = '回復ラインが危険ライン以下です。効率回復はせず、危険時の回復だけを行います。'
    local lines = kit.wrap(s, 'font', 13, 21 * 10)  -- the fake measures 7 a byte: 10 characters a line
    eq(table.concat(lines), s)
    for _, l in ipairs(lines) do
        eq(kit.measure(l, 'font', 13) <= 21 * 10 or #l <= 6, true, l)
        eq(l:sub(1, 3) ~= '。' and l:sub(1, 3) ~= '、', true, l)
    end
    eq(#lines, 4)
    -- '（' would end the first line, ten characters long: it starts the next one, with what follows it
    eq(kit.wrap('あいうえおかきくけ（こさしすせそ）', 'font', 13, 21 * 10), { 'あいうえおかきくけ', '（こさしすせそ）' })
    eq(kit.wrap('HP 62%  MP 100%', 'font', 13, 500), { 'HP 62%  MP 100%' })
    eq(kit.wrap('Roll 2 is Roll 1: one roll kept up', 'font', 13, 7 * 12), { 'Roll 2 is', 'Roll 1: one', 'roll kept up' })
end)

test('in Japanese a row\'s Combat and Idle are Japanese, their ids English: a click still sets the gate', function ()
    open_settings()
    lang.misses = {}
    local cfg, st = settings.defaults(), status()
    eq(render_ja(cfg, st, on('Buff', { over = true, ['Combat##buff_Haste_gate'] = true })), 1)
    render_ja(cfg, st, on('Remove', { over = true }))
    render_ja(cfg, st, on('Heal', { over = true }))
    eq({ cfg.gates, lang.misses }, { { Haste = 'combat' }, {} })
    render_ja(cfg, st, on('Buff', { over = true }))
    eq({ drew('戦闘中'), drew('戦闘外'), drew('Combat'), drew('Idle') }, { true, true, false, false })  -- not the rune set's 通常時
    cfg.ui.japanese = false
end)
