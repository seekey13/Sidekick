-- core/lang.lua and core/ja.lua: the UI's words and the game's names in the client's language, its
-- encodings, and that every word Sidekick asks for has its Japanese.
local fake = require('tests.fake')
local ja = require('core.ja')
local K = require('core.knowledge')
local lang = require('core.lang')

local sjis = fake.sjis

-- `body` with the UI in Japanese (a font to draw it assumed), the language put back after.
local function japanese(body)
    local was_on, was_drawable = lang.on, lang.drawable
    lang.drawable = true
    lang.use(true)
    local ok, err = pcall(body)
    lang.on, lang.drawable = was_on, was_drawable
    if not ok then error(err, 0) end
end

test('a word or a format is English, or Japanese once the UI is; a word core/ja.lua lacks is noted for the tests', function ()
    lang.use(false)
    eq({ lang.t('Heal under'), lang.f('recast %ds', 12), lang.list({ 'a', 'b' }) }, { 'Heal under', 'recast 12s', 'a, b' })
    japanese(function ()
        lang.misses = nil  -- in game: none kept, however many sentences no pattern takes
        eq({ lang.t('Not a word here'), lang.why('waiting on it for 12 more seconds') },
           { 'Not a word here', 'waiting on it for 12 more seconds' })
        eq(lang.misses, nil)
        lang.misses = {}
        eq({ lang.t('Heal under'), lang.f('recast %ds', 12), lang.list({ 'a', 'b' }) }, { '回復ライン', 'リキャスト 12秒', 'a、b' })
        eq({ lang.t('Not a word here'), lang.misses['Not a word here'] }, { 'Not a word here', true })
        lang.misses = {}
    end)
    eq({ lang.t('Heal under', true), lang.t('Heal under', false) }, { '回復ライン', 'Heal under' })  -- chat's own language
end)

test('Japanese shows only while a Japanese font can draw it: without one the UI stays English', function ()
    local was = lang.drawable
    lang.drawable = false
    eq({ lang.use(true), lang.t('Heal under') }, { false, 'Heal under' })
    lang.drawable = true
    eq({ lang.use(true), lang.t('Heal under') }, { true, '回復ライン' })
    lang.use(false)
    lang.drawable = was
end)

test('the game\'s text is converted from Shift-JIS; ASCII and UTF-8 stay as they are', function ()
    eq(lang.text(sjis('クピピ')), 'クピピ')
    eq({ lang.text('Kupipi'), lang.text('クピピ'), lang.text(nil) }, { 'Kupipi', 'クピピ', nil })
    eq(lang.text('Cure IV -> ' .. sjis('クピピ')), 'Cure IV -> クピピ')  -- an English sentence with a trust's name in it
end)

test('a name: in Japanese the DAT\'s, given or found by its English one; none given, the English', function ()
    lang.learn({ { name = 'Cure IV', jp = fake.res.spells[4].jp } })
    eq({ lang.name('Cure IV', fake.res.spells[4].jp), lang.name('Cure IV') }, { 'Cure IV', 'Cure IV' })
    japanese(function ()
        eq({ lang.name('Cure IV', fake.res.spells[4].jp), lang.name('Cure IV'), lang.name('Cure IV', '') },
           { 'ケアルIV', 'ケアルIV', 'Cure IV' })
        eq(lang.name('Not a spell'), 'Not a spell')
    end)
    eq(lang.name('Cure IV', nil, true), 'ケアルIV')  -- chat's language, whatever the UI's
end)

test('a job\'s abbreviation is its one character in Japanese', function ()
    eq(lang.job('WHM'), 'WHM')
    japanese(function () eq({ lang.job('WHM'), lang.job('BLM'), lang.job('RUN') }, { '白', '黒', '剣' }) end)
end)

-- A reason as each behavior builds it, and what it reads as in Japanese.
local REASONS = {
    { 'efficient: A 70% +2', '効率: A 70% +2' },
    { 'critical: Kupipi 20%', '瀕死: Kupipi 20%' },
    { 'for Haste -> A: A lacks it', 'ヘイスト → A のため: A に効果なし' },
    { 'for Protect: B +2 lack it', 'プロテスのため: B +2 に効果なし' },
    { 'danger: A 40%, for Cure IV', '危険: A 40%（ケアルIVのため）' },
    { 'Me: one shadow left', 'Me: 分身残り1枚' },
    { 'A +1 are due', 'A +1 の歌い直し' },
    { 'A 6.2y away', 'A 6.2y先' },
    { 'MP full', 'MP満タン' },
    { 'A left', 'Aが離れた' },
    { 'B near you', 'B（近く）' },
    { '2 asleep', '2人が睡眠中' },
    { 'Corsair\'s Roll at 7', 'コルセアズロール: 7' },
    { 'at 10, for 11', '10 → 11狙い' },
    { 'A (Entrust)', 'A（エントラスト）' },
    { 'combat over', '戦闘終了' },
    { 'for Radial Arcana', 'レイディアルアルカナのため' },
    { 'holding Protectra V: A 12.3y away', 'プロテアV待機: A 12.3y先' },
    { 'needs Light Arts', '白のグリモアが必要' },
    { 'blocked by Defender', 'ディフェンダー中は使用不可' },
    { 'recast 12.5s', 'リキャスト 12.5秒' },
    { 'nothing to do', 'することがありません' },
    { 'AFK: you moved. Automation resumed.', '放置: 移動したので自動操作を再開しました。' },
}

test('the reasons behaviors give are translated, names from the DAT', function ()
    lang.learn(fake.res.spells, fake.res.abilities, fake.res.statuses)
    eq(lang.why('A lacks it'), 'A lacks it')
    japanese(function ()
        for _, r in ipairs(REASONS) do eq(lang.why(r[1]), r[2], r[1]) end
        eq(lang.why(sjis('クピピ') .. ' lacks it'), 'クピピ に効果なし')  -- a trust's name in it, from the game
    end)
    eq(lang.why('A lacks it', true), 'A に効果なし')  -- chat's language, whatever the UI's
end)

test('a chat line: in Japanese its words translated and the line Shift-JIS, a name from the game kept', function ()
    eq(lang.chat(false, 'Focus: %s.', 'Kupipi'), 'Focus: Kupipi.')
    eq(lang.chat(true, 'Focus: %s.', 'Kupipi'), sjis('フォーカス: Kupipi'))
    eq(lang.chat(true, 'Focus: %s.', sjis('クピピ')), sjis('フォーカス: クピピ'))
    eq(lang.chat(false, 'Profile loaded: %s.', 'ヒーラー'), 'Profile loaded: ' .. sjis('ヒーラー') .. '.')  -- typed in ImGui
end)

test('every note, label and pick-one group in the knowledge table has its Japanese', function ()
    local missing = {}
    for name, rows in pairs(K) do
        for _, use in ipairs(rows.role and { rows } or rows) do
            if use.note and not ja.words[use.note] then missing[#missing + 1] = use.note end
            local base, note = (use.label or ''):match('^(.-) %((.+)%)$')
            if note and not ja.words[note] then missing[#missing + 1] = note end
            if use.label and base ~= name then missing[#missing + 1] = use.label end
        end
    end
    eq(missing, {})
end)

test('each Japanese format takes the arguments its English one does, in the same order', function ()
    local function specs(s)
        local out = {}
        for spec in s:gsub('%%%%', ''):gmatch('%%[-%d.]*%a') do out[#out + 1] = spec:sub(-1) end
        return table.concat(out)
    end
    local wrong = {}
    for en, j in pairs(ja.words) do
        if specs(en) ~= specs(j) then wrong[#wrong + 1] = en end
    end
    for _, p in ipairs(ja.patterns) do
        local caps = select(2, p[1]:gsub('%((.-)%)', ''))
        for k in p[2]:gmatch('%%(%d)') do
            if tonumber(k) > caps then wrong[#wrong + 1] = p[1] end
        end
    end
    eq(wrong, {})
end)
