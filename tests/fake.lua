-- What the engine and UI tests share: a real catalog from the dumped client
-- data (tests/data), and fake snapshots shaped like core/game.lua's.
local catalog = require('core.catalog')
local engine = require('core.engine')
local K = require('core.knowledge')
local lang = require('core.lang')
local settings = require('core.settings')

local fake = {}

-- Shift-JIS and UTF-8, the same on every OS (the game's own converters are Windows'): ASCII, kana, the symbols and
-- the few kanji the tests' names hold; anything else '〓', the client's own mark for a character it lacks.
local SYMBOLS = { [0x40] = 0x3000, [0x41] = 0x3001, [0x42] = 0x3002, [0x45] = 0x30FB, [0x46] = 0xFF1A, [0x5B] = 0x30FC,
                  [0x60] = 0xFF5E, [0x69] = 0xFF08, [0x6A] = 0xFF09, [0x75] = 0x300C, [0x76] = 0x300D, [0xAC] = 0x3013 }
local KANJI = {
    ['\147\197'] = '毒', ['\150\131'] = '麻', ['\225\131'] = '痺', ['\136\195'] = '暗', ['\136\197'] = '闇',
    ['\144\195'] = '静', ['\142\226'] = '寂', ['\139\243'] = '空', ['\144\228'] = '蝉', ['\143\112'] = '術',
    ['\136\235'] = '壱', ['\147\243'] = '弐', ['\148\146'] = '白', ['\141\149'] = '黒', ['\138\200'] = '簡',
    ['\145\102'] = '素', ['\144\180'] = '清', ['\149\110'] = '貧', ['\143\205'] = '章', ['\143\151'] = '女',
    ['\144\95'] = '神', ['\141\126'] = '降', ['\151\213'] = '臨', ['\150\210'] = '猛', ['\142\210'] = '者',
    ['\136\243'] = '印', ['\149\170'] = '分', ['\144\103'] = '身', ['\151\122'] = '陽', ['\148\69'] = '忍',
    ['\147\100'] = '電', ['\140\245'] = '光', ['\144\206'] = '石', ['\137\206'] = '火', ['\142\190'] = '疾',
    ['\149\151'] = '風', ['\144\118'] = '迅', ['\151\139'] = '雷', ['\139\206'] = '勤', ['\140\144'] = '倹',
    ['\143\172'] = '小', ['\144\83'] = '心', ['\151\223'] = '令', ['\146\75'] = '狸', ['\142\183'] = '執',
    ['\145\108'] = '鼠', ['\148\77'] = '熱', ['\148\103'] = '波', ['\144\119'] = '陣', ['\144\237'] = '戦',
    ['\147\172'] = '闘', ['\149\115'] = '不', ['\148\92'] = '能', ['\150\130'] = '魔', ['\147\185'] = '道',
    ['\142\109'] = '士', ['\149\226'] = '補', ['\136\226'] = '遺', ['\144\138'] = '衰', ['\142\227'] = '弱',
    ['\144\135'] = '睡', ['\150\176'] = '眠', ['\144\233'] = '宣', ['\141\144'] = '告', ['\142\128'] = '死',
    ['\142\244'] = '呪', ['\149\97'] = '病', ['\139\67'] = '気', ['\137\187'] = '化',
}

local function utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- A two-byte Shift-JIS character as UTF-8.
local function wide(b1, b2)
    if b1 == 0x81 and SYMBOLS[b2] then return utf8(SYMBOLS[b2]) end
    if b1 == 0x82 and b2 >= 0x9F and b2 <= 0xF1 then return utf8(0x3041 + b2 - 0x9F) end  -- hiragana
    if b1 == 0x83 and b2 >= 0x40 and b2 <= 0x96 and b2 ~= 0x7F then  -- katakana, which skips 0x7F
        return utf8(0x30A1 + b2 - 0x40 - (b2 > 0x7F and 1 or 0))
    end
    return KANJI[string.char(b1, b2)] or '〓'
end

function fake.from_sjis(s)
    local out, i = {}, 1
    while i <= #s do
        local b = s:byte(i)
        if b < 0x80 then out[#out + 1], i = string.char(b), i + 1
        elseif b >= 0xA1 and b <= 0xDF then out[#out + 1], i = utf8(0xFF61 + b - 0xA1), i + 1  -- half-width kana
        else out[#out + 1], i = wide(b, s:byte(i + 1) or 0), i + 2 end
    end
    return table.concat(out)
end

-- Each UTF-8 character fake.from_sjis gives, back to its Shift-JIS; '?' for any other, as Windows does.
local to = {}
for b1 = 0x81, 0x83 do
    for b2 = 0x40, 0xFC do
        local c = wide(b1, b2)
        if c ~= '〓' or b2 == 0xAC then to[c] = to[c] or string.char(b1, b2) end
    end
end
for k, c in pairs(KANJI) do to[c] = k end

function fake.to_sjis(s)
    return (s:gsub('[\192-\255][\128-\191]*', function (c) return to[c] or '?' end))
end
fake.sjis = fake.to_sjis  -- a name as the game would give it, written in UTF-8 in a test
lang.from_sjis, lang.to_sjis = fake.from_sjis, fake.to_sjis

fake.res = {
    spells = dofile('tests/data/spells.lua'),
    abilities = dofile('tests/data/abilities.lua'),
    statuses = dofile('tests/data/statuses.lua'),
}

-- Catalog for main/sub at these levels: every spell learned, abilities only those named in `jas`.
function fake.catalog(main, main_lv, sub, sub_lv, jas)
    local has = {}
    for _, n in ipairs(jas or {}) do has[n] = true end
    return catalog.build(fake.res, {
        main = main, main_lv = main_lv, sub = sub, sub_lv = sub_lv,
        has_spell = function () return true end,
        has_ability = function (id) return has[fake.res.abilities[id].en] == true end,
    }, K)
end

-- A unit; HP defaults to a 1000 max at its hpp, and everyone stands together.
function fake.unit(t)
    local u = { kind = 'party', in_zone = true, alive = true, dist = 5, pos = { 0, 0, 0 }, buffs = {},
                hpp = 100, mpp = 100, mp = 0, tp = 0, uses_mp = true }
    for k, v in pairs(t) do u[k] = v end
    u.alive = t.alive ~= false and u.hpp > 0
    u.max_hp = t.max_hp or (t.hp and u.hpp > 0 and math.floor(t.hp * 100 / u.hpp)) or 1000
    u.hp = t.hp or math.floor(u.max_hp * u.hpp / 100)
    return u
end

-- Snapshot: you (WHM 75 / BLM 37, 1000 MP) plus `others` in slots 1..n (a
-- tracked player has none, and no MP; the alliance's take slots 6 on, server
-- ids 301 on); `over` sets snapshot fields; `waits` = { [action name] = seconds of recast }.
function fake.snap(others, over, waits)
    local units = { fake.unit({ kind = 'self', slot = 0, sid = 1, name = 'Me', dist = 0, mp = 1000, tp = 0 }) }
    local allied = 0
    for i, o in ipairs(others or {}) do
        if o.kind == 'tracked' then
            o.sid, o.mpp, o.uses_mp = o.sid or 200 + i, 0, false
        elseif o.kind == 'alliance' then
            allied = allied + 1
            o.slot, o.sid = o.slot or 5 + allied, o.sid or 300 + allied
        else
            o.slot, o.sid = o.slot or i, o.sid or 100 + i
        end
        units[#units + 1] = fake.unit(o)
    end
    local g = { now = 1000, me = units[1], units = units, combat = false, learned = {},
        main = 3, main_lv = 75, sub = 4, sub_lv = 37,
        recast = function (a) return (waits or {})[a.name] or 0 end }
    for k, v in pairs(over or {}) do g[k] = v end
    return g
end

-- The action in `list` named `name` (of `role`, when given), else nil.
function fake.named(list, name, role)
    for _, a in ipairs(list) do
        if a.name == name and (not role or a.role == role) then return a end
    end
end

-- The engine's decision on `g` from catalog `cat` (`cfg` the defaults, `mem` a fresh
-- one when nil): the command it would send and the intent, or nil and why not.
function fake.decide(g, cat, cfg, mem)
    cfg = cfg or settings.defaults()
    local intent, why = engine.decide(g, cat, cfg, mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg), intent
end

-- fake.decide, then its send recorded (engine.sent) when there was one, as in game.
function fake.step(g, cat, cfg, mem)
    local cmd, intent = fake.decide(g, cat, cfg, mem)
    if cmd then engine.sent(intent, g, mem) end
    return cmd, intent
end

return fake
