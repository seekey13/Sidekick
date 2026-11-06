--[[
    Japanese, for core/lang.lua: Sidekick's own words, keyed by the English they stand for, exactly as the code
    has it (a format's arguments in the same order); the sentences other modules build in English (a behavior's
    reason, a status line), matched by pattern; and the jobs' one-character abbreviations. Names of spells,
    abilities, items and statuses come from the DATs, never from here. Spelled as the Japanese client spells
    them: ペット, 羅盤, ピアニッシモ. tests/lang_test.lua checks every key the UI asks for is here.
]]--

local ja = {}

ja.words = {
    -- Pages and sections (ui/model.lua's SECTIONS) -----------------------------------------
    ['Profiles'] = 'プロファイル', ['Follow'] = '追従', ['Heal'] = '回復', ['Healing'] = '回復', ['Revive'] = '蘇生',
    ['Remove'] = '治療', ['Wake sleepers'] = '睡眠を起こす', ['Debuff removal'] = '弱体回復', ['Buff'] = '強化',
    ['Buffs'] = '強化', ['Rolls'] = 'ロール', ['Songs'] = '歌', ['Geomancy'] = '風水', ['Runes'] = 'ルーン',
    ['Pet'] = 'ペット', ['Maneuvers'] = 'マニューバ', ['Recover'] = 'MP・TP回復', ['Recovery'] = 'MP・TP回復',
    ['Resting'] = 'ヒーリング', ['Tracked'] = '追跡', ['Tracked players'] = '追跡プレイヤー', ['AFK'] = '放置',
    ['AFK sleep'] = '放置スリープ', ['UI / Log'] = 'UI / ログ', ['SETUP'] = '設定',

    -- Who acts (a behavior, as the log and the HUD's label name it) ---------------------------
    ['heal'] = '回復', ['remove'] = '治療', ['wake'] = '起こす', ['recover'] = 'MP・TP回復', ['pet'] = 'ペット',
    ['pet_send'] = 'ペット', ['revive'] = '蘇生', ['roll'] = 'ロール', ['rune'] = 'ルーン', ['geo'] = '風水',
    ['buff'] = '強化', ['song'] = '歌', ['maneuver'] = 'マニューバ', ['follow'] = '追従', ['rest'] = 'ヒーリング',
    ['Wake'] = '起こす', ['Roll'] = 'ロール', ['Rune'] = 'ルーン', ['Geo'] = '風水', ['Song'] = '歌',
    ['Maneuver'] = 'マニューバ', ['Rest'] = 'ヒーリング', ['Stand'] = '立つ',
    -- /sk catalog's roles, besides those
    ['emergency'] = '緊急', ['modifier'] = '補助', ['ward'] = 'ワード', ['pet_heal'] = 'ペット回復',
    ['pet_remove'] = 'ペット治療', ['unknown'] = '対象外',

    -- Automation's state ---------------------------------------------------------------------
    ['Running'] = '実行中', ['Stopped'] = '停止中', ['Halted (%s)'] = '一時停止中（%s）',
    ['casting'] = '詠唱中', ['moving'] = '移動中', ['combat'] = '戦闘中', ['safe zone'] = '安全エリア',
    ['AFK asleep'] = '放置スリープ中', ['mounted'] = 'マウント中', ['dead'] = '戦闘不能', ['resting'] = 'ヒーリング中',
    ['incapacitated'] = '行動不能', ['silenced'] = '静寂', ['amnesia'] = 'アムネジア', ['zoning'] = 'エリア移動中',
    ['loading'] = 'エリア移動中', ['nothing to do'] = 'することがありません', ['waiting for a cure'] = '回復待ち',
    ['invisible'] = 'インビジ中', ['nothing sent yet'] = 'まだ何も送っていません', ['would: %s'] = '予定: %s',
    ['following %s; %s'] = '%sを追従中、%s',
    ['%s -> %s'] = '%s → %s', ['%s (%s: %s)'] = '%s（%s: %s）', ['%s: %s'] = '%s: %s', ['%s:%s'] = '%s:%s', ['%s'] = '%s',

    -- Names and their notes --------------------------------------------------------------------
    ['%s (%s)'] = '%s（%s）', ['%s %d / %s %d'] = '%s%d/%s%d', ['%s %d'] = '%s%d',
    ['Auto (best)'] = '自動（最上位）', ['Pick one'] = '選択してください', ['%s (not available)'] = '%s（使用不可）',
    ['None'] = 'なし', ['keep up'] = '維持', ['Duration'] = '効果時間', ['Effect'] = '効果',
    -- a pick-one group's name, when it's too many spells to list
    ['Barelement'] = 'バ系（属性）', ['Barstatus'] = 'バ系（状態異常）', ['Enspell'] = 'エン系', ['Storm'] = '陣',
    ['Absorb'] = 'アブゾ系', ['Indi'] = 'インデ系', ['Geo debuff'] = '風水（弱体）',  -- 'Geo' is the behavior's, above
    -- what a modifier does
    ['half the MP'] = '消費MP半減', ['half the casting time'] = '詠唱時間半減', ['longer duration'] = '効果時間延長',
    ['on everyone near you'] = '近くの全員に', ['on everyone near you, at twice the MP'] = '近くの全員に、消費MP2倍',
    ['more potent'] = '効果アップ', ['the next die rolls 1'] = '次の出目が1', ['the next song on one member'] = '次の歌を1人に',
    ['recall the luopan'] = '羅盤を戻す', ['before a luopan'] = '羅盤の前に', ['an Indi- on a member'] = 'インデ系をメンバーに',
    -- what a song gives
    ['+ATK'] = '攻撃力+', ['+DEF'] = '防御力+', ['+Regen'] = 'リジェネ', ['+Refresh'] = 'リフレシュ', ['+ACC'] = '命中+',
    ['++ACC'] = '命中++', ['+Rng Acc.'] = '飛命+', ['++Rng Acc.'] = '飛命++', ['+Haste'] = 'ヘイスト+',
    ['++Haste'] = 'ヘイスト++', ['+EVA'] = '回避+', ['++EVA'] = '回避++', ['+Move Spd.'] = '移動速度+',
    ['-Enmity'] = '敵対心-', ['+Enmity'] = '敵対心+', ['Reraise'] = 'リレイズ', ['+Slow Res.'] = 'スロウ耐性+',
    ['+Poison Res.'] = '毒耐性+', ['+Blind Res.'] = '暗闇耐性+', ['+Silence Res.'] = '静寂耐性+',
    ['+Pet. Res.'] = '石化耐性+', ['+Curse Res.'] = '呪い耐性+', ['+Bind Res.'] = 'バインド耐性+',
    ['+Fire Res.'] = '火耐性+', ['+Ice Res.'] = '氷耐性+', ['+Wind Res.'] = '風耐性+', ['+Earth Res.'] = '土耐性+',
    ['+Lightning Res.'] = '雷耐性+', ['+Water Res.'] = '水耐性+', ['+Light Res.'] = '光耐性+', ['+Dark Res.'] = '闇耐性+',
    ['+STR'] = 'STR+', ['+DEX'] = 'DEX+', ['+VIT'] = 'VIT+', ['+AGI'] = 'AGI+', ['+INT'] = 'INT+', ['+MND'] = 'MND+',
    ['+CHR'] = 'CHR+', ['++STR'] = 'STR++', ['++DEX'] = 'DEX++', ['++VIT'] = 'VIT++', ['++AGI'] = 'AGI++',
    ['++INT'] = 'INT++', ['++MND'] = 'MND++', ['++CHR'] = 'CHR++',
    -- what a roll gives
    ['EXP+'] = '経験値+', ['EVA+'] = '回避+', ['ACC+'] = '命中+', ['ATK+'] = '攻撃力+', ['MDEF+'] = '魔法防御力+',
    ['Cure+'] = 'ケアル回復量+', ['PACC+'] = 'ペット命中+', ['SIR-'] = '詠唱中断率-', ['SB+'] = 'モクシャ+',
    ['PATK+'] = 'ペット攻撃力+', ['STP+'] = 'ストアTP+', ['Refresh+'] = 'リフレシュ+', ['CRIT+'] = 'クリティカル+',
    ['MACC+'] = '魔法命中+', ['DA+'] = 'ダブルアタック+', ['PMAG+'] = 'ペット魔法+', ['DMG Reflect'] = 'ダメージ反射',
    ['MATK+'] = '魔法攻撃力+', ['Regen+'] = 'リジェネ+', ['CMP+'] = 'コンサーブMP+', ['Enhancing+'] = '強化魔法時間+',
    ['MEVA+'] = '魔法回避+', ['Pet Regain & Regen'] = 'ペットのリゲイン・リジェネ', ['Move Speed+'] = '移動速度+',
    ['Fast Cast+'] = 'ファストキャスト+',
    -- elements (runes, maneuvers) and what a rune defends against
    ['Fire'] = '火', ['Ice'] = '氷', ['Wind'] = '風', ['Earth'] = '土', ['Lightning'] = '雷', ['Thunder'] = '雷',
    ['Water'] = '水', ['Light'] = '光', ['Dark'] = '闇', ['Idle'] = '通常時', ['Area'] = '範囲',
    ['Paralyze / Bind'] = '麻痺 / バインド', ['Silence / Weight'] = '静寂 / ヘヴィ', ['Petrify / Slow'] = '石化 / スロウ',
    ['Stun'] = 'スタン', ['Poison'] = '毒', ['Amnesia / Plague'] = 'アムネジア / 悪疫',
    ['Blind / Curse / Sleep'] = '暗闇 / 呪い / 睡眠', ['Charm / Sleep'] = '魅了 / 睡眠',

    -- Whether a row can go (ui/model.lua, core/can.lua) ----------------------------------------
    ['ready'] = '使用可', ['pick one'] = '要選択', ['not available'] = '使用不可', ['recast %ds'] = 'リキャスト %d秒',
    ['equips %s'] = '%sを装備', ['waits for %s: %s'] = '%s待ち: %s', ['nothing on removes it'] = '回復手段がオフ',
    ['every tier unticked'] = 'すべての段階がオフ',
    ['MP'] = 'MP不足', ['TP'] = 'TP不足', ['no ammo'] = '矢弾なし', ['no tools'] = '忍具なし', ['none left'] = '所持なし',
    ['combat only'] = '戦闘中のみ', ['idle only'] = '戦闘外のみ', ['no pet'] = 'ペットなし', ['pet too far'] = 'ペットが遠い',
    ['wrong pet'] = 'ペットが違う', ['not listed'] = '使用できません', ['no battle target'] = '戦闘対象なし',
    ['target out of range'] = '対象が射程外', ['a status'] = '強化',

    -- The HUD ----------------------------------------------------------------------------------
    ['%s  (profile %s)'] = '%s  （プロファイル %s）', ['Target'] = 'ターゲット', ['trust'] = 'フェイス',
    ['tracked'] = '追跡', ['alliance'] = 'アライアンス', ['KO'] = '戦闘不能', ['away'] = '圏外',
    ['%s (pet)\nHP %d%%  MP %d%%  TP %d  %s'] = '%s（ペット）\nHP %d%%  MP %d%%  TP %d  %s',
    ['%s (pet)\nHP %d%%  TP %d  %s'] = '%s（ペット）\nHP %d%%  TP %d  %s',
    ['%s (pet)\nHP %d%%  %s'] = '%s（ペット）\nHP %d%%  %s',
    ['Stop automation'] = '自動操作を停止', ['Start automation'] = '自動操作を開始',
    ['Stop %s\'s automation'] = '%sの自動操作を停止', ['Start %s\'s automation'] = '%sの自動操作を開始',
    ['Settings for %s'] = '%sの設定', ['Settings'] = '設定', ['Close (/sk hud opens it again)'] = '閉じる（/sk hud で再び開きます）',

    -- The widget -------------------------------------------------------------------------------
    ['You'] = 'あなた', ['Default'] = 'デフォルト', ['\nRight-click to load a profile.'] = '\n右クリックでプロファイルを読み込みます。',
    ['%s: %s\nProfile: %s\nRight-click to load another.'] = '%s: %s\nプロファイル: %s\n右クリックで別のプロファイルを読み込みます。',
    ['Open or close Sidekick Settings'] = 'Sidekick設定を開く/閉じる',

    -- Sidekick Settings ------------------------------------------------------------------------
    ['Sidekick Settings'] = 'Sidekick設定', ['Close'] = '閉じる', ['loaded: %s'] = '使用中: %s',
    ['Every switch here is off.'] = 'ここのスイッチはすべてオフです。',
    ['Changes here are sent to that session, which applies them within a second or so.'] =
        'ここでの変更はそのセッションに送られ、1秒ほどで反映されます。',
    ['%s runs another version of Sidekick: /addon reload sidekick there.'] =
        '%sは別のバージョンのSidekickを実行しています。そちらで /addon reload sidekick を実行してください。',
    ['Waiting for %s\'s session...'] = '%sのセッションを待っています…',
    ['px'] = 'px', ['%'] = '%', ['y'] = 'y', ['s'] = '秒', ['m'] = '分',

    -- each section's switch
    ['Follow the leader once they are further away than the distance: mounted, in a safe zone and with '
        .. 'automation stopped too.'] =
        'リーダーが設定した距離より離れたら追従します。マウント中、安全エリア、自動操作の停止中も追従します。',
    ['Heal the party with the rows that are on.'] = 'オンの行でパーティを回復します。',
    ['Raise fallen members with the rows that are on.'] = 'オンの行で戦闘不能のメンバーを蘇生します。',
    ['Wake a sleeping member with a cure or waltz that is on under Heal; an area one for two or more.'] =
        '回復でオンのケアルやワルツで、睡眠中のメンバーを起こします。2人以上なら範囲で起こします。',
    ['Remove the debuffs that are on for the players that are on, with the spells, abilities and items ticked.'] =
        'オンのプレイヤーの、オンの弱体を、チェックした魔法・アビリティ・アイテムで回復します。',
    ['Keep the buffs that are on up on their targets.'] = 'オンの強化を対象に維持します。',
    ['Keep the rolls picked up, and Double-Up the last one by the risk picked. Held for the group with '
        .. 'Hold area buffs, as an area buff.'] =
        '選んだロールを維持し、最後のロールを選んだリスクでダブルアップします。範囲強化として「範囲強化は全員を待つ」の対象です。',
    ['Keep the songs picked up: the area ones on everyone near you, then each member\'s own through Pianissimo. '
        .. 'Held for the group with Hold area buffs, as an area buff.'] =
        '選んだ歌を維持します。範囲の歌は近くの全員に、続いて各メンバーの歌をピアニッシモで。範囲強化として「範囲強化は全員を待つ」の対象です。',
    ['Keep a luopan down: the Geo row\'s on its target, or the Geo debuff\'s on your battle target in combat. '
        .. 'Full Circle recalls it when its target leaves it, and a debuff\'s after combat.'] =
        '羅盤を維持します。ジオの行は対象に、戦闘中はジオ弱体を戦闘対象に置きます。対象が離れたとき、弱体は戦闘後に、フルサークルで戻します。',
    ['Keep the runes picked up: a ward\'s set once it is ready, then the ward in combat; the Idle set the rest '
        .. 'of the time. Lunge and Swipe are yours: the runes go back up after.'] =
        '選んだルーンを維持します。ワードが使えるようになったらそのセットにし、戦闘中にワードを使います。それ以外は通常時のセット。ランジとスワイプは手動で、その後ルーンを付け直します。',
    ['Look after your pet, and send it in, with the rows that are on.'] = 'オンの行でペットの世話をし、戦わせます。',
    ['Keep the maneuvers picked up on you while your automaton is out (none under Overload).'] =
        'オートマトンがいる間、選んだマニューバを維持します（オーバーロード中は使いません）。',
    ['Get MP and TP back with the rows that are on.'] = 'オンの行でMPとTPを回復します。',
    ['Rest for MP out of combat once it falls under a line; stand at full MP, or when the leader leaves.'] =
        'MPがラインを下回ったら戦闘外でヒーリングし、MPが満タンになるか、リーダーが離れたら立ちます。',
    ['While running, pause automation once no one in your party has moved and there has been no combat for '
        .. 'a while; your own movement wakes it (a pull doesn\'t), and so does the leader leaving with Follow on. '
        .. 'Nothing is stopped or saved.'] =
        '実行中、しばらくパーティの誰も動かず戦闘もなければ自動操作を一時停止します。自分が動くと再開します（釣りでは再開しません）。追従中にリーダーが離れても再開します。停止も保存もしません。',

    -- Healing
    ['Heal under'] = '回復ライン', ['Danger under'] = '危険ライン', ['Critical under'] = '瀕死ライン',
    ['Under this HP %, heal with the most HP for the MP or TP. Over it, missing HP is left be.'] =
        'HPがこの%未満なら、MPやTPあたりの回復量が最も多い方法で回復します。これ以上なら減ったHPはそのままにします。',
    ['Under this HP %, heal fastest instead, and wait for a heal nearly ready.'] =
        'HPがこの%未満なら、最も早い回復を優先し、間もなく使える回復を待ちます。',
    ['Under this HP %, boost the heal first (Divine Seal) or save them (Martyr).'] =
        'HPがこの%未満なら、先に回復を強化する（女神の印）か、マーターで救います。',
    ['Focus heal under'] = 'フォーカス回復', ['Focus danger under'] = 'フォーカス危険', ['Focus critical under'] = 'フォーカス瀕死',
    ['For the focus member: Under this HP %, heal with the most HP for the MP or TP. Over it, missing HP is left be.'] =
        'フォーカスメンバー: HPがこの%未満なら、MPやTPあたりの回復量が最も多い方法で回復します。これ以上なら減ったHPはそのままにします。',
    ['For the focus member: Under this HP %, heal fastest instead, and wait for a heal nearly ready.'] =
        'フォーカスメンバー: HPがこの%未満なら、最も早い回復を優先し、間もなく使える回復を待ちます。',
    ['For the focus member: Under this HP %, boost the heal first (Divine Seal) or save them (Martyr).'] =
        'フォーカスメンバー: HPがこの%未満なら、先に回復を強化する（女神の印）か、マーターで救います。',
    ['Untick to never heal them for their own sake; an area heal may still land on them.'] =
        'オフにすると、そのメンバーのためには回復しません。範囲回復は届くことがあります。',
    ['Heal under is at or under Danger under: no efficient heals, only danger ones.'] =
        '回復ラインが危険ライン以下です。効率回復はせず、危険時の回復だけを行います。',
    ['Focus'] = 'フォーカス', ['Heal this member first, on its own lines.'] = 'このメンバーを専用のラインで優先して回復します。',
    ['Focus heal under is at or under Focus danger under: the focus member gets danger heals only.'] =
        'フォーカス回復がフォーカス危険以下です。フォーカスメンバーには危険時の回復だけを行います。',
    ['Cure potency +'] = 'ケアル回復量+', ['Cure potency % from gear, until a cure has been seen healing.'] =
        '装備によるケアル回復量%。ケアルの実際の回復量がわかるまで使います。',
    ['Waltz potency +'] = 'ワルツ回復量+', ['Waltz potency % from gear, until a waltz has been seen healing.'] =
        '装備によるワルツ回復量%。ワルツの実際の回復量がわかるまで使います。',
    ['Regen potency +'] = 'リジェネ効果+', ['HP per Regen tick from gear.'] = '装備によるリジェネ1回あたりのHP。',
    ['Untick to never heal with it; the other tiers still go, and it still wakes a sleeper.'] =
        'オフにすると回復には使いません。他の段階は使います。睡眠中のメンバーを起こすのには使います。',
    ['Untick to never heal with it; the other tiers still go.'] = 'オフにすると回復には使いません。他の段階は使います。',
    ['Keep a stratagem for healing'] = '回復用に戦術魔道書を1回残す',
    ['Buff rows never spend the last stratagem charge, so healing has one for Accession or Rapture.'] =
        '強化の行は戦術魔道書の最後の1回を使わず、女神降臨の章や意気昂然の章のために回復用に残します。',

    -- MP and TP, pet, follow, resting, AFK
    ['MP under'] = 'MP回復ライン', ['Recover MP under this MP % (yours; a member\'s for Devotion).'] =
        'MPがこの%未満なら回復します（自分のMP。デヴォーションはメンバーのMP）。',
    ['TP under'] = 'TP回復ライン', ['In combat, get TP back under this.'] = '戦闘中、TPがこれ未満なら回復します。',
    ['Spend TP from'] = 'TP消費の下限', ['Chivalry turns all your TP into MP: only from this much.'] =
        'シバルリーは全TPをMPに変えます。このTP以上のときだけ使います。',
    ['Pet HP under'] = 'ペットHPライン', ['Heal your pet under this HP %.'] = 'ペットのHPがこの%未満なら回復します。',
    ['Leader'] = 'リーダー', ['Who to follow; resting stands up when they leave too.'] =
        '追従する相手。この人が離れたらヒーリングもやめて立ちます。',
    ['Follow past'] = '追従する距離', ['Yalms.'] = 'ヤルム。',
    ['Rest under'] = 'ヒーリングライン', ['Rest when your MP falls under this %, until it is full.'] =
        'MPがこの%未満になったらヒーリングし、満タンまで続けます。',
    ['Stand up when they are further than Stand past. The same leader as Follow\'s.'] =
        'この人が「立つ距離」より離れたら立ちます。追従のリーダーと同じです。',
    ['Stand past'] = '立つ距離', ['Yalms from the leader.'] = 'リーダーからのヤルム数。',
    ['Sleep after'] = 'スリープまで', ['Minutes with no one in your party moving and no combat.'] =
        'パーティの誰も動かず、戦闘もない分数。',
    ['Asleep: move to wake.'] = 'スリープ中: 動くと再開します。',
    ['Sleeps in %d min without movement or combat.'] = '移動も戦闘もなければ%d分後にスリープします。',

    -- Buffs
    ['Hold area buffs for the group'] = '範囲強化は全員を待つ',
    ['Hold an area buff spell (Protectra, Barfira, songs) while a player in your party who lacks it is out of its '
        .. 'reach, so nobody is left out. Trusts and members in another zone never hold it.'] =
        '効果のないパーティのプレイヤーが範囲外にいる間、範囲強化（プロテア、バファイラ、歌）を待ち、誰も漏れないようにします。フェイスや別エリアのメンバーでは待ちません。',
    ['Ask them to gather'] = '集合を呼びかける',
    ['While one is held that someone near you lacks too, say "Gather together for <spell>" in party chat, '
        .. 'at most every 5 seconds.'] =
        '待っている範囲強化が近くの誰かにも切れていれば、パーティチャットで「集まってください。 <魔法>」と言います（5秒に1回まで）。',
    ['Cast Utsusemi at one shadow'] = '分身1枚で空蝉の術を張り直す',
    ['Recast Utsusemi while its last shadow is up, not only once it is gone. For Ichi, which cannot replace '
        .. 'Ni\'s shadows, that shadow is cancelled a second into the cast, so the new ones land.'] =
        '分身が消えてからではなく、最後の1枚があるうちに空蝉の術を張り直します。弐の分身を上書きできない壱では、詠唱の1秒後にその分身を消して新しい分身が付くようにします。',

    -- Rolls
    ['Roll 1'] = 'ロール1', ['Roll 2'] = 'ロール2', ['Risk'] = 'リスク', ['Lowest'] = '最低', ['Medium'] = '中',
    ['Highest'] = '最高', ['Lucky %d, unlucky %d.'] = 'ラッキー %d、アンラッキー %d。',
    ['Roll 2 is Roll 1: one roll kept up'] = 'ロール2がロール1と同じです: 1つだけ維持します',
    ['Roll 2: Corsair main job only'] = 'ロール2: メインジョブがコルセアのときのみ',
    ['Lowest: banks lucky, and never doubles once a die could bust (6 or more).'] =
        '最低: ラッキーで止め、バストしうる目（6以上）ではダブルアップしません。',
    ['Medium: banks lucky, chases it while it is one die away, and doubles off unlucky up to 8.'] =
        '中: ラッキーで止め、あと1回で届くならラッキーを狙い、アンラッキーなら8までダブルアップします。',
    ['Highest: 11 or nothing. Rolls past lucky, and doubles at 6-10 while Fold is ready to undo a Bust; '
        .. 'without Fold, plays as Medium.'] =
        '最高: 11か無か。ラッキーでも振り、フォールドでバストを消せる間は6～10でもダブルアップします。フォールドがなければ「中」と同じです。',
    ['How far Double-Up chases a total. Every risk doubles at 5 or under (Lowest and Medium bank a lucky '
        .. 'there), never at 11, and turns 10 into 11 with Snake Eye. Fold clears a Bust whenever it is ready.'] =
        'ダブルアップでどこまで目を狙うか。どのリスクでも5以下ならダブルアップし（最低と中はそこでのラッキーで止めます）、11ではせず、10はスネークアイで11にします。フォールドは使えるときにいつでもバストを消します。',
    ['Max risk while an 11 is up'] = '11がある間は最高リスク',
    ['While one roll stands at 11, a Bust can\'t happen, so the other is doubled until it is 11 too (rolled again '
        .. 'when it can no longer be doubled). Once no roll at 11 is up, the risk picked is back.'] =
        '一方のロールが11の間はバストしないので、もう一方も11になるまでダブルアップします（できなくなったら振り直します）。11のロールがなくなれば、選んだリスクに戻ります。',
    ['Risk at max: %s is at 11'] = 'リスク最高: %sが11です', ['Last: %s %d%s'] = '前回: %s %d%s',
    [' (Bust)'] = '（バスト）', [' (lucky)'] = '（ラッキー）', [' (11)'] = '（11）', [' (unlucky)'] = '（アンラッキー）',

    -- Songs
    ['Sung as they are, on you and everyone in your party near you, whenever someone there lacks one. '
        .. 'A member with songs of their own picked keeps only the slots those leave.'] =
        '近くの自分とパーティ全員に、誰かに切れていればそのまま歌います。個別の歌を選んだメンバーには、その歌の残りの枠だけ範囲の歌が入ります。',
    ['Two songs of one kind (Victory and Advancing March) stand side by side; a song picked twice is one. '
        .. 'While an area song is owed, the songs on one member wait: it would push them out.'] =
        '同じ種類の歌2つ（マーチ2種など）は並んで効果があります。同じ歌を2回選んでも1つです。範囲の歌が必要な間は個別の歌を待ちます（範囲の歌で上書きされるため）。',
    ['Sung on %s alone, through Pianissimo, whenever they lack one.'] = '%sだけに、切れたときにピアニッシモで歌います。',
    ['whoever is in this party slot'] = 'このパーティ枠のメンバー', ['no one'] = 'なし',
    ['Pianissimo: %s'] = 'ピアニッシモ: %s',
    ['Songs on one member need Pianissimo (Bard 20)'] = '個別の歌にはピアニッシモ（吟遊詩人20）が必要です',
    ['Pianissimo fast casting'] = 'ピアニッシモで詠唱短縮',
    ['Fire Pianissimo before an area song too, for its shorter cast, and cancel it a second into the cast '
        .. 'so the song still lands on everyone near you. None is fired while Nightingale is up (its casts are '
        .. 'short already); with Pianissimo on recast the area song goes without it. A Pianissimo already up '
        .. 'goes to the next area song, or to a member\'s song while that area song can\'t go yet.'] =
        '範囲の歌の前にもピアニッシモを使って詠唱を短くし、詠唱の1秒後に解除して近くの全員に歌が届くようにします。ナイチンゲール中は使いません（すでに詠唱が短いため）。ピアニッシモがリキャスト中なら範囲の歌はそのまま歌います。すでにかかっているピアニッシモは次の範囲の歌に使い、その歌がまだ歌えない間はメンバーの歌に使います。',
    ['Song Duration'] = '歌の効果時間',
    ['Seconds: sing each song again this long after it landed, before it wears (0: only once it\'s gone). '
        .. 'Set it just under your songs\' real duration, gear included; doubled for a song sung under Troubadour. '
        .. 'While Nightingale and Troubadour are both up, every song sung without Troubadour is sung again.'] =
        '秒数: 歌が付いてからこの時間で、切れる前に歌い直します（0: 切れてから）。装備込みの実際の効果時間より少し短くします。トルバドゥール中に歌った歌は2倍です。ナイチンゲールとトルバドゥールが両方ある間は、トルバドゥールなしで歌った歌をすべて歌い直します。',

    -- Geomancy
    ['Recall past'] = '羅盤を戻す距離',
    ['Yalms: Full Circle the luopan once who it is on is further than this from it, so it goes down again.'] =
        'ヤルム: 対象が羅盤からこれより離れたらフルサークルで戻し、置き直します。',
    ['Keep after combat'] = '戦闘後に残す秒数',
    ['Seconds a debuff luopan waits once combat is over before Full Circle recalls it: a new battle target in that time keeps it.'] =
        '戦闘が終わってから弱体の羅盤をフルサークルで戻すまでの秒数。その間に新しい戦闘対象ができれば残します。',
    ['Entrust to'] = 'エントラスト先',
    ['With Entrust on, put the Indi- spell picked on this member (within 20 yalms).'] =
        'エントラストがオンなら、選んだインデ系をこのメンバーにかけます（20ヤルム以内）。',
    ['Entrust spell'] = 'エントラスト魔法',
    ['The Indi- spell Entrust puts on that member whenever they lack its aura.'] =
        'そのメンバーにオーラがないとき、エントラストでかけるインデ系魔法。',

    -- Runes and maneuvers
    ['Each rune by the element it adds to your attacks.'] = '攻撃に付く属性でルーンを表示します。',
    ['Each rune by the element it resists.'] = '耐性の属性でルーンを表示します。',
    ['Each rune by the ailments it defends against.'] = '防ぐ状態異常でルーンを表示します。',
    ['%s: adds %s, resists %s, against %s.'] = '%s: 攻撃属性 %s、耐性 %s、%sを防ぐ。',
    ['Once %s is ready, its runes take the slots, then it fires in combat.'] =
        '%sが使えるようになったらそのルーンを枠に入れ、戦闘中に使います。',
    ['The runes kept up the rest of the time.'] = 'それ以外のときに維持するルーン。',
    ['The same element in two slots keeps two up.'] = '同じ属性を2枠に入れると2つ維持します。',

    -- Tracked players
    ['Untrack'] = '追跡解除', ['  (in your party)'] = '  （パーティ内）', ['  (in your alliance)'] = '  （アライアンス内）',
    ['  (from %s)'] = '  （%sから）', ['Out of range.'] = '範囲外です。', ['In another zone.'] = '別のエリアにいます。',
    ['Tracked while %s\'s session lists them; Untrack keeps them off until tracked again.'] =
        '%sのセッションが載せている間は追跡します。追跡解除すると、再び追跡するまで外したままにします。',
    ['Track %s'] = '%sを追跡', ['Add Tracked'] = '追跡に追加',
    ['Heal, clear, raise and buff them too, with what reaches outside the party. This session only.'] =
        'パーティ外に届くもので、このプレイヤーも回復・弱体回復・蘇生・強化します。このセッションのみ。',
    ['Target a player outside the alliance in %s\'s game to track them there.'] =
        '%sのゲームでアライアンス外のプレイヤーをターゲットすると、そこで追跡できます。',
    ['Target a player outside your alliance to track them, or /sk track Name.'] =
        'アライアンス外のプレイヤーをターゲットすると追跡できます（/sk track 名前 でも可）。',

    -- Profiles
    ['Name'] = '名前', ['A name for Save or Save as. Each job pair has its own profiles.'] =
        '保存・別名保存の名前。プロファイルはジョブの組み合わせごとにあります。',
    ['Name to save under'] = '保存する名前', ['Save'] = '保存', ['Save as'] = '別名保存', ['New'] = '新規',
    ['Delete'] = '削除',
    ['Save the settings as they are now under this name. With a profile loaded and the name changed, '
        .. 'rename that profile instead. Never over another profile: Save as replaces one.'] =
        '今の設定をこの名前で保存します。プロファイルを読み込み中に名前を変えた場合は、そのプロファイルの名前を変えます。他のプロファイルは上書きしません（上書きは別名保存で）。',
    ['Save the settings as they are now under this name, over any profile already named so.'] =
        '今の設定をこの名前で保存します。同じ名前のプロファイルがあれば上書きします。',
    ['Every setting back to its default, on Default. Saved profiles are kept.'] =
        'すべての設定を初期値に戻してデフォルトにします。保存済みのプロファイルは残ります。',
    ['Delete %s, and go back to Default.'] = '%sを削除して、デフォルトに戻ります。',
    ['%s exists: Save as replaces it.'] = '%sはすでにあります。別名保存で上書きします。',
    ['SAVED'] = '保存済み',
    ['The working copy: your settings as they were before a profile was loaded.'] =
        '作業用の設定: プロファイルを読み込む前の設定です。',
    ['Changes save to the settings in use; to a profile only with Save.'] =
        '変更は使用中の設定に保存されます。プロファイルには「保存」でのみ保存されます。',

    -- UI / Log
    ['HUD'] = 'HUD', ['LOG'] = 'ログ', ['CLIENT'] = 'クライアント', ['Nothing sent yet.'] = 'まだ何も送っていません。',
    ['%ds'] = '%d秒',
    ['HP bar width'] = 'HPバーの幅', ['HP bar height'] = 'HPバーの高さ', ['MP bar width'] = 'MPバーの幅',
    ['MP bar height'] = 'MPバーの高さ', ['TP bar width'] = 'TPバーの幅', ['TP bar height'] = 'TPバーの高さ',
    ['Name font size'] = '名前の文字サイズ', ['Text font size'] = '文字サイズ', ['Spacing'] = 'メンバーの間隔',
    ['Pixels.'] = 'ピクセル。', ['Pixels: its three parts, 1000 TP each, together.'] = 'ピクセル。1000TPずつの3つの区画を合わせた幅。',
    ['Pixels: the title, the tags, the alliance\'s names and the action labels; '
        .. 'the buttons follow it, as far as the HP bar fits them.'] =
        'ピクセル。タイトル、タグ、アライアンスの名前、アクションのラベル。ボタンもHPバーに収まる範囲でこの大きさになります。',
    ['Pixels between members.'] = 'メンバー間のピクセル数。',
    ['Hide unused MP bars'] = '使わないMPバーを隠す',
    ['Leave out the MP bar of a member or pet with no MP (0/0): a job without it, a wyvern, a jug pet. '
        .. 'A tracked player\'s stays: their MP can\'t be read.'] =
        'MPのない（0/0）メンバーやペットのMPバーを表示しません（MPのないジョブ、飛竜、呼び出したペットなど）。'
        .. '追跡中のプレイヤーのMPは読めないため、バーはそのまま残ります。',
    ['Show the HUD'] = 'HUDを表示',
    ['The party\'s HP, MP and TP, apart from this window: closing either leaves the other. Also /sk hud.'] =
        'パーティのHP・MP・TP。このウィンドウとは別で、どちらを閉じてももう一方は残ります。/sk hud でも切り替えられます。',
    ['Lock position'] = '位置を固定',
    ['Keep the HUD and the widget where they are: dragging them no longer moves them.'] =
        'HUDとウィジェットを今の位置に固定します。ドラッグしても動きません。',
    ['Widget'] = 'ウィジェット',
    ['One row of its own: each character\'s name (yours, then each other Sidekick session\'s), its Start/Stop and its '
        .. 'Settings. Right-click a name to load a profile. Up with the HUD closed too. Also /sk widget.'] =
        '1行のバー: 各キャラクターの名前（自分、続いて他のSidekickセッション）と開始/停止、設定。名前を右クリックするとプロファイルを読み込めます。HUDを閉じても表示されます。/sk widget でも切り替えられます。',
    ['Widget size'] = 'ウィジェットのサイズ', ['Pixels: the widget\'s text and icons\' height.'] =
        'ピクセル: ウィジェットの文字とアイコンの高さ。',
    ['Size'] = 'サイズ',
    ['Drop-down rows'] = 'ドロップダウンの行数',
    ['The most choices a drop-down or the widget\'s profile menu shows at once; scroll for the rest. Lower it on a '
        .. 'small screen.'] =
        'ドロップダウンとウィジェットのプロファイルメニューに一度に表示する選択肢の最大数。残りはスクロールで表示されます。小さい画面では下げてください。',
    ['This window\'s size, % of the size that suits your screen. Taken up once the slider is let go.'] =
        'このウィンドウのサイズ（画面に合ったサイズに対する%）。スライダーを離すと反映されます。',
    ['Japanese client'] = '日本語クライアント',
    ['Send spell, ability and item names in Japanese, and show Sidekick in Japanese, on every job.'] =
        '魔法・アビリティ・アイテム名を日本語で送り、Sidekickも日本語で表示します（全ジョブ共通）。',

    -- Rows
    ['Hold'] = '待機', ['empty slot'] = '空き枠', ['%s first: %s'] = '先に%s: %s',
    ['Wait while a modifier picked here can\'t go with the spell (on recast, too few charges, the wrong Arts, '
        .. 'Accession unable to spread it, or short of MP for it); otherwise the spell goes without it.'] =
        'ここで選んだ補助（戦術魔道書など）を魔法と一緒に使えない間（リキャスト中、チャージ不足、グリモア違い、女神降臨の章で広げられない、MP不足）は待ちます。オフなら補助なしで使います。',
    ['\nNo modifier is on here: it waits for nothing.'] = '\nここでオンの補助がないので、何も待ちません。',
    -- a row's gate (its Idle pill is 'Idle (gate)': 'Idle' is the rune set's word above, 通常時)
    ['Combat'] = '戦闘中', ['Idle (gate)'] = '戦闘外',
    ['Only in combat: while there is a battle target, and for a few seconds after.'] =
        '戦闘中のみ: 戦闘対象がいる間と、いなくなってから数秒の間。',
    ['Only out of combat: once the battle target has been gone a few seconds.'] =
        '戦闘外のみ: 戦闘対象がいなくなって数秒たってから。',
    ['Built in: it only goes in combat.'] = '固定: 戦闘中のみ使います。',
    ['Built in: it only goes out of combat.'] = '固定: 戦闘外のみ使います。',
    ['\nClick again to let it go any time.'] = '\nもう一度クリックすると、いつでも使います。',
    ['\nShared with its row under %s: set here, it is set there too.'] =
        '\n%sの行と共通です。ここで設定すると、そちらでも設定されます。',
    ['REMOVERS'] = '回復手段', ['DEBUFFS'] = '弱体', ['ACTIONS'] = 'アクション', ['ITEMS'] = 'アイテム',
    ['Untick to never use it: the debuffs only it removes are greyed out below.'] =
        'オフにすると使いません。これでしか回復できない弱体は下で灰色になります。',
    ['\nIt heals too: unticked here, it is unticked under Heal.'] = '\n回復にも使います。ここでオフにすると回復でもオフになります。',
    ['Untick to leave it on: worth it for what doesn\'t matter to your job (MP Down on a Warrior).'] =
        'オフにすると回復しません。ジョブに関係のない弱体（戦士のMPmaxダウンなど）に。',
    ['All'] = 'すべて', ['Everyone'] = '全員',
    ['Everyone without a set of their own, and whoever joins. A player\'s first change gives them their own.'] =
        '個別の設定がない全員と、新しく入った人。プレイヤーのチップを変えると、その人だけの設定になります。',
    ['Remove all of these debuffs.'] = 'これらの弱体をすべて回復します。',
    ['Leave all of these debuffs on.'] = 'これらの弱体はすべてそのままにします。',
    ['Untick to never clear debuffs on them, Doom too: someone else sees to them.'] =
        'オフにすると、この人の弱体は死の宣告も含めて回復しません（ほかの人に任せます）。',
    ['Removed by %s'] = '回復手段: %s',
    ['\nSwitched off: left on once something removes it again.'] = '\nオフ: 回復手段がまた使えるようになっても、そのままにします。',
    ['Tick something above that removes it.'] = '上で回復手段をオンにしてください。',

    -- Chat (Sidekick.lua) ---------------------------------------------------------------------
    ['No blue magic until the server sends your set spells: it does when you zone or change one.'] =
        'サーバーからセット中の青魔法が届くまで青魔法は使いません（エリア移動か魔法の変更で届きます）。',
    ['No Japanese name for "%s": sent in English, which the Japanese client won\'t take.'] =
        '「%s」の日本語名がないため英語で送りました。日本語クライアントでは使えません。',
    ['%s: Bust'] = '%s: バスト', ['%s: %d (total %d)%s'] = '%s: %d（合計 %d）%s', [': lucky!'] = ': ラッキー！',
    [': 11!'] = ': 11！', [': unlucky'] = ': アンラッキー',
    ['%d more with no automation; /sk catalog unknown lists them.'] = 'ほかに自動化しないものが%d個あります。/sk catalog unknown で一覧します。',
    ['Would send %s  (%s: %s)'] = '送信予定: %s  （%s: %s）', ['Nothing to do now: %s.'] = '今はすることがありません: %s。',
    ['(still inside the post-action lockout)'] = '（行動後の待ち時間中）',
    ['No buffs on. /sk buff Haste p1 p2 turns one on; /sk catalog lists them.'] =
        'オンの強化はありません。/sk buff Haste p1 p2 でオンにできます。/sk catalog で一覧します。',
    ['No buff "%s" for this job. /sk catalog lists them.'] = 'このジョブに強化「%s」はありません。/sk catalog で一覧します。',
    ['Not tracking "%s": /sk track %s first.'] = '「%s」は追跡していません。先に /sk track %s を実行してください。',
    ['%s  (%s: %s)'] = '%s  （%s: %s）', ['  %s%s -> %s'] = '  %s%s → %s', ['%s off.'] = '%s: オフ',['%s on, but pick one: /sk buff <spell name>.'] = '%s: オン。ただし魔法を選んでください: /sk buff <魔法名>',
    ['%s on%s.'] = '%s: オン%s', [' (%s)'] = '（%s）',
    ['%s can\'t go on players outside your party: not on %s.'] = '%sはパーティ外のプレイヤーにはかけられません: %sには使いません。',
    ['/sk afk [on | off | minutes (%d to %d)]'] = '/sk afk [on | off | 分数 (%d～%d)]',
    ['AFK sleep off.'] = '放置スリープ: オフ', ['counts only while running'] = '実行中のみ数えます',
    ['asleep: move to wake'] = 'スリープ中: 動くと再開します', ['sleeps in %d min'] = '%d分後にスリープ',
    ['starts counting now'] = '今から数えます',
    ['AFK sleep after %d min with no party movement or combat (%s).'] = 'パーティの移動も戦闘もなく%d分で放置スリープ（%s）。',
    ['Profiles for %s (loaded: %s): Default%s'] = '%sのプロファイル（使用中: %s）: デフォルト%s',
    ['Profile: Default.'] = 'プロファイル: デフォルト', ['No profile "%s" for %s. /sk profile lists them.'] =
        'プロファイル「%s」は%sにありません。/sk profile で一覧します。',
    ['Profile loaded: %s.'] = 'プロファイルを読み込みました: %s',
    ['No player "%s" near you.'] = '近くにプレイヤー「%s」はいません。',
    ['Target a player first, or /sk track <name>.'] = '先にプレイヤーをターゲットしてください（または /sk track <名前>）。',
    ['%s is in your %s.'] = '%sは%sにいます。', ['party'] = 'パーティ',
    ['Tracking %s: healed, cleared, raised and buffed (buff rows pick them by name).%s'] =
        '%sを追跡します: 回復・弱体回復・蘇生・強化します（強化の行では名前で選べます）。%s',
    [' Checking their level.'] = 'レベルを確認します。',
    ['Tracking %s yourself now: kept when %s\'s session stops listing them.'] =
        '%sを自分で追跡します: %sのセッションが外しても追跡を続けます。',
    ['Already tracking %s%s.'] = '%sはすでに追跡しています%s。', ['; checking their level again'] = '。レベルを再確認します',
    ['No Sidekick session "%s" on this PC (%s).'] = 'このPCにSidekickのセッション「%s」はありません（%s）。',
    ['sessions: %s'] = 'セッション: %s', ['no other sessions'] = '他のセッションはありません',
    ['Automation %s.'] = '自動操作を%s。', ['started'] = '開始しました', ['stopped'] = '停止しました',
    ['Other sessions can\'t be reached until your game has loaded.'] = 'ゲームの読み込みが終わるまで他のセッションに送れません。',
    ['Sent %s to %s.'] = '%sを%sに送りました。', ['start'] = '開始', ['stop'] = '停止',
    ['No other Sidekick sessions on this PC.'] = 'このPCに他のSidekickのセッションはありません。',
    ['That\'s you: /sk opens your Sidekick Settings, /sk start|stop your automation.'] =
        'それはあなたです: /sk で自分のSidekick設定を開き、/sk start|stop で自動操作を切り替えます。',
    ['Not tracking "%s".'] = '「%s」は追跡していません。',
    ['Stopped tracking %s (from %s\'s session) until /sk track %s.'] =
        '%sの追跡をやめました（%sのセッションから）。/sk track %s で再開します。',
    ['Stopped tracking %s.'] = '%sの追跡をやめました。',
    ['ui/custom.lua failed to load, using the standard window: %s'] = 'ui/custom.lua を読み込めないため、標準のウィンドウを使います: %s',
    ['/sk shows Sidekick Settings now, /sk hud the HUD: a custom UI draws them for view.ui.settings '
        .. '(ui/README.md, Upgrading from 3.0.0).'] =
        '/sk はSidekick設定を開くようになりました（HUDは /sk hud）。カスタムUIは view.ui.settings のときに設定を表示します'
        .. '（ui/README.md の Upgrading from 3.0.0）。',
    ['Window closed on an error (/sk hud or /sk opens it again): %s'] =
        'エラーのためウィンドウを閉じました（/sk hud か /sk で再び開きます）: %s',
    ['%s\'s session sent %s, which failed: %s'] = '%sのセッションから届いた%sが失敗しました: %s',
    ['Automation %s from %s\'s session.'] = '自動操作を%s（%sのセッションから）。',
    ['Settings view for another session failed: %s'] = '他のセッション用の設定画面の作成に失敗しました: %s',
    ['The UI failed at load: %s'] = '読み込み時にUIが失敗しました: %s',
    ['Action log %s.'] = 'アクションログ: %s', ['on'] = 'オン',
    ['off'] = 'オフ', ['Widget %s.'] = 'ウィジェット: %s', ['Focus off.'] = 'フォーカス: オフ', ['Focus: %s.'] = 'フォーカス: %s',
    ['Follow off.'] = '追従: オフ', ['Following %s past %d yalms.'] = '%sを追従します（%dヤルムより離れたら）。',
    ['Follow on, but no leader yet: /sk follow <name>.'] = '追従: オン。ただしリーダーが未設定です: /sk follow <名前>',
    ['That\'s you: /sk follow <name> follows someone on the Leader list.'] =
        'それはあなたです: /sk follow <名前> でリーダー一覧の誰かを追従します。',
    ['%s isn\'t on the Leader list now: followed once in your party or alliance, or tracked (/sk track %s).'] =
        '%sは今リーダー一覧にいません。パーティーかアライアンスに加わるか、追跡すると追従します（/sk track %s）。',
    ['Tracking no one. Target a player, then /sk track (or /sk track <name>).'] =
        '誰も追跡していません。プレイヤーをターゲットして /sk track（または /sk track <名前>）。',
    ['Tracking: %s. Target another player to add them.'] = '追跡中: %s。他のプレイヤーをターゲットすると追加できます。',
    ['/sk untrack <name|all>'] = '/sk untrack <名前|all>', ['Tracking no one.'] = '誰も追跡していません。',
    ['Other sessions\' players kept off until tracked by hand (/sk track <name>): %s.'] =
        '他のセッションのプレイヤーは、手動で追跡するまで外したままにします（/sk track <名前>）: %s',
    ['Resting %s.'] = 'ヒーリング: %s', ['Waiting for the game to load your job.'] = 'ゲームがジョブを読み込むのを待っています。',
    ['asked'] = '指定',
    ['%s, then Double-Up at lowest.'] = '%s、続いてダブルアップ（最低リスク）。',
    ['%s when it can (%s), then Double-Up at lowest.'] = '%sは使えるようになってから（%s）、続いてダブルアップ（最低リスク）。',
    ['%s once Invisible wears, then Double-Up at lowest.'] = 'インビジが切れてから%s、続いてダブルアップ（最低リスク）。',
    ['%s once Bust is gone, then Double-Up at lowest.'] = 'バストが消えてから%s、続いてダブルアップ（最低リスク）。',
    ['No roll "%s". /sk help lists the commands.'] = 'ファントムロール「%s」はありません。/sk help でコマンド一覧。',
    ['/sk (or /sidekick) opens or closes Sidekick Settings. Commands: hud, alt [name|all], alt start|stop [name|all], widget, '
        .. 'start [name|all], stop [name|all], toggle, plan, state, '
        .. 'buff [name] [me p1..p5 b0..c5 <tracked>|off], focus <name|off>, follow [name|on|off], rest [on|off], '
        .. 'track [name], untrack <name|all>, profile [name|default], afk [on|off|minutes], catalog [unknown], log, help. '
        .. 'A Phantom Roll\'s name (Bolter\'s Roll) rolls it now, then Double-Ups at Lowest'] =
        '/sk（または /sidekick）でSidekick設定を開閉します。コマンド: hud、alt [名前|all]、alt start|stop [名前|all]、widget、'
        .. 'start [名前|all]、stop [名前|all]、toggle、plan、state、'
        .. 'buff [名前] [me p1..p5 b0..c5 <追跡>|off]、focus <名前|off>、follow [名前|on|off]、rest [on|off]、'
        .. 'track [名前]、untrack <名前|all>、profile [名前|default]、afk [on|off|分数]、catalog [unknown]、log、help。'
        .. 'ファントムロールの名前（ボルターズロール）で今すぐロールし、最低リスクでダブルアップします',
}

-- Sentences built in English elsewhere, tried in order: { Lua pattern, Japanese with %1..%9 for its captures,
-- how each capture is translated ('name': a spell's, ability's or status's name; 'why': a sentence of its own;
-- 'word': one of the words above; nil: as it is, a player's name or a number) }.
ja.patterns = {
    -- whole sentences, before the patterns that would take a part of them
    { '^at (%d+), for 11$', '%1 → 11狙い' },
    { '^to put down one for Radial Arcana$', 'レイディアルアルカナのため羅盤を置く' },
    -- a modifier first (core/engine.lua), ammo first (core/ammo.lua), a heal through a modifier (behaviors/heal.lua)
    { '^for (.-) %-> (.-): (.+)$', '%1 → %2 のため: %3', { 'name', nil, 'why' } },
    { '^for (.-): (.+)$', '%1のため: %2', { 'name', 'why' } },
    { '^(.+), for (.+)$', '%1（%2のため）', { 'why', 'name' } },
    { '^for (.+)$', '%1のため', { 'name' } },
    -- healing (behaviors/heal.lua)
    { '^efficient: (.+)$', '効率: %1' },
    { '^danger: (.+)$', '危険: %1' },
    { '^critical: (.+)$', '瀕死: %1' },
    -- buffs, songs (behaviors/buff.lua, jobs/brd.lua)
    { '^(.+) %+(%d+) lack it$', '%1 +%2 に効果なし' },
    { '^(.+) lacks it$', '%1 に効果なし' },
    { '^(.+) %+(%d+) are due$', '%1 +%2 の歌い直し' },
    { '^(.+) is due$', '%1 の歌い直し' },
    { '^(.+): one shadow left$', '%1: 分身残り1枚' },
    -- the engine's reasons for nothing (core/engine.lua)
    { '^holding (.-): (.+) ([%d%.]+)y away$', '%1待機: %2 %3y先', { 'name' } },
    { '^holding (.-): (.+) not in sight$', '%1待機: %2 が見えない', { 'name' } },
    { '^holding (.+) for (.+)$', '%1: %2待ち', { 'name', 'name' } },
    -- availability (core/can.lua, ui/model.lua)
    { '^needs (.+)$', '%1が必要', { 'name' } },
    { '^blocked by (.+)$', '%1中は使用不可', { 'name' } },
    { '^recast ([%d%.]+)s$', 'リキャスト %1秒' },
    -- follow, rest, removal, waking (behaviors/*.lua)
    { '^(.+) ([%d%.]+)y away$', '%1 %2y先' },
    { '^MP full$', 'MP満タン' },
    { '^(.+) left$', '%1が離れた' },
    { '^(.+) near you$', '%1（近く）' },
    { '^(%d+) asleep$', '%1人が睡眠中' },
    { '^(.+) asleep$', '%1が睡眠中' },
    -- Corsair, Geomancer, Rune Fencer (jobs/*.lua)
    { '^Bust$', 'バスト' },
    { '^not up$', '効果なし' },
    { '^(.+) at (%d+)$', '%1: %2', { 'name' } },
    { '^(.+) %(Entrust%)$', '%1（エントラスト）' },
    { '^combat over$', '戦闘終了' },
    { '^Radial Arcana passed it up$', 'レイディアルアルカナで使い切った' },
    { '^who it went on is gone$', '対象がいない' },
    { '^the Geo row changed$', 'ジオの行が変わった' },
    { '^(.+) ([%d%.]+)y from it$', '%1 が羅盤から%2y' },
    { '^(.+) out of sight$', '%1 が見えない' },
    { '^runes up$', 'ルーン付与済み' },
    { '^idle$', '通常時' },
    { '^(.+) at (.+)$', '%1 → %2' },  -- your pet sent at your battle target (behaviors/pet.lua)
    -- AFK sleep (core/afk.lua), in chat
    { '^AFK: (.+) is leaving%. Automation resumed to follow%.$', '放置: %1が離れています。追従のため自動操作を再開しました。' },
    { '^AFK: you moved%. Automation resumed%.$', '放置: 移動したので自動操作を再開しました。' },
    { '^AFK: no movement or combat for (%d+) min%. Automation asleep: move to wake%.$',
      '放置: %1分間移動も戦闘もありません。自動操作をスリープします。動くと再開します。' },
}

-- The jobs' abbreviations as the Japanese client writes them, by their English ones.
ja.jobs = {
    WAR = '戦', MNK = 'モ', WHM = '白', BLM = '黒', RDM = '赤', THF = 'シ', PLD = 'ナ', DRK = '暗', BST = '獣', BRD = '詩',
    RNG = '狩', SAM = '侍', NIN = '忍', DRG = '竜', SMN = '召', BLU = '青', COR = 'コ', PUP = 'か', DNC = '踊', SCH = '学',
    GEO = '風', RUN = '剣',
}

return ja
