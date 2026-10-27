--[[
    The language players see: English, or Japanese on a Japanese client (`ui.japanese`). The UI's text is UTF-8, as
    ImGui takes it; Sidekick's chat lines are Shift-JIS, as the game takes them. English is the keys themselves;
    Japanese is core/ja.lua's.

    lang.use(japanese)             the UI's language from here, Japanese only while a Japanese font can draw it
                                   (lang.drawable, which ui/kit.lua sets); returns lang.on
    lang.t(s[, japanese])          a fixed string in the UI's language (or the one given)
    lang.f(fmt, ...)               a format in the UI's language, filled in (its arguments in the same order)
    lang.why(s[, japanese])        a sentence built in English (a reason, a status line), translated by core/ja.lua's
                                   patterns; its game text (a trust's name) as UTF-8 either way
    lang.text(s)                   text from the game (Shift-JIS) as UTF-8; ASCII and UTF-8 as they are
    lang.name(en, jp, japanese)    a name to show: in Japanese its Japanese one (`jp`, from the DAT, Shift-JIS; nil
                                   for the one lang.learn was given for `en`, '' or false for none), else `en`;
                                   `japanese` the language when not the UI's
    lang.learn(list, ...)          names to find by their English one: records { name or en, jp }, each list once
    lang.job(abbr)                 a job's abbreviation; in Japanese its one character ('WHM' -> '白')
    lang.list(items)               items joined: ', ', or '、' in Japanese
    lang.chat(japanese, fmt, ...)  a chat line: `fmt` in that language, filled in, as Shift-JIS

    Pure but for the encoding: VanaCore's vana.encoding, else Windows' code pages through FFI (Wine's too). The
    tests set lang.from_sjis and lang.to_sjis to their own.
]]--

local ja = require('core.ja')

local lang = {}

lang.on = false        -- the UI's text is Japanese now
lang.drawable = true   -- a Japanese font can draw it (ui/kit.lua): false and the UI stays English
lang.misses = nil      -- a table the tests set: the fixed strings and sentences asked for in Japanese that core/ja.lua
                       -- lacks, kept there (not in game, where a sentence with a number in it would add one each time)

function lang.use(japanese)
    lang.on = japanese == true and lang.drawable
    return lang.on
end

local function language(japanese)
    if japanese == nil then return lang.on end
    return japanese == true
end

-- Encoding -----------------------------------------------------------------------------

-- Windows' converters between Shift-JIS (code page 932) and UTF-8, or nil off Windows.
local function windows()
    local ok, ffi = pcall(require, 'ffi')
    if not ok or ffi.os ~= 'Windows' then return nil end
    pcall(ffi.cdef, [[
        int MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *s, int n, wchar_t *w, int wn);
        int WideCharToMultiByte(unsigned int cp, unsigned long flags, const wchar_t *w, int wn, char *s, int n,
                                const char *dflt, int *used);
    ]])
    local function convert(s, from, to)
        local n = ffi.C.MultiByteToWideChar(from, 0, s, #s, nil, 0)
        if n <= 0 then return nil end
        local w = ffi.new('wchar_t[?]', n)
        ffi.C.MultiByteToWideChar(from, 0, s, #s, w, n)
        local m = ffi.C.WideCharToMultiByte(to, 0, w, n, nil, 0, nil, nil)
        if m <= 0 then return nil end
        local b = ffi.new('char[?]', m)
        ffi.C.WideCharToMultiByte(to, 0, w, n, b, m, nil, nil)
        return ffi.string(b, m)
    end
    return function (s) return convert(s, 932, 65001) end, function (s) return convert(s, 65001, 932) end
end

-- lang.from_sjis and lang.to_sjis, chosen the first time one is needed: VanaCore's, else Windows'.
local function converters()
    if lang.from_sjis == nil then
        local vana = rawget(_G, 'vana')
        local enc = type(vana) == 'table' and vana.encoding
        if enc and enc.from_shift_jis and enc.to_shift_jis then
            lang.from_sjis, lang.to_sjis = enc.from_shift_jis, enc.to_shift_jis
        else
            local from, to = windows()
            lang.from_sjis, lang.to_sjis = from or false, to or false
        end
    end
    return lang.from_sjis, lang.to_sjis
end

local utf8_of, utf8_n = {}, 0  -- Shift-JIS -> UTF-8, kept: the same names are shown every frame

-- `s` (Shift-JIS) as UTF-8; nil when nothing here converts it.
local function from_sjis(s)
    local u = utf8_of[s]
    if u ~= nil then return u or nil end
    local from = converters()
    local ok, out = false, nil
    if from then ok, out = pcall(from, s) end
    u = ok and type(out) == 'string' and out or false
    if utf8_n > 4000 then utf8_of, utf8_n = {}, 0 end
    utf8_of[s], utf8_n = u, utf8_n + 1
    return u or nil
end

-- Whether `s` is UTF-8 throughout: text typed into ImGui (a profile's name) or written here, not the game's.
local function utf8_valid(s)
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = b < 0x80 and 1 or b >= 0xC2 and b <= 0xDF and 2 or b >= 0xE0 and b <= 0xEF and 3
            or b >= 0xF0 and b <= 0xF4 and 4 or nil
        if not len then return false end
        for k = i + 1, i + len - 1 do
            local c = s:byte(k)
            if not c or c < 0x80 or c > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

function lang.text(s)
    if type(s) ~= 'string' or not s:find('[\128-\255]') or utf8_valid(s) then return s end
    return from_sjis(s) or s
end

-- `s` (UTF-8) as Shift-JIS, for the game; as it is when nothing converts it.
local function to_sjis(s)
    if not s:find('[\128-\255]') then return s end
    local _, to = converters()
    local ok, out = false, nil
    if to then ok, out = pcall(to, s) end
    return ok and type(out) == 'string' and out or s
end

-- Words --------------------------------------------------------------------------------

function lang.t(s, japanese)
    if not language(japanese) then return s end
    local j = ja.words[s]
    if j then return j end
    if lang.misses then lang.misses[s] = true end
    return s
end

function lang.f(fmt, ...) return lang.t(fmt):format(...) end

function lang.list(items) return table.concat(items, lang.on and '、' or ', ') end

function lang.job(abbr) return lang.on and ja.jobs[abbr] or abbr end

-- Names --------------------------------------------------------------------------------

local index = {}                                -- an English name -> its Japanese one (Shift-JIS)
local learned = setmetatable({}, { __mode = 'k' })  -- the lists in it

function lang.learn(...)
    for i = 1, select('#', ...) do
        local list = select(i, ...)
        if type(list) == 'table' and not learned[list] then
            learned[list] = true
            for _, r in pairs(list) do
                local en = type(r) == 'table' and (r.name or r.en)
                if en and type(r.jp) == 'string' and r.jp ~= '' and index[en] == nil then index[en] = r.jp end
            end
        end
    end
end

-- (`jp` nil looks `en` up; '' or false says it has none)
local function named(en, jp, japanese)
    if not japanese or type(en) ~= 'string' then return en end
    if jp == nil then jp = index[en] end
    return type(jp) == 'string' and jp ~= '' and from_sjis(jp) or en
end

function lang.name(en, jp, japanese) return named(en, jp, language(japanese)) end

-- Sentences ------------------------------------------------------------------------------

-- How each of a pattern's captures is translated: as a name, a sentence of its own, a word; as it is by default.
local CAPTURE = {
    name = function (s, japanese) return named(s, nil, japanese) end,
    why = function (s, japanese) return lang.why(s, japanese) end,
    word = function (s, japanese) return ja.words[s] and lang.t(s, japanese) or s end,
}

function lang.why(s, japanese)
    if type(s) ~= 'string' then return '' end
    s = lang.text(s)
    if not language(japanese) or s == '' then return s end
    if ja.words[s] then return ja.words[s] end
    for _, p in ipairs(ja.patterns) do
        local caps = { s:match(p[1]) }
        if caps[1] then
            for i, c in ipairs(caps) do
                local how = p[3] and CAPTURE[p[3][i]]
                caps[i] = how and how(c, true) or c
            end
            return (p[2]:gsub('%%(%d)', function (k) return caps[tonumber(k)] end))
        end
    end
    -- A name alone ('Kupipi', 'MP 40%') has nothing to translate; two lower-case words in a row are English left over.
    if lang.misses and s:find('%l%l+ %l%l+') then lang.misses[s] = true end
    return s
end

-- Chat -----------------------------------------------------------------------------------

function lang.chat(japanese, fmt, ...)
    local n, args = select('#', ...), { ... }
    for i = 1, n do
        if type(args[i]) == 'string' then args[i] = lang.text(args[i]) end  -- a trust's name: UTF-8 like the rest
    end
    return to_sjis(lang.t(fmt, japanese == true):format(unpack(args, 1, n)))
end

return lang
