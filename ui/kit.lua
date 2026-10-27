--[[
    The look the standard UI's windows share, after VanaCore's /vana window
    (docs/vana-ui-style.md): one palette, sizes through S(), every control drawn
    on ImGui's draw lists over an invisible button, its states eased.

    Based on VanaCore's addons/vanacore/vana/draw.lua, Copyright (C) 2026 Vekien
    (GPL-3.0-or-later), adapted for Sidekick3 from 2026-10-19. Sidekick3 is
    GPL-3.0-or-later too (LICENSE); VanaCore's name and logo aren't licensed with it.

    A control takes its value and returns the new one and whether it changed; it
    reads and writes no setting. Text is Segoe UI, added once at load (kit.bake):
    under ImGui 1.92 (Ashita 4.30's libs, as VanaCore gives them) drawn at any size,
    on 1.81 (Ashita 4.16) from its 18px bake, scaled. Without the font files it's
    ImGui's own font, scaled. Draw-list text is drawn as is: no '%' doubling.
    Japanese (kit.frame's `japanese`) is Meiryo, else Yu Gothic or MS Gothic, as
    VanaCore's own Japanese windows: on 1.92 added the first frame it's wanted. 1.81
    takes no font mid-frame, nor any kanji unless asked for them when the font is
    added: there it's the Japanese font Ashita added at its start, from its boot
    config ([ashita.imgui.fonts] with `is_jp`), scaled from its size. Where there's
    none, core/lang.lua is told (lang.drawable) and the UI stays English.
]]--

local imgui = require('imgui')
local lang = require('core.lang')
local util = require('core.util')

local kit = {}

kit.P = {
    bg = '#161822', side = '#10121A', border = '#2A2E3E', line = '#242838', hover = '#1F2334',
    well = '#0E1017', well_edge = '#272B3C', field = '#080A10', field_edge = '#3E4460', popup = '#0F1118',
    white = '#FFFFFF', text = '#E8EAF1', text2 = '#BDC1D0', dim = '#7B8095', faint = '#4E536A',
    accent = '#7AA2F7', accent2 = '#A9C1FF', accent_lo = '#3E5CB3', accent_bg = '#1B2340',
    teal = '#5FD3B3', amber = '#E8B45C', rose = '#EE6F78', rose_bg = '#3A2026',
    knob = '#F2F3F8', off = '#2B2F42', seg = '#313752', ink = '#0B1020',
    hp = '#EE6F78', mp = '#E8B45C',  -- the HUD's bars: the mockup's red and yellow, from the palette,
    tp = '#5FD3B3',                  -- and TP in its teal, as what is ready
    track = '#808080',               -- each HUD bar's background, at 70%, not faded with the panel
    yellow = '#E8C84A', orange = '#E8883A', red = '#E8454E',  -- a name on an HP bar, at 75%, 50% and 25%
    go = '#2F9E68', halt = '#C23B45', held = '#3E5CB3',  -- the widget's pill round a character: running, stopped,
                                                        -- running but held (asleep, mounted, zoning...)
}
local P = kit.P

kit.BODY, kit.SMALL = 16, 13.5  -- the text sizes, unscaled
kit.SW_W, kit.SW_H = 32, 17     -- a switch

local VERSION = tonumber(IMGUI_VERSION_NUM) or 0
kit.dynamic = VERSION >= 19200  -- fonts added while running, drawn at any size
local CHILD_FLAGS = VERSION >= 19000  -- BeginChild's third argument: child flags, no longer a border bool
-- ImDrawFlags (1.92) or ImDrawCornerFlags (1.81): nil rounds every corner
kit.LEFT_CORNERS = ImDrawFlags_RoundCornersLeft or ImDrawCornerFlags_Left

-- Colours --------------------------------------------------------------------------

-- '#RRGGBB' as its red, green and blue, 0 to 255.
local function rgb(hex) return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16) end

-- '#RRGGBB' and an alpha to an ImU32 (0xAABBGGRR), for a draw list.
function kit.u32(hex, alpha)
    local r, g, b = rgb(hex)
    local a = util.round(util.clamp(alpha or 1, 0, 1) * 255)
    return ((a * 256 + b) * 256 + g) * 256 + r
end

-- '#RRGGBB' and an alpha to { r, g, b, a }, for PushStyleColor.
function kit.rgba(hex, alpha)
    local r, g, b = rgb(hex)
    return { r / 255, g / 255, b / 255, alpha or 1 }
end

local function lerp(x, y, t) return util.round(x + (y - x) * t) end

-- The colour `t` of the way from `a` to `b`.
function kit.mix(a, b, t)
    t = util.clamp(t, 0, 1)
    local r1, g1, b1 = rgb(a)
    local r2, g2, b2 = rgb(b)
    return ('#%02X%02X%02X'):format(lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t))
end
local mix = kit.mix

-- Scale ----------------------------------------------------------------------------

kit.scale = 1
function kit.S(n) return util.round(n * kit.scale) end
local S = kit.S

-- The screen's size, 1920 by 1080 until ImGui says.
function kit.screen()
    local ok, d = pcall(function () return imgui.GetIO().DisplaySize end)
    local w, h = ok and d and tonumber(d.x), ok and d and tonumber(d.y)
    if not (w and h and w > 0 and h > 0) then return 1920, 1080 end
    return w, h
end

-- 1440 pixels tall is 1.1 (0.825 to 1.76 across screens), times the user's own (0.5 to 2).
local function set_scale(user)
    local _, h = kit.screen()
    kit.scale = util.clamp(h / 1440, 0.75, 1.6) * 1.1 * util.clamp(user or 1, 0.5, 2)
end

-- Fonts and text -------------------------------------------------------------------

kit.fonts = {}      -- text, semi, bold_italic, semi_italic: the faces drawn now, the language's (kit.frame)
kit.custom = false  -- they're ours (Segoe UI, or the Japanese faces): measured and drawn at the size asked
kit.ja = nil        -- the Japanese faces once added (or found); false when there are none
kit.ja_error = nil  -- why Ashita's fonts couldn't be read (1.81), for UI / Log
local latin = nil   -- Segoe UI's faces once added
local fonts_tried, fonts_pending, ja_pending = false, nil, nil
local BAKE = 18     -- the size each face is added at; 1.81 scales it to the size asked
local baked, plain = BAKE, nil  -- the faces drawn now: their size, and what of PLAIN they lack (a set's `size`, `plain`)
-- Characters ImGui 1.81's Japanese set lacks, written as these where a face has no glyph for them.
local PLAIN = { { 0x2192, '→', '->' }, { 0x2026, '…', '...' } }
-- The same four faces Tracker loads. Each falls back to the one named last.
local FACES = {
    { 'text', 'segoeui.ttf' }, { 'semi', 'seguisb.ttf', 'text' },
    { 'bold_italic', 'segoeuiz.ttf', 'semi' }, { 'semi_italic', 'seguisbi.ttf', 'semi' },
}
-- Japanese: one family with the kana and kanji, its bold for every face but the text (Japanese has no italic), the
-- first of these Windows has. 1.92 adds each glyph as it's drawn, so no ranges are given.
local JA_FAMILIES = { { 'meiryo.ttc', 'meiryob.ttc' }, { 'YuGothM.ttc', 'YuGothB.ttc' }, { 'msgothic.ttc' } }

local function fonts_dir() return ((os.getenv and os.getenv('WINDIR')) or 'C:\\Windows') .. '\\Fonts\\' end

-- The font file `name` in Windows' fonts added at BAKE, or nil.
local function add_font(name)
    local path = fonts_dir() .. name
    local file = io.open(path, 'rb')
    if not file then return nil end
    file:close()
    local ok, font = pcall(imgui.AddFontFromFileTTF, path, BAKE)
    return ok and font or nil
end

-- Segoe UI from Windows' fonts, each face falling back to the one before; nil without the regular.
local function load_fonts()
    local out = {}
    for _, face in ipairs(FACES) do
        out[face[1]] = add_font(face[2]) or out[face[3]]
    end
    return out.text and out or nil
end

-- The first Japanese family Windows has: { text, semi, bold_italic, semi_italic }; nil with none.
local function load_japanese()
    for _, family in ipairs(JA_FAMILIES) do
        local text = add_font(family[1])
        if text then
            local bold = family[2] and add_font(family[2]) or text
            return { text = text, semi = bold, bold_italic = bold, semi_italic = bold }
        end
    end
end

-- On 1.81, the Japanese faces Ashita added at its start, known by their kana: of those nearest BAKE in size, the
-- first for the text and the next for the bold, with their `size` and what of PLAIN they lack (`plain`); nil with none.
local function ashita_japanese()
    local ok, faces = pcall(function ()
        local out, fonts = {}, imgui.GetIO().Fonts.Fonts
        for i = 1, #fonts do
            local f = fonts[i]
            local glyphs, has = f.Glyphs, {}
            for j = 1, #glyphs do has[glyphs[j].Codepoint] = true end
            if has[0x3042] then out[#out + 1] = { font = f, size = f.FontSize, has = has } end  -- 'あ'
        end
        return out
    end)
    if not ok then kit.ja_error = tostring(faces) end
    if not ok or not faces[1] then return nil end
    local size = faces[1].size
    for _, f in ipairs(faces) do
        if math.abs(f.size - BAKE) < math.abs(size - BAKE) then size = f.size end
    end
    local at = {}
    for _, f in ipairs(faces) do
        if f.size == size then at[#at + 1] = f end
    end
    local lacks = {}
    for _, p in ipairs(PLAIN) do
        if not at[1].has[p[1]] then lacks[#lacks + 1] = p end
    end
    local text, bold = at[1].font, (at[2] or at[1]).font
    return { text = text, semi = bold, bold_italic = bold, semi_italic = bold, size = size, plain = lacks[1] and lacks }
end

-- `s` as the faces drawn now can draw it: what they lack of PLAIN written in its stead.
local function spelt(s)
    if not plain or type(s) ~= 'string' or not s:find('\226', 1, true) then return s end  -- (PLAIN's all start so)
    for _, p in ipairs(plain) do s = s:gsub(p[2], p[3]) end
    return s
end

-- Segoe UI, once, from Sidekick's load event (window.load): outside any frame, as ImGui 1.81 locks its font atlas
-- while one is drawn. 1.92 takes a font mid-frame too (kit.frame adds it then for a UI with no load). The faces are
-- drawn from the next kit.frame.
function kit.bake()
    if fonts_tried then return end
    fonts_tried = true
    fonts_pending = load_fonts()
end

-- `font` (one of kit.fonts) at `px` for ImGui's own items until kit.pop_font (a popup's, a tooltip's, a text field's);
-- nothing until Segoe UI is in. 1.81's PushFont takes no size: the face goes on at its bake and the window's font scale
-- makes up the rest. Nothing else here sets that scale, so the pop puts back 1.
function kit.push_font(font, px)
    if not kit.custom then return end
    if kit.dynamic then
        imgui.PushFont(font, px)
    else
        imgui.PushFont(font)
        imgui.SetWindowFontScale(px / baked)
    end
end

function kit.pop_font()
    if not kit.custom then return end
    if not kit.dynamic then imgui.SetWindowFontScale(1) end
    imgui.PopFont()
end

local measured, measured_n = {}, 0

-- `s` drawn in `font` at `px` pixels: its width and height. Cached, as the same labels are measured every frame.
function kit.measure(s, font, px)
    s = tostring(s)
    local key = tostring(font) .. '|' .. px .. '|' .. s
    local m = measured[key]
    if not m then
        if measured_n > 4000 then measured, measured_n = {}, 0 end  -- live values keep adding strings
        s = spelt(s)
        local w, h
        if kit.custom and kit.dynamic then
            imgui.PushFont(font, px)
            w, h = imgui.CalcTextSize(s)
            imgui.PopFont()
        else
            if kit.custom then imgui.PushFont(font) end  -- 1.81: at its bake
            w, h = imgui.CalcTextSize(s)  -- at the font's own size
            local k = px / imgui.GetFontSize()
            if kit.custom then imgui.PopFont() end
            w, h = w * k, h * k
        end
        m = { w, h }
        measured[key], measured_n = m, measured_n + 1
    end
    return m[1], m[2]
end
local measure = kit.measure

-- Segoe UI's line holds a tall ascent and a descent: centred by its box, its letters sit low.
local function lift(h) return kit.custom and util.round(h * 0.06) or 0 end

function kit.text(dl, x, y, s, color, font, px, alpha)
    dl:AddText(font, px, { util.round(x), util.round(y) }, kit.u32(color, alpha), spelt(s))
end
local text = kit.text

-- Text with its middle at cy, `align` of its width left of x: 0 from x, 1 ending there, 0.5 centred on it.
local function aligned(dl, x, cy, s, color, font, px, alpha, align)
    local w, h = measure(s, font, px)
    text(dl, x - w * align, cy - h / 2 - lift(h), s, color, font, px, alpha)
end

-- Text with its middle at cy: from x, ending at `right`, or centred on cx.
function kit.text_mid(dl, x, cy, s, color, font, px, alpha) aligned(dl, x, cy, s, color, font, px, alpha, 0) end
function kit.text_right(dl, right, cy, s, color, font, px, alpha) aligned(dl, right, cy, s, color, font, px, alpha, 1) end
function kit.text_centred(dl, cx, cy, s, color, font, px, alpha) aligned(dl, cx, cy, s, color, font, px, alpha, 0.5) end

-- Capitals one glyph at a time, `spacing` pixels apart (ImGui has no tracking).
-- Tracker's section headers. Returns the width. `dl` nil only measures.
function kit.text_spaced(dl, x, cy, s, color, font, px, spacing, alpha)
    s, spacing = tostring(s or ''), spacing or 0
    local start, i, n = x, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
        local letter = s:sub(i, i + len - 1)
        if dl then kit.text_mid(dl, x, cy, letter, color, font, px, alpha) end
        x = x + measure(letter, font, px) + spacing
        i = i + len
    end
    if x == start then return 0 end
    return x - start - spacing
end

-- Text over the game or a bar: stamped in black a pixel out each way first, so it reads on anything.
local AROUND = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }
function kit.halo(dl, x, y, s, color, font, px, alpha)
    x, y, s = util.round(x), util.round(y), spelt(s)
    local dark = kit.u32('#000000', 0.85 * (alpha or 1))
    for _, o in ipairs(AROUND) do dl:AddText(font, px, { x + o[1], y + o[2] }, dark, s) end
    dl:AddText(font, px, { x, y }, kit.u32(color, alpha), s)
end

-- `s` cut to `room` pixels, with an ellipsis; never inside a UTF-8 character.
function kit.fit(s, room, font, px)
    s = tostring(s)
    if measure(s, font, px) <= room then return s end
    local dots = kit.custom and kit.dynamic and '…' or '...'  -- 1.81 bakes Latin-1 alone: no '…'
    local n = #s
    repeat
        n = n - 1
        while n > 0 and (s:byte(n + 1) or 0) >= 0x80 and (s:byte(n + 1) or 0) < 0xC0 do n = n - 1 end
    until n <= 0 or measure(s:sub(1, n) .. dots, font, px) <= room
    return s:sub(1, n) .. dots
end

-- Punctuation a line never starts with (Japanese breaks between any two characters, but not before these).
local CLOSING = { ['、'] = true, ['。'] = true, ['，'] = true, ['．'] = true, ['）'] = true, ['」'] = true, ['』'] = true,
                  ['！'] = true, ['？'] = true, ['ー'] = true, ['・'] = true, ['：'] = true, ['％'] = true }

-- A line's pieces, each a place it may break before: a word (the spaces before it its `gap`, kept unless the line
-- breaks there), or a character of Japanese (from U+3000, three bytes of UTF-8), which closing punctuation joins.
local function pieces(para)
    local out, i, n, gap = {}, 1, #para, ''
    while i <= n do
        local b = para:byte(i)
        if b == 32 then
            gap, i = gap .. ' ', i + 1
        elseif b >= 0xE3 and b <= 0xEF then
            local c = para:sub(i, i + 2)
            if CLOSING[c] and out[1] and gap == '' then out[#out].s = out[#out].s .. c
            else out[#out + 1] = { s = c, gap = gap } end
            gap, i = '', i + 3
        else
            local j = i
            while j <= n do
                local c = para:byte(j)
                if c == 32 or c >= 0xE3 and c <= 0xEF then break end
                j = j + 1
            end
            out[#out + 1] = { s = para:sub(i, j - 1), gap = gap }
            gap, i = '', j
        end
    end
    return out
end

-- `s` broken into lines, each as long as `fits(line)` allows, at its spaces or between Japanese characters (its own
-- lines kept, as they are when they fit). A piece longer than a line stands alone.
local function broken(s, fits)
    local lines = {}
    for para in (tostring(s) .. '\n'):gmatch('(.-)\n') do
        if fits(para) then
            lines[#lines + 1] = para
        else
            local cur = ''
            for _, p in ipairs(pieces(para)) do
                local try = cur == '' and p.s or cur .. p.gap .. p.s
                if cur ~= '' and not fits(try) then
                    lines[#lines + 1], cur = cur, p.s
                else
                    cur = try
                end
            end
            lines[#lines + 1] = cur
        end
    end
    return lines
end

-- `s` broken into lines `width` pixels wide.
function kit.wrap(s, font, px, width)
    return broken(s, function (line) return measure(line, font, px) <= width end)
end

-- Shapes ---------------------------------------------------------------------------

-- (corners nil rounds all four: it isn't passed, as 1.81 reads 0 as none and 1.92 as all.)
function kit.fill(dl, x, y, w, h, color, r, alpha, corners)
    local a, b, c = { x, y }, { x + w, y + h }, kit.u32(color, alpha)
    if corners then dl:AddRectFilled(a, b, c, r or 0, corners) else dl:AddRectFilled(a, b, c, r or 0) end
end
local fill = kit.fill

function kit.outline(dl, x, y, w, h, color, r, alpha, thickness)
    local col, rad = kit.u32(color, alpha), r or 0
    if thickness and thickness ~= 1 then
        -- Thickness is the last argument, so the corner flags have to be passed too. 0 squares the corners on 1.81.
        local corners = ImDrawFlags_RoundCornersAll or ImDrawCornerFlags_All
        dl:AddRect({ x, y }, { x + w, y + h }, col, rad, corners, thickness)
    else
        dl:AddRect({ x, y }, { x + w, y + h }, col, rad)
    end
end
local outline = kit.outline

function kit.circle(dl, cx, cy, r, color, alpha) dl:AddCircleFilled({ cx, cy }, r, kit.u32(color, alpha), 24) end
function kit.ring(dl, cx, cy, r, color, alpha) dl:AddCircle({ cx, cy }, r, kit.u32(color, alpha), 24) end

function kit.line(dl, x1, y1, x2, y2, color, alpha, thickness)
    dl:AddLine({ x1, y1 }, { x2, y2 }, kit.u32(color, alpha), thickness or 1)
end

-- A filled triangle, wound clockwise on screen as ImGui's anti-aliasing expects.
function kit.tri(dl, a, b, c, color, alpha)
    if (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) < 0 then b, c = c, b end
    dl:AddTriangleFilled(a, b, c, kit.u32(color, alpha))
end

-- An icon `size` across centred on (cx, cy), drawn in shapes so no font has to carry it: 'close', 'play', 'stop',
-- 'cog' (its hole in `cut`), 'down', 'right', 'check'. In a 24-unit box.
function kit.icon(dl, name, cx, cy, size, color, alpha, cut)
    local k = size / 24
    local function p(x, y) return { cx + (x - 12) * k, cy + (y - 12) * k } end
    local col, t = kit.u32(color, alpha), math.max(1, 2 * k)
    if name == 'close' then
        dl:AddLine(p(6, 6), p(18, 18), col, t)
        dl:AddLine(p(18, 6), p(6, 18), col, t)
    elseif name == 'play' then
        kit.tri(dl, p(8, 5), p(19, 12), p(8, 19), color, alpha)
    elseif name == 'stop' then
        dl:AddRectFilled(p(6, 6), p(18, 18), col, 2 * k)
    elseif name == 'cog' then
        -- eight teeth, one straight up: trapezoids from radius 7 to 12, round a body of 9 with a hole of 4
        dl:AddCircleFilled({ cx, cy }, 9 * k, col, 24)
        for i = 0, 7 do
            local a = i * math.pi / 4
            local dx, dy = math.sin(a), -math.cos(a)
            local function q(r, w) return { cx + (dx * r - dy * w) * k, cy + (dy * r + dx * w) * k } end
            local b1, b2, t1, t2 = q(7, -2.8), q(7, 2.8), q(12, -2.2), q(12, 2.2)
            kit.tri(dl, b1, b2, t2, color, alpha)
            kit.tri(dl, b1, t2, t1, color, alpha)
        end
        dl:AddCircleFilled({ cx, cy }, 4 * k, kit.u32(cut or P.bg), 24)
    elseif name == 'down' then
        dl:AddLine(p(5, 9), p(12, 16), col, t)
        dl:AddLine(p(12, 16), p(19, 9), col, t)
    elseif name == 'right' then
        dl:AddLine(p(9, 5), p(16, 12), col, t)
        dl:AddLine(p(16, 12), p(9, 19), col, t)
    elseif name == 'check' then
        dl:AddLine(p(5, 12), p(10, 17), col, t)
        dl:AddLine(p(10, 17), p(19, 7), col, t)
    end
end

-- Frames, easing and the mouse ------------------------------------------------------

kit.clock = os.clock  -- (the tests step it, so every eased value lands at once)
kit.prefix = ''       -- each window's own: two windows drawing one control keep their own eased state
local anim, last, dt = {}, nil, 0

-- The Japanese faces, the first frame they're wanted: on 1.92 added now, drawn from the next frame; on 1.81 Ashita's,
-- drawn from now. None (kit.ja false) without a Japanese font: in Windows on 1.92, in Ashita's boot config on 1.81.
local function want_japanese()
    if ja_pending ~= nil or kit.ja ~= nil then return end
    if kit.dynamic then
        ja_pending = load_japanese()
        if not ja_pending then kit.ja = false end
    else
        kit.ja = ashita_japanese() or false
    end
end

-- Once a frame, before any window: the time since the last, the fonts for the language (`japanese`), the scale
-- (`user`, 1 for 100%).
function kit.frame(user, japanese)
    local now = kit.clock()
    dt = last and util.clamp(now - last, 0, 0.1) or 0  -- capped: a hitch takes one step, not a jump
    last = now
    if fonts_pending then latin, fonts_pending = fonts_pending, nil  -- added before this frame: usable from it
    elseif not latin and kit.dynamic then kit.bake() end
    if ja_pending then kit.ja, ja_pending = ja_pending, nil end
    if japanese then want_japanese() end
    local set = japanese and kit.ja or latin
    if set then
        kit.fonts.text, kit.fonts.semi, kit.fonts.bold_italic, kit.fonts.semi_italic =
            set.text, set.semi, set.bold_italic, set.semi_italic
    else
        local f = imgui.GetFont()
        kit.fonts.text, kit.fonts.semi, kit.fonts.bold_italic, kit.fonts.semi_italic = f, f, f, f
    end
    kit.custom = set ~= nil
    baked, plain = set and set.size or BAKE, set and set.plain or nil
    lang.drawable = not japanese or kit.ja ~= false  -- (still on while the faces are added)
    set_scale(user)
    kit.tooltips()  -- one a UI left asked for last frame, a frame late
end

-- `id`'s value moved towards `target` a share of the way each frame (`speed` a second: 18 lands in about a sixth).
function kit.ease(id, target, speed)
    id = kit.prefix .. id
    local v = anim[id]
    if v == nil then
        v = target  -- a new control starts where it should be
    else
        v = v + (target - v) * math.min(1, dt * (speed or 18))
        if math.abs(v - target) < 0.003 then v = target end
    end
    anim[id] = v
    return v
end
local ease = kit.ease

-- The input half of every control: an invisible button over its box. Hovered, clicked, held.
function kit.hit(id, x, y, w, h)
    imgui.SetCursorScreenPos({ x, y })
    local clicked = imgui.InvisibleButton(id, { math.max(1, w), math.max(1, h) })
    return imgui.IsItemHovered(), clicked, imgui.IsItemActive()
end
local hit = kit.hit

-- The mouse over a box of this window, with no item made for it.
function kit.over(x, y, w, h)
    return imgui.IsWindowHovered() and imgui.IsMouseHoveringRect({ x, y }, { x + w, y + h })
end

function kit.esc(s) return (tostring(s):gsub('%%', '%%%%')) end

-- How wide `s` is in columns: a Japanese character two (it's drawn twice as wide), any other one.
local function columns(s)
    local _, wide = s:gsub('[\227-\239][\128-\191][\128-\191]', '')
    local _, others = s:gsub('[^\128-\191]', '')
    return others + wide
end

-- Lines past `n` columns broken at a space, or between Japanese characters.
local function wrap_chars(s, n)
    return table.concat(broken(s, function (line) return columns(line) <= n end), '\n')
end

-- ImGui style `colours` ({ { ImGuiCol_*, rgba }, ... }) pushed, then each ImGuiStyleVar_* after them with its value
-- (no list built: this runs every frame). Returns how many vars, which kit.pop_style takes with the same colours.
function kit.push_style(colours, ...)
    for _, c in ipairs(colours) do imgui.PushStyleColor(c[1], c[2]) end
    local n = select('#', ...)
    assert(n % 2 == 0, 'push_style: every var needs its value')
    for i = 1, n, 2 do
        local var, value = select(i, ...)
        imgui.PushStyleVar(var, value)
    end
    return n / 2
end

function kit.pop_style(colours, vars)
    if vars > 0 then imgui.PopStyleVar(vars) end
    if #colours > 0 then imgui.PopStyleColor(#colours) end
end

local TOOLTIP_COLOURS = { { ImGuiCol_PopupBg, kit.rgba(P.popup, 0.97) }, { ImGuiCol_Border, kit.rgba(P.border) },
                          { ImGuiCol_Text, kit.rgba(P.text) } }

local tip_pending  -- the tooltip asked for last this frame, for kit.tooltips

-- A tooltip by the mouse. Only the last asked for in a frame shows, as with SetTooltip (BeginTooltip would stack
-- them all): kit.tooltips draws it once the windows are, or the next kit.frame does.
function kit.tooltip(s)
    if s and s ~= '' then tip_pending = tostring(s) end
end

-- Once a frame, after every window: the tooltip asked for last, in the palette, wrapped, drawn as is
-- (TextUnformatted: no '%' doubling). Its font goes on inside it, as 1.81 sizes a font by the window it's in.
-- (1.92's BeginTooltip says whether to draw; 1.81's says nothing.)
function kit.tooltips()
    local s = tip_pending
    if not s then return end
    tip_pending = nil
    local vars = kit.push_style(TOOLTIP_COLOURS, ImGuiStyleVar_WindowPadding, { S(9), S(6) }, ImGuiStyleVar_WindowRounding,
        S(4), ImGuiStyleVar_PopupRounding, S(4), ImGuiStyleVar_PopupBorderSize, 1)
    if imgui.BeginTooltip() ~= false then
        kit.push_font(kit.fonts.text, S(kit.SMALL + 0.5))
        imgui.TextUnformatted(spelt(wrap_chars(s, 72)))
        kit.pop_font()
        imgui.EndTooltip()
    end
    kit.pop_style(TOOLTIP_COLOURS, vars)
end

-- The last item's tooltip, while it's hovered.
function kit.tip(s)
    if s and s ~= '' and imgui.IsItemHovered() then kit.tooltip(s) end
end

local POPUP_COLOURS = {
    { ImGuiCol_PopupBg, kit.rgba(P.popup) }, { ImGuiCol_Border, kit.rgba(P.border) }, { ImGuiCol_Text, kit.rgba(P.text) },
    { ImGuiCol_Header, kit.rgba(P.accent_bg) }, { ImGuiCol_HeaderHovered, kit.rgba(P.hover) },
    { ImGuiCol_HeaderActive, kit.rgba(P.accent_lo) }, { ImGuiCol_Separator, kit.rgba(P.line) },
    { ImGuiCol_FrameBg, kit.rgba(P.well) }, { ImGuiCol_FrameBgHovered, kit.rgba(P.well) }, { ImGuiCol_FrameBgActive, kit.rgba(P.well) },
}

-- ImGui's popup `id` (a drop-down's list, a typed number), in the palette with the padding the windows here
-- take away and its text at `px`, `body()` inside it while it's open. A Lua error in `body` still closes every
-- scope it opened (ImGui asserts on one left open), then is raised again.
function kit.popup(id, px, body)
    local vars = kit.push_style(POPUP_COLOURS, ImGuiStyleVar_WindowPadding, { S(10), S(8) }, ImGuiStyleVar_PopupRounding,
        S(5), ImGuiStyleVar_PopupBorderSize, 1, ImGuiStyleVar_FramePadding, { S(8), S(4) }, ImGuiStyleVar_FrameRounding, S(4),
        ImGuiStyleVar_ItemSpacing, { S(8), S(6) })
    local open, ok, err = imgui.BeginPopup(id), true, nil
    if open then
        kit.push_font(kit.fonts.text, px)
        ok, err = pcall(body)
        kit.pop_font()
        imgui.EndPopup()
    end
    kit.pop_style(POPUP_COLOURS, vars)
    if not ok then error(err, 0) end
    return open
end

-- A child window `w` by `h` at the cursor, scrolling its own items (EndChild after, whatever it returns).
function kit.child(id, w, h)
    if CHILD_FLAGS then return imgui.BeginChild(id, { w, h }, 0, ImGuiWindowFlags_NoNavInputs) end
    return imgui.BeginChild(id, { w, h }, false, ImGuiWindowFlags_NoNavInputs)
end

-- Controls: each centred on cy; `enabled` false draws it at 0.4 and takes no click ----

local function faded(enabled, alpha) return (enabled == false and 0.4 or 1) * (alpha or 1) end

-- A switch, kit.SW_W by kit.SW_H. Returns on, changed.
function kit.switch(id, x, cy, on, enabled, alpha)
    local w, h = S(kit.SW_W), S(kit.SW_H)
    local y = cy - h / 2
    local hovered, clicked = hit(id, x, y, w, h)
    local changed = clicked and enabled ~= false
    if changed then on = not on end
    local t, a = ease(id, on and 1 or 0), faded(enabled, alpha)
    local dl = imgui.GetWindowDrawList()
    fill(dl, x, y, w, h, mix(P.off, P.accent, t), h / 2, a)
    if hovered and enabled ~= false then fill(dl, x, y, w, h, '#FFFFFF', h / 2, 0.08 * a) end
    local r = (h - S(4)) / 2
    kit.circle(dl, x + S(2) + r + (w - S(4) - r * 2) * t, cy, r, P.knob, a)
    return on, changed == true
end

-- A checkbox, kit.CB by kit.CB, its left edge at x: the accent with a tick when on, a sunken box when off.
-- Returns on, changed.
kit.CB = 16
function kit.checkbox(id, x, cy, on, enabled, alpha)
    local s = S(kit.CB)
    local y = cy - s / 2
    local hovered, clicked = hit(id, x, y, s, s)
    local changed = clicked and enabled ~= false
    if changed then on = not on end
    local t, a = ease(id, on and 1 or 0), faded(enabled, alpha)
    local dl = imgui.GetWindowDrawList()
    fill(dl, x, y, s, s, mix(P.well, P.accent, t), S(3), a)
    outline(dl, x, y, s, s, mix(P.well_edge, P.accent, t), S(3), a)
    if hovered and enabled ~= false then fill(dl, x, y, s, s, '#FFFFFF', S(3), 0.08 * a) end
    if t > 0 then kit.icon(dl, 'check', x + s / 2, cy, s, P.bg, a * t) end
    return on, changed == true
end

-- Where slider `id` (its track from x, w wide) is dragged to, min to max, while it's held; else nil.
-- The last item is its track. (The tests stand in for the mouse here.)
function kit.dragged(_, x, w, min, max)
    if not imgui.IsItemActive() then return nil end
    local mx = imgui.GetMousePos()
    if type(mx) == 'table' then mx = mx.x or mx[1] end
    return min + (max - min) * util.clamp((mx - x) / w, 0, 1)
end

local numbers = {}  -- a slider's id -> its typed number's text ({ s }), while that box is open

-- The number typed in slider `id`'s box, once Enter is pressed; nil until then.
local function number_box(id, min, max)
    local key, typed = kit.prefix .. id, nil
    local buf = numbers[key]
    local open = kit.popup(id .. '.number', S(kit.SMALL + 1), function ()
        if buf.focus then
            imgui.SetKeyboardFocusHere()
            buf.focus = false
        end
        imgui.PushItemWidth(S(90))
        if imgui.InputText('##' .. id .. '.typed', buf, 16, ImGuiInputTextFlags_CharsDecimal
                + ImGuiInputTextFlags_EnterReturnsTrue + ImGuiInputTextFlags_AutoSelectAll) then
            typed = tonumber(buf[1])
            imgui.CloseCurrentPopup()
        end
        imgui.PopItemWidth()
        imgui.TextDisabled(('%d to %d'):format(min, max))
    end)
    if not open then numbers[key] = nil end  -- shut: clicked away, or Escape
    return typed
end

-- A slider of whole numbers, `w` wide: the track, then the value (`unit` after it), which a click lets you type.
-- Returns value, changed (each frame it moves: write it then; Sidekick saves once it's let go).
function kit.slider(id, x, cy, w, value, min, max, enabled, alpha, unit)
    local dl, on, a = imgui.GetWindowDrawList(), enabled ~= false, faded(enabled, alpha)
    local value_w = S(52)
    local track = w - value_w - S(10)
    local function held(v) return util.clamp(util.round(v), min, max) end
    -- the press area runs past the track's ends, so the knob drawn half past either end is still the slider's
    local hovered = hit(id, x - S(4), cy - S(9), track + S(12), S(18))
    local dragged = on and kit.dragged(id, x, track, min, max) or nil
    local changed = false
    if dragged then
        local v = held(dragged)
        if v ~= value then value, changed = v, true end
    end
    local f, th = max > min and util.clamp((value - min) / (max - min), 0, 1) or 0, S(4)
    fill(dl, x, cy - th / 2, track, th, P.off, th / 2, a)
    if f > 0 then fill(dl, x, cy - th / 2, math.max(th, track * f), th, P.accent, th / 2, a) end
    local lit = ease(id .. '.lit', (hovered or dragged) and on and 1 or 0, 22)
    kit.circle(dl, x + track * f, cy, S(5.5) + S(1) * lit, dragged and P.accent2 or mix(P.knob, P.accent2, lit * 0.5), a)
    local vx = x + track + S(10)
    local vhov, vclick = hit(id .. '.value', vx, cy - S(10), value_w, S(20))
    if vhov and on then fill(dl, vx, cy - S(10), value_w, S(20), P.hover, S(3)) end
    kit.text_right(dl, vx + value_w - S(4), cy, tostring(value) .. (unit or ''), P.text2, kit.fonts.text, S(kit.SMALL + 0.5), a)
    if vclick and on then
        numbers[kit.prefix .. id] = { tostring(value), focus = true }
        imgui.OpenPopup(id .. '.number')
    end
    local typed = numbers[kit.prefix .. id] and number_box(id, min, max)
    if typed then
        local v = held(typed)
        if v ~= value then value, changed = v, true end
    end
    return value, changed
end

function kit.segments_width(labels, px)
    local widths, total = {}, S(4)
    for i, label in ipairs(labels) do
        widths[i] = measure(label, kit.fonts.text, px) + S(20)
        total = total + widths[i] + (i > 1 and S(1) or 0)
    end
    return total, widths
end

-- Words side by side in a sunken box, one chosen (`index`, 0 for none); segment i's button is ids[i].
-- Returns index, changed, the segment hovered.
function kit.segments(ids, x, cy, labels, index, enabled, alpha, px)
    px = px or S(kit.BODY - 1)
    local dl, on, a = imgui.GetWindowDrawList(), enabled ~= false, faded(enabled, alpha)
    local h = px + S(8)
    local y = cy - h / 2
    local total, widths = kit.segments_width(labels, px)
    fill(dl, x, y, total, h, P.well, S(4), a)
    outline(dl, x, y, total, h, P.well_edge, S(4), a)
    local changed, over, at = false, nil, x + S(2)
    for i, label in ipairs(labels) do
        local sy, sh = y + S(2), h - S(4)
        local hovered, clicked = hit(ids[i], at, sy, widths[i], sh)
        if hovered then over = i end
        if clicked and on and index ~= i then index, changed = i, true end
        local t = ease(ids[i], index == i and 1 or 0)
        if t > 0.01 then fill(dl, at, sy, widths[i], sh, P.seg, S(3), t * a) end
        if hovered and on and index ~= i then fill(dl, at, sy, widths[i], sh, '#FFFFFF', S(3), 0.05 * a) end
        kit.text_centred(dl, at + widths[i] / 2, cy, label, mix(P.dim, P.text, t), kit.fonts.text, px, a)
        at = at + widths[i] + S(1)
    end
    return index, changed, over
end

-- A drop-down `w` wide showing `shown` (whole in a tooltip when it's cut to fit); a click opens its list, ImGui's popup,
-- which `body()` fills with Selectables (a pick closes it). Returns whether its box is hovered.
function kit.dropdown(id, x, cy, w, shown, enabled, alpha, body)
    local h, pad = S(24), S(8)
    local y = cy - h / 2
    local hovered, clicked = hit(id, x, y, w, h)
    local list = id .. '.list'
    local open = imgui.IsPopupOpen(list) == true
    local dl, on, a = imgui.GetWindowDrawList(), enabled ~= false, faded(enabled, alpha)
    fill(dl, x, y, w, h, P.well, S(4), a)
    outline(dl, x, y, w, h, (hovered or open) and on and P.accent_lo or P.well_edge, S(4), a)
    local px = S(kit.SMALL + 0.5)
    local fitted = kit.fit(shown, w - pad * 2 - S(14), kit.fonts.text, px)
    if hovered and fitted ~= shown then kit.tooltip(shown) end
    kit.text_mid(dl, x + pad, cy, fitted, P.text2, kit.fonts.text, px, a)
    kit.icon(dl, open and 'right' or 'down', x + w - pad - S(4), cy, S(11), P.dim, a)
    if clicked and on then imgui.OpenPopup(list) end
    imgui.SetNextWindowPos({ x, y + h + S(2) })
    imgui.SetNextWindowSizeConstraints({ w, 0 }, { math.max(w, S(360)), S(420) })
    kit.popup(list, S(kit.BODY - 1), body)
    return hovered
end

function kit.button_width(label)
    return measure(label, kit.fonts.text, S(kit.SMALL + 0.5)) + S(22)
end

-- A button: 'ghost' (a border), 'accent' (filled) or 'danger' (rose). Returns clicked, its width.
function kit.button(id, x, cy, label, kind, enabled, alpha)
    local w, h = kit.button_width(label), S(24)
    local y = cy - h / 2
    local hovered, clicked, active = hit(id, x, y, w, h)
    local dl, on, a = imgui.GetWindowDrawList(), enabled ~= false, faded(enabled, alpha)
    local t = ease(id, hovered and on and 1 or 0, 22)
    local fg
    if kind == 'accent' then
        fill(dl, x, y, w, h, mix(P.accent, P.accent2, t * 0.6), S(4), a)
        outline(dl, x, y, w, h, '#FFFFFF', S(4), 0.22 * a)
        fg = P.ink
    elseif kind == 'danger' then
        fill(dl, x, y, w, h, mix(P.well, P.rose, 0.10 + 0.10 * t), S(4), a)
        outline(dl, x, y, w, h, P.rose, S(4), (0.45 + 0.25 * t) * a)
        fg = mix(P.rose, '#FFFFFF', t * 0.35)
    else
        fill(dl, x, y, w, h, mix(P.well, P.hover, t), S(4), a)
        outline(dl, x, y, w, h, mix(P.well_edge, P.accent_lo, t), S(4), a)
        fg = mix(P.text2, P.text, t)
    end
    if active then fill(dl, x, y, w, h, '#000000', S(4), 0.15) end
    kit.text_centred(dl, x + w / 2, cy, label, fg, kit.fonts.text, S(kit.SMALL + 0.5), a)
    return clicked and on, w
end

function kit.chip_width(label)
    return math.max(S(30), measure(label, kit.fonts.text, S(kit.SMALL - 0.5)) + S(14))
end

-- A small toggle, `w` wide: 'on' (the accent), 'held' (amber), 'off', or 'empty' (nothing there: an outline).
-- Returns clicked.
function kit.chip(id, x, cy, w, label, state, enabled, alpha)
    local h = S(20)
    local y = cy - h / 2
    local hovered, clicked = hit(id, x, y, w, h)
    local dl, on, a = imgui.GetWindowDrawList(), enabled ~= false, alpha or 1
    local t = ease(id, (state == 'on' or state == 'held') and 1 or 0)
    local fg
    if state == 'empty' then
        outline(dl, x, y, w, h, P.line, S(4), a)
        fg = P.faint
    else
        local held = state == 'held'
        local lit_fill, lit_edge = held and mix(P.well, P.amber, 0.18) or P.accent_bg, held and mix(P.well, P.amber, 0.6) or P.accent_lo
        fill(dl, x, y, w, h, mix(P.well, lit_fill, t), S(4), a)
        outline(dl, x, y, w, h, mix(P.well_edge, lit_edge, t), S(4), a)
        fg = mix(P.dim, held and P.amber or P.accent2, t)
    end
    if hovered and on then fill(dl, x, y, w, h, '#FFFFFF', S(4), 0.06 * a) end
    kit.text_centred(dl, x + w / 2, cy, label, fg, kit.fonts.text, S(kit.SMALL - 0.5), a)
    return clicked and on
end

local CLEAR = { 0, 0, 0, 0 }
local FIELD_COLOURS = { { ImGuiCol_FrameBg, CLEAR }, { ImGuiCol_FrameBgHovered, CLEAR }, { ImGuiCol_FrameBgActive, CLEAR },
                        { ImGuiCol_Text, kit.rgba(P.text) } }

-- A text field `w` wide over a sunken box, `hint` in it while it's empty; `buf` is its { text }. Returns edited.
function kit.input(id, x, cy, w, buf, max, hint)
    local h = S(26)
    local y = cy - h / 2
    local dl = imgui.GetWindowDrawList()
    fill(dl, x, y, w, h, P.field, S(5))
    outline(dl, x, y, w, h, P.field_edge, S(5))
    local px = S(kit.SMALL + 1)
    if hint and buf[1] == '' then kit.text_mid(dl, x + S(9), cy, hint, P.faint, kit.fonts.text, px) end
    local text_h = kit.custom and px or imgui.GetFontSize()
    imgui.SetCursorScreenPos({ x + S(1), y })
    local vars = kit.push_style(FIELD_COLOURS, ImGuiStyleVar_FramePadding, { S(8), math.max(0, (h - text_h) / 2) },
        ImGuiStyleVar_FrameBorderSize, 0)
    kit.push_font(kit.fonts.text, px)
    imgui.PushItemWidth(w - S(2))
    local edited = imgui.InputText(id, buf, max)
    imgui.PopItemWidth()
    kit.pop_font()
    kit.pop_style(FIELD_COLOURS, vars)
    return edited == true
end

return kit
