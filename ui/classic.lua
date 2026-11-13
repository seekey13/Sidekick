--[[
    Sidekick Classic: Sidekick 2.9.1's windows, drawn from Sidekick 3's view.

    A theme (ui/README.md): it only shows `view` and changes things through `act`;
    Sidekick decides and acts as it does under the standard window. Party State's Theme,
    or /sk theme Standard, goes back to the standard window.

      /sk          Sidekick Configuration      2.9.1's window: the profile button and the job,
                                               Start/Stop and the status, Track Target, the
                                               tracked players, then a collapsing header per
                                               section with its checkbox. Right-click a header
                                               for tabs or button groups, empty space for the
                                               window's size; right-click a row to favorite it
                                               or keep it to combat or idle.
      /sk widget   Sidekick Widget             the window's header alone, floating.
      /sk hud      Sidekick: Party State       2.9.1's /sk panel: the party, then its row of
                                               settings (Hold AOE, potency, Song Duration, AFK
                                               Sleep, UI Opacity, Japanese Client), and Theme.
      /sk alt      Sidekick Configuration: Name, another session's, its changes sent to it.

    Sidekick 3 keeps some things differently, so 2.9.1's controls are drawn over its
    settings: a buff is on while any of its ME/P1... buttons is lit; each heal tier is
    a checkbox of its own; songs are rows of [A] ME P1... buttons over each target's two
    song slots; Focus Healing is checked while a Focus Target is picked. The section
    layout, window size, opacity and favorites are this UI's own (ui.classic_*).

    English only, as 2.9.1 was: on a Japanese client names still go out in Japanese
    (Japanese Client), but the window, drawn in ImGui's own font, stays in English.

    Ashita's ImGui: widget values are one-element tables, Text and SetTooltip take a
    printf format (esc doubles '%'), and every scope opened must be closed even on an
    error (the `open` stack below), or ImGui takes the game down.
]]--

local imgui = require('imgui')
local lang = require('core.lang')
local LIMITS = require('ui.model').REMOTE_SET  -- each setting's range
local util = require('core.util')

local ui = {}
ui.name = 'Classic'  -- as the theme lists show it

local game_text = lang.text  -- a name the game gave (Shift-JIS on a Japanese client), to draw

-- ImGui ------------------------------------------------------------------------------

-- An ImGui constant by the first of its names this ImGui has (1.92 renamed some), or nil.
local function C(...)
    for i = 1, select('#', ...) do
        local v = _G[(select(i, ...))]
        if v ~= nil then return v end
    end
    return nil
end

-- Flags by name, added up; one this ImGui lacks counts 0.
local function flags(...)
    local n = 0
    for i = 1, select('#', ...) do n = n + (tonumber(C((select(i, ...)))) or 0) end
    return n
end

local VAR_ALPHA = C('ImGuiStyleVar_Alpha')
local COL = {
    text = C('ImGuiCol_Text'), check = C('ImGuiCol_CheckMark'),
    button = C('ImGuiCol_Button'), button_hovered = C('ImGuiCol_ButtonHovered'), button_active = C('ImGuiCol_ButtonActive'),
    frame = C('ImGuiCol_FrameBg'), frame_hovered = C('ImGuiCol_FrameBgHovered'), frame_active = C('ImGuiCol_FrameBgActive'),
    header = C('ImGuiCol_Header'), header_hovered = C('ImGuiCol_HeaderHovered'), header_active = C('ImGuiCol_HeaderActive'),
    tab = C('ImGuiCol_Tab'), tab_hovered = C('ImGuiCol_TabHovered'), tab_active = C('ImGuiCol_TabSelected', 'ImGuiCol_TabActive'),
    tab_dim = C('ImGuiCol_TabDimmed', 'ImGuiCol_TabUnfocused'),
    tab_dim_active = C('ImGuiCol_TabDimmedSelected', 'ImGuiCol_TabUnfocusedActive'),
}
local DEFAULT_OPEN = flags('ImGuiTreeNodeFlags_DefaultOpen')
local TAB_NO_PUSH_ID, TAB_SET_SELECTED = flags('ImGuiTabItemFlags_NoPushId'), flags('ImGuiTabItemFlags_SetSelected')
local BAR_SCROLL, BAR_AUTOSELECT = flags('ImGuiTabBarFlags_FittingPolicyScroll'), flags('ImGuiTabBarFlags_AutoSelectNewTabs')
local KEEP_POPUP = flags('ImGuiSelectableFlags_NoAutoClosePopups', 'ImGuiSelectableFlags_DontClosePopups')
-- BeginChild's third argument: child flags from 1.90 (a border is 1), a border bool before.
local CHILD_BORDER = (tonumber(C('IMGUI_VERSION_NUM')) or 0) >= 19000
    and (tonumber(C('ImGuiChildFlags_Borders', 'ImGuiChildFlags_Border')) or 1) or true
local TABLE_FLAGS = flags('ImGuiTableFlags_Borders', 'ImGuiTableFlags_RowBg', 'ImGuiTableFlags_SizingFixedFit',
    'ImGuiTableFlags_NoHostExtendX')
local LIST_FLAGS = flags('ImGuiTableFlags_SizingFixedFit', 'ImGuiTableFlags_NoHostExtendX')  -- columns of checkboxes
local COLUMN_FIXED = flags('ImGuiTableColumnFlags_WidthFixed')
local FLT_MAX = tonumber(C('FLT_MAX')) or 3.4e38
local AUTO_SIZE = ImGuiWindowFlags_NoResize + ImGuiWindowFlags_AlwaysAutoResize  -- 2.9.1's 'auto' window size
local WIDGET_FLAGS = ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoTitleBar

-- 2.9.1's palette and sizes ---------------------------------------------------------------

local RED, YELLOW, GREEN = { 1.0, 0.7, 0.7, 1.0 }, { 1.0, 1.0, 0.7, 1.0 }, { 0.7, 1.0, 0.7, 1.0 }
local BLUE, GRAY, WHITE = { 0.7, 0.7, 1.0, 1.0 }, { 0.5, 0.5, 0.5, 1.0 }, { 1.0, 1.0, 1.0, 1.0 }
local POPUP_TITLE = { 0.8, 0.8, 0.8, 1.0 }
local DIM = { 0.2, 0.2, 0.2, 1.0 }

local NONE = {}
local OFF_BUTTON = { { COL.button, { 0.3, 0.3, 0.3, 1.0 } }, { COL.button_hovered, { 0.4, 0.4, 0.4, 1.0 } },
                     { COL.button_active, { 0.5, 0.5, 0.5, 1.0 } } }
local DEAD_BUTTON = { { COL.button, DIM }, { COL.button_hovered, DIM }, { COL.button_active, DIM }, { COL.text, GRAY } }
local LABEL_BUTTON = { { COL.button, DIM }, { COL.button_hovered, DIM }, { COL.button_active, DIM } }
local HEADER = { { COL.header, { 0.2, 0.2, 0.2, 0.31 } }, { COL.header_hovered, { 0.2, 0.2, 0.2, 0.45 } },
                 { COL.header_active, { 0.2, 0.2, 0.2, 0.65 } } }
local TAB_OFF = { { COL.tab, { 0.15, 0.15, 0.15, 0.50 } }, { COL.tab_hovered, { 0.25, 0.25, 0.25, 0.60 } },
                  { COL.tab_active, { 0.30, 0.30, 0.30, 0.80 } }, { COL.tab_dim, { 0.15, 0.15, 0.15, 0.50 } },
                  { COL.tab_dim_active, { 0.30, 0.30, 0.30, 0.80 } }, { COL.text, GRAY } }
local NAME_FRAME = { { COL.frame, DIM }, { COL.frame_hovered, { 0.3, 0.3, 0.3, 1.0 } }, { COL.frame_active, { 0.4, 0.4, 0.4, 1.0 } } }
local LOCKED_CHECK = { { COL.text, GRAY }, { COL.frame, DIM }, { COL.frame_hovered, DIM }, { COL.frame_active, DIM },
                       { COL.check, GRAY } }
local GRAY_TEXT, YELLOW_TEXT, GREEN_TEXT = { { COL.text, GRAY } }, { { COL.text, YELLOW } }, { { COL.text, GREEN } }

local INDENT, CHIP_W, GAP, SLOT_W = 10, 35, 8, 20  -- a section's indent; ME/P1 buttons; between them; the S and A column
local DROPDOWN_W, SLIDER_W, NAME_W, BUTTON_W, TRACK_W = 300, 250, 250, 80, 120
local RUNE_LABEL_W, RUNE_W, MANEUVER_W, INT_W = 140, 100, 100, 90
local MIN_W, MIN_H = 320, 200  -- the custom window size's floor
local WIDEST_JOB = 'Puppetmaster 99 / Puppetmaster 49'  -- the widget's width, so it doesn't twitch

local JOBS = { WAR = 'Warrior', MNK = 'Monk', WHM = 'White Mage', BLM = 'Black Mage', RDM = 'Red Mage', THF = 'Thief',
               PLD = 'Paladin', DRK = 'Dark Knight', BST = 'Beastmaster', BRD = 'Bard', RNG = 'Ranger', SAM = 'Samurai',
               NIN = 'Ninja', DRG = 'Dragoon', SMN = 'Summoner', BLU = 'Blue Mage', COR = 'Corsair', PUP = 'Puppetmaster',
               DNC = 'Dancer', SCH = 'Scholar', GEO = 'Geomancer', RUN = 'Rune Fencer' }

-- The modifiers a row's S button lists (the rest get a letter of their own: E for Embolden, N for Nether Void...).
local STRATAGEMS = {}
for _, name in ipairs({ 'Penury', 'Celerity', 'Rapture', 'Accession', 'Parsimony', 'Alacrity', 'Ebullience',
                        'Manifestation', 'Altruism', 'Focalization', 'Tranquility', 'Equanimity', 'Perpetuance',
                        'Immanence' }) do STRATAGEMS[name] = true end

-- Why a row can't go that 2.9.1 greyed it for: it isn't the player's to use now, not a recast or MP.
local LOCKED_REASONS = { ['not available'] = true, ['not listed'] = true, ['no ammo'] = true, ['no tools'] = true,
                         ['none left'] = true, ['wrong pet'] = true }

-- Tooltips, 2.9.1's where Sidekick 3 does the same (SetTooltip doesn't wrap: lines are broken by hand) -------------

local TIP = {
    automation = 'Start/Stop toggles all Sidekick automation.\nStatus shows why it may be paused:\n'
        .. '- Loading: zoning\n- Asleep: AFK sleep, move to wake\n- Mounted: automation suspended\n'
        .. '- Dead: automation suspended\n- Resting: recovering MP\n'
        .. '- Paused: in a safe zone, or unable to act\n- Running: fully active',
    profiles = 'Settings profiles for this job/subjob combo.\nSave named snapshots of the current settings and load them later.\n'
        .. 'Tweaks after a load auto-save to the working copy, never to the profile.',
    tracked = 'Tracks a player outside your party/alliance:\nheal, clear, raise and buff them too, with what\n'
        .. 'reaches outside the party. Removal and buffs\non them are less reliable than on party\n'
        .. 'members. This session only (/sk track Name).',
    follow = 'Auto-follows a party member or tracked\ntarget when they move away. Sends /follow\n'
        .. 'once they pass the Distance below; healing\nand every other support action always take\n'
        .. 'priority. Off by default -- Sidekick never\nmoves you unless this is enabled.',
    follow_target = 'Party member or tracked target to follow.\nSwitching targets stops running at the old\n'
        .. 'one and follows the new one. Also used as\nthe Resting distance watch target.',
    follow_distance = 'Distance (yalms) the Follow Target must pass\nbefore Sidekick sends /follow. The client\n'
        .. 'holds position once you catch up.',
    pet = 'Pet support. Heals your pet under Pet (HP%),\nclears its ailments and sends it in\n'
        .. '(Deploy/Assault/Fight, opt-in) with the rows\nchecked. Maneuver (PUP main or sub) keeps the\n'
        .. '3 picked elements applied, stacking duplicates\nif you pick one twice. Held off while Overload\nis up.',
    maneuver = 'Keep the 3 maneuvers picked up while your\nautomaton is out. The same element twice keeps\ntwo up.',
    pet_hp = 'When your pet\'s HP falls below this %,\nSidekick uses the checked pet-healing ability.',
    pet_at_t = 'Send your pet at your own target (<t>),\nonly while you are engaged. Off: at the\nbattle target (<bt>), engaged or not.',
    focus = 'Gives one party/tracked/alliance member their\nown HP% healing lines (usually higher),\n'
        .. 'checked before the Group lines.\nChecked while a Focus Target is picked.',
    focus_target = 'The member healed on the Focus lines below.',
    group = 'When a member\'s HP drops below Group (HP%),\nSidekick heals them with the most HP for the\n'
        .. 'MP or TP. Under Danger it heals fastest\ninstead; under Critical it boosts the heal\n'
        .. 'first (Divine Seal) or saves them (Martyr).\n\nGroup Targets picks who is healed for their\n'
        .. 'own sake: untick a member to skip them.\nArea heals may still land on them.',
    group_hp = 'Under this HP%, heal with the most HP for\nthe MP or TP. Over it, missing HP is left be.',
    danger_hp = 'Under this HP%, heal fastest instead, and\nwait for a heal nearly ready.',
    critical_hp = 'Under this HP%, boost the heal first (Divine\nSeal) or save them (Martyr) -- before Focus\nor Group healing.',
    group_target = '\nUntick to never heal them for their own sake;\nan area heal may still land on them.',
    reserve = 'Keep one stratagem in reserve for healing.\nBuff rows never spend the last charge, so\n'
        .. 'healing has one for Accession or Rapture.',
    wake = 'Wakes a sleeping member with a cure or waltz;\nan area one when two or more are asleep.\nYou cannot wake yourself.',
    remove = 'Removes debuffs with the spells, abilities\nand items checked, from the Removal Targets.\n'
        .. 'Debuffs to Remove picks which debuffs are\nworth removing, for everyone or one player.',
    remove_target = '\nUntick to never clear debuffs on them, Doom\ntoo: someone else sees to them.',
    shared = 'It heals too: unchecked here, it is unchecked\nunder Group Healing.',
    doom_retries = 'Times Cursna is cast again after it misses a\nDoom; then the Doom is taken as gone. Your\n'
        .. 'own and your party\'s Doom are read from the\ngame: Cursna goes on while it shows.\n\n'
        .. 'Trust/Alliance/Tracked targets: their debuffs\nare read from what this character sees, so\n'
        .. 'if someone else removed the Doom, a Cursna\nthat finds nothing may look the same as a miss.',
    whose = 'Everyone without a set of their own, and\nwhoever joins. A player\'s first change gives\nthem their own.',
    rest = 'While idle and your MP falls below Rest\n(MP%), Sidekick sends /heal on. Nothing\n'
        .. 'Sidekick does interrupts a rest: it stands\nat full MP, or when the Follow Target passes\nDistance.',
    rest_mp = 'Rest when your MP falls under this %,\nuntil it is full.',
    rest_distance = 'Max distance (yalms) from the Follow Target\nbefore resting is stopped or blocked from\nstarting.',
    recover = 'Self Recover (TP/MP%) uses the checked\nabilities when your TP/MP drops below the\n'
        .. 'set value (TP in combat). Chivalry Min TP\nholds back TP-cost MP recovery until your TP\n'
        .. 'reaches that amount. Devotion is used on a\nmember when THEIR MP drops below Self\nRecover (MP%): '
        .. 'the Devotion Target, or\nwhoever is lowest on MP.',
    recover_tp = 'In combat, get TP back under this.',
    recover_mp = 'Recover MP under this MP% (yours; a\nmember\'s for Devotion).',
    min_tp = 'Chivalry turns all your TP into MP: only\nfrom this much.',
    devotion_target = 'Party member Devotion goes on, once their\nMP drops below Self Recover (MP%). While\n'
        .. 'they\'re not in your party, whoever is\nlowest. Lowest MP: whoever in your party\nis lowest.',
    rolls = 'Corsair automation: keeps the two rolls below\nactive and uses Double-Up on each until it is\n'
        .. 'good enough. While Bust is up only one roll slot\nis used, so Sidekick holds off recasting the other.',
    roll_slot = 'Roll cast in this slot. Set to None to leave\nthe slot unused.',
    risk = 'How far Double-Up chases a total. Every tier\ndoubles at 5 or under, never at 11, and turns\n'
        .. '10 into 11 with Snake Eye. Fold clears a\nBust whenever it is ready.\n'
        .. 'Lowest: banks lucky, never doubles once a die\ncould bust (6 or more).\n'
        .. 'Medium: banks lucky, chases it while it is one\ndie away, and doubles off unlucky up to 8.\n'
        .. 'Highest: 11 or nothing. Rolls past lucky, and\ndoubles at 6-10 while Fold is ready to undo a\n'
        .. 'Bust; without Fold, plays as Medium.',
    max_at_11 = 'While one roll stands at 11, a Bust can\'t\nhappen, so the other is doubled until it is 11\n'
        .. 'too. Once no roll at 11 is up, the Risk Tier\npicked is back.',
    runes = 'Rune Fencer runes (RUN main or sub).\nEach row picks the runes to hold, by what they\n'
        .. 'do rather than by name: the element they add\n(Idle Runes), the element they resist\n'
        .. '(Vallation, Valiance), or the ailments they\ndefend against (Pflug).\n'
        .. 'Slots follow your RUN level: 1 rune at 5,\n2 at 35, 3 at 65. Picking the same rune twice\n'
        .. 'keeps two of it up. A row with nothing picked\ndoes nothing.\n'
        .. 'A ward row takes over from Idle Runes once its\nrecast is ready: its runes go up, the ward\n'
        .. 'itself fires in combat, then Idle Runes takes\nthe slots back. Swipe and Lunge are yours to\n'
        .. 'use -- Sidekick only puts the runes back.',
    buffs = 'For each buff that is on, Sidekick checks the\ntarget\'s active buffs and casts it when it is\n'
        .. 'missing: on yourself, party/alliance members or\ntracked players. Click ME/P1... to pick who gets\n'
        .. 'it; a row with none lit is off. Grouped buffs\nlet you pick one tier, or Auto (best).',
    songs = 'Bard songs. Each row is a song: A sings it\nwithout Pianissimo so everyone in range gets\n'
        .. 'it; ME/P1... sing it on that member alone,\nthrough Pianissimo (Bard 20). Each target holds\n'
        .. '2 songs (1 from a subjob): a third swaps the\noldest out. The drop-down picks the tier.',
    area_song = 'Area: sing without Pianissimo so everyone in range gets it.\n'
        .. 'Recast tracks party members not given a specific ME/P button.',
    geo = 'Geomancer automation: keeps a luopan down on\nthe Geo row\'s target (or the Geo debuff\'s on\n'
        .. 'your battle target in combat), triggers Full\nCircle when the luopan is out of range, and\n'
        .. 'casts an Indi spell on a party member via Entrust.',
    geo_distance = 'If your luopan drifts beyond this many yalms\nfrom who it went on, Sidekick uses Full Circle\n'
        .. 'to recall it so it goes down again.',
    geo_timer = 'After your Geo debuff\'s battle target dies,\nSidekick waits this many seconds before Full\n'
        .. 'Circle dismisses the luopan. If a new battle\ntarget appears in that window, the luopan is\n'
        .. 'kept and reused instead.',
    full_circle = 'When checked, Sidekick uses Full Circle to\nrecall your luopan once it passes the\n'
        .. 'Distance threshold below, or after combat\nfor a debuff.',
    blaze = 'Enhances the luopan created by your NEXT Geo\nspell, so Sidekick fires it as a precast: only\n'
        .. 'when no luopan is out and the Geo spell that\nfollows it is affordable. Never used on a\n'
        .. 'luopan that is already down.',
    entrust = 'Enables the Entrust automation below, using\nthe Target and Spell selected.',
    entrust_target = 'Party member who will receive the Entrust-\nassisted Indi spell selected below.',
    entrust_spell = 'Indi spell Sidekick casts on the Entrust Target.\nSidekick uses Entrust on itself first, then casts\n'
        .. 'this spell on the target while Entrust is active.',
    revive = 'Scans party, tracked, and alliance members\nfor KO and casts a raise spell (checks range\n'
        .. 'and buff prerequisites, e.g. Addendum: White).\nRaise spells are idle-only, so this won\'t\n'
        .. 'trigger while you\'re in combat.',
    stratagem = 'Scholar Stratagem: apply a stratagem to this spell to\nreduce MP cost or boost its effect. Click to choose which\n'
        .. 'stratagems to spend. Lit when one is assigned.',
    stratagem_hold = 'On: skip this spell until the stratagem is ready.\n'
        .. 'Off (default): cast the spell without the stratagem when it is on cooldown.',
    debug = 'Print each action Sidekick sends to chat\n(/sk log). This session only: off at load.',
    hold_aoe = 'Holds an area buff spell (Protectra, Barfira,\nsongs, rolls) while a player in your party who\n'
        .. 'lacks it is out of its reach, so nobody is left\nout. Trusts and members in another zone never\n'
        .. 'cause a hold. Off by default.',
    gather = 'Sends "/p Gather together for <spell>" while\nHold AOE for Group is holding a cast that\n'
        .. 'someone near you lacks too, at most once every\n5 seconds. Turn off to hold silently.',
    fast = 'BRD: fire Pianissimo before an area song too,\nfor its shorter cast, and cancel it a second\n'
        .. 'into the cast so the song still lands on\neveryone near you.',
    one_shadow = 'NIN: recast Utsusemi while its last shadow is\nup, not only once it is gone. For Ichi, that\n'
        .. 'shadow is cancelled a second into the cast,\nso the new ones land.',
    cure_potency = 'Gear-based Cure Potency bonus (+%), used to\nsize cures until a cure has been seen healing.',
    waltz_potency = 'Gear-based Waltz Potency bonus (+%), used to\nsize waltzes until a waltz has been seen healing.',
    regen_potency = 'HP per Regen tick from gear.',
    song_duration = 'BRD main at 75. 0 = off: sing a song again once\nit is gone. Above 0: sing each song again this\n'
        .. 'many seconds after it landed -- set it just\nunder your songs\' real duration, gear included.\n'
        .. 'Doubled for a song sung under Troubadour.',
    afk = 'Pauses automation after the Timeout with no\nparty movement or combat. Move to resume.',
    afk_minutes = 'Minutes with no one in your party moving and\nno combat.',
    opacity = 'Fades the Sidekick Configuration window and\nthe widget. Popups and tooltips stay opaque.',
    japanese = 'Turn on if your game client runs in Japanese.\nSpell, ability and item names, and the Gather\n'
        .. 'alert, are then sent in Japanese so the client\naccepts them. This window stays in English.',
    theme = 'What draws Sidekick\'s windows, on every character\non this PC: Standard, this one, or another .lua\n'
        .. 'file in Sidekick\'s ui folder. Also /sk theme.',
}

local MODES = {
    { value = 'headers', label = 'Display as section headers', hint = 'Sections are stacked as collapsing headers.' },
    { value = 'tabs', label = 'Display as tabs', hint = 'Sections are shown as tabs.\n'
        .. 'Dimmed tabs are disabled and sit after the enabled ones.\nOpen a tab to enable or disable it.' },
    { value = 'groups', label = 'Display as button groups', hint = 'Sections are split into Healing, Support and Utility.\n'
        .. 'Click a group to show its sections as tabs.\nDimmed tabs are disabled and sit after the enabled ones.\n'
        .. 'Open a tab to enable or disable it.' },
}
local GROUPS = { 'Healing', 'Support', 'Utility' }
local SIZE_HINT = {
    auto = 'The window resizes itself to fit its contents.\nInstant, but it cannot be resized by hand.',
    custom = 'The window keeps the size you drag it to.\nDrag the bottom-right corner to resize.\n'
        .. 'Contents scroll when they do not fit.',
}

-- Scopes -------------------------------------------------------------------------------------

-- What's open now, innermost last, as the call that closes each: { 'EndCombo' }, { 'PopStyleColor', 3 }... An error
-- inside a window unwinds it to where the window began, so ImGui is always left balanced.
local open = {}

local function opened(closer, arg) open[#open + 1] = { closer, arg } end
local function call(e) if e[2] ~= nil then imgui[e[1]](e[2]) else imgui[e[1]]() end end
local function close(closer)
    local e = table.remove(open)
    if not e or e[1] ~= closer then error(('%s, but %s is open'):format(closer, e and e[1] or 'nothing'), 2) end
    call(e)
end
local function unwind(depth)
    while #open > depth do call(table.remove(open)) end
end

-- Colours from a list of { ImGuiCol_*, colour } (one this ImGui lacks is left out), until untint().
local function tint(list)
    local n = 0
    for _, c in ipairs(list) do
        if c[1] then imgui.PushStyleColor(c[1], c[2]); n = n + 1 end
    end
    opened('PopStyleColor', n)
end
local function untint() close('PopStyleColor') end
local function style(var, v)
    if var then imgui.PushStyleVar(var, v); opened('PopStyleVar', 1) else opened('PopStyleVar', 0) end
end
local function unstyle() close('PopStyleVar') end
local function width(w) imgui.PushItemWidth(w); opened('PopItemWidth') end
local function unwidth() close('PopItemWidth') end
local function indent() imgui.Indent(INDENT); opened('Unindent', INDENT) end
local function unindent() close('Unindent') end

-- The window being drawn: its key (popups' state is kept by it), its opacity, and whether a row's right-click menu
-- is up this frame (the window's own menu then stands down).
local win = { key = '', alpha = 1, item_popup = false }
local was_open = {}  -- [window key][popup id]: open last frame, so its background can be made opaque before it opens

-- Popups ignore the window's fade (UI Opacity): their background is set before they open, which is known from the
-- last frame, and their contents are drawn at full alpha.
local function arm(id)
    local seen = was_open[win.key]
    if win.alpha < 1 and seen and seen[id] then imgui.SetNextWindowBgAlpha(1.0) end
end
local function popped(id, is_open, closer)
    was_open[win.key] = was_open[win.key] or {}
    was_open[win.key][id] = is_open or nil
    if is_open then
        opened(closer)
        style(VAR_ALPHA, 1.0)
    end
    return is_open
end
local function finish(closer) unstyle(); close(closer) end

local function begin_combo(label, preview) arm(label); return popped(label, imgui.BeginCombo(label, preview) == true, 'EndCombo') end
local function end_combo() finish('EndCombo') end
local function begin_popup(id) arm(id); return popped(id, imgui.BeginPopup(id) == true, 'EndPopup') end
local function begin_item_menu(id)
    arm(id)
    local is_open = popped(id, imgui.BeginPopupContextItem(id) == true, 'EndPopup')
    if is_open then win.item_popup = true end
    return is_open
end
local function end_popup() finish('EndPopup') end
local function child(id, size) imgui.BeginChild(id, size, CHILD_BORDER); opened('EndChild') end
local function end_child() close('EndChild') end

-- Text ---------------------------------------------------------------------------------------

local function esc(s) return (tostring(s):gsub('%%', '%%%%')) end
local function text(s) imgui.Text(esc(s)) end
local function colored(c, s) imgui.TextColored(c, esc(s)) end
local function tooltip(s)
    if s == nil or s == '' then return end
    if win.alpha < 1 and VAR_ALPHA then
        imgui.PushStyleVar(VAR_ALPHA, 1.0)
        imgui.SetTooltip(esc(s))
        imgui.PopStyleVar()
    else
        imgui.SetTooltip(esc(s))
    end
end
local function tip(s) if s and s ~= '' and imgui.IsItemHovered() then tooltip(s) end end

local function num(v, d)
    v = tonumber(v)
    if v == nil or v ~= v then return d end
    return v
end
local function text_w(s) return num((imgui.CalcTextSize(s)), #s * 7) end
local function cap(s) return util.capitalize(tostring(s or '')) end
local function id_of(path) return (path:gsub('%.', '_')) end

local function check(label, on)
    local v = { on == true }
    return imgui.Checkbox(label, v), v[1]
end

-- 'White Mage 75 / Black Mage 37', 2.9.1's job line, from the view's 'WHM 75 / BLM 37'; 'None 0' with no subjob.
local function job_line(job)
    job = tostring(job or '')
    local m, ml, s, sl = job:match('^(%S+) (%d+) / (%S+) (%d+)$')
    if not m then m, ml = job:match('^(%S+) (%d+)$') end
    if not m then return job end
    return ('%s %d / %s %d'):format(JOBS[m] or m, tonumber(ml), s and (JOBS[s] or s) or 'None', tonumber(sl) or 0)
end

local function has_flag(view, flag)
    for _, f in ipairs(view.flags or {}) do if f == flag then return true end end
    return false
end

-- 2.9.1's status words and colour: red stopped, green running, blue running but held.
local HALTED = { zoning = 'Automation loading', ['AFK asleep'] = 'Automation asleep', mounted = 'Automation mounted',
                 dead = 'Automation dead', ['safe zone'] = 'Automation paused', incapacitated = 'Automation paused' }
local function status_words(view)
    local s = view.status
    if not s.running then return 'Automation stopped', RED end
    if s.halted then return HALTED[s.halted] or 'Automation paused', BLUE end
    if has_flag(view, 'resting') then return 'Automation resting', BLUE end
    return 'Automation running', GREEN
end

-- Settings controls ----------------------------------------------------------------------------

-- A slider for setting `path`, over its range (LIMITS, unless given).
local function slider(c, label, path, value, help, lo, hi)
    if not lo then lo, hi = LIMITS[path][1], LIMITS[path][2] end
    local v = { util.clamp(math.floor(num(value, lo)), lo, hi) }
    width(SLIDER_W)
    local moved = imgui.SliderInt(label .. '##sk_' .. id_of(path), v, lo, hi)
    unwidth()
    tip(help)
    if moved then c.act.set(path, v[1]) end
end

-- 2.9.1's number field (the Party State panel's), held to its range.
local function int_field(c, label, path, value, w, help)
    local lo, hi = LIMITS[path][1], LIMITS[path][2]
    local v = { util.clamp(math.floor(num(value, lo)), lo, hi) }
    width(w or INT_W)
    local changed = imgui.InputInt(label .. '##sk_' .. id_of(path), v)
    unwidth()
    tip(help)
    if changed then c.act.set(path, util.clamp(math.floor(num(v[1], lo)), lo, hi)) end
end

-- 2.9.1's member drop-down: None for '', then `names`; one not there now reads None and is kept. With `none`,
-- '' reads that instead (Lowest MP), and a name not there now reads as itself: `none` isn't what it does then.
local function name_pick(c, label, path, current, names, help, none)
    local shown = none and current ~= '' and game_text(current) or none or 'None'
    none = none or 'None'
    for _, n in ipairs(names or {}) do
        if n == current then shown = game_text(n) end
    end
    local id = id_of(path)
    width(NAME_W)
    tint(NAME_FRAME)
    if begin_combo(label .. '##sk_' .. id, shown) then
        if imgui.Selectable(none .. '##sk_' .. id .. '_none', shown == none) then c.act.set(path, '') end
        for _, n in ipairs(names or {}) do
            local selected = n == current
            if imgui.Selectable(game_text(n) .. '##sk_' .. id .. '_' .. n, selected) then c.act.set(path, n) end
            if selected then imgui.SetItemDefaultFocus() end
        end
        end_combo()
    end
    untint()
    unwidth()
    tip(help)
end

-- 2.9.1's ability drop-down (rolls, runes, maneuvers): None, then each choice by its `field`; `item_help(choice)`
-- for each one's tooltip. A pick no longer in `choices` reads None.
local function choice_pick(c, label, path, current, choices, field, w, item_help)
    local shown = 'None'
    for _, ch in ipairs(choices) do
        if ch.name == current then shown = ch[field] or ch.label end
    end
    local id = label:match('##.*$') or ('##' .. label)  -- the items' ids, from the combo's
    width(w)
    if begin_combo(label, shown) then
        if imgui.Selectable('None' .. id .. '_none', shown == 'None') then c.act.set(path, '') end
        for _, ch in ipairs(choices) do
            local selected = ch.name == current
            if imgui.Selectable((ch[field] or ch.label) .. id .. '_' .. ch.name, selected) then c.act.set(path, ch.name) end
            if item_help then tip(item_help(ch)) end
            if selected then imgui.SetItemDefaultFocus() end
        end
        end_combo()
    end
    unwidth()
end

-- Favorites (2.9.1's right-click Favorite): row keys, kept as '|Cure|Haste|' in ui.classic_favorites. -------------

local function favorites_of(u)
    local out = {}
    local s = u and u.classic_favorites
    if type(s) == 'string' then
        for key in s:gmatch('[^|]+') do out[key] = true end
    end
    return out
end

local function set_favorite(c, key, on)
    local list = {}
    for k in pairs(c.favs) do
        if k ~= key then list[#list + 1] = k end
    end
    if on then list[#list + 1] = key end
    table.sort(list)
    c.mine.set('ui.classic_favorites', #list > 0 and ('|' .. table.concat(list, '|') .. '|') or '')
    c.favs[key] = on or nil
end

-- `rows` with the favorites first (by name), then the rest in their own order; and how many favorites lead.
local function favorites_first(c, rows)
    local favs, rest = {}, {}
    for _, r in ipairs(rows) do
        table.insert(c.favs[r.key] and favs or rest, r)
    end
    table.sort(favs, function (a, b)
        local x, y = a.label:lower(), b.label:lower()
        if x ~= y then return x < y end
        return a.key < b.key
    end)
    local n = #favs
    for _, r in ipairs(rest) do favs[#favs + 1] = r end
    return favs, n
end

-- A line under the last favorite, when more rows follow.
local function divider(i, n, total)
    if i == n and i < total then imgui.Separator() end
end

-- Rows ------------------------------------------------------------------------------------------

local GATE_WORDS = { combat = 'Combat Only', idle = 'Idle Only' }

-- A row 2.9.1 would grey: it isn't yours to use now (not learned, no ammo or tools, none left, the wrong pet, a
-- status it needs not up), as against one only waiting (recast, MP, combat).
local function locked(r)
    if r.ready then return false end
    local a = r.avail or ''
    return LOCKED_REASONS[a] == true or a:find('^needs ') ~= nil
end

local function row_colors(r, gray)
    if gray then return GRAY_TEXT end
    if r.gate == 'combat' then return YELLOW_TEXT end
    if r.gate == 'idle' then return GREEN_TEXT end
    return NONE
end

-- A row's tooltip: `extra`, its gate (yellow Combat Only, green Idle Only), why it can't go, the section it shares.
local function row_help(r, extra)
    local lines = {}
    if extra then lines[#lines + 1] = extra end
    if r.gate then lines[#lines + 1] = GATE_WORDS[r.gate] .. (r.gate_fixed and ' (built in)' or '') end
    if not r.ready and r.avail and r.avail ~= '' then lines[#lines + 1] = cap(r.avail) end
    if r.also then lines[#lines + 1] = 'Shared with its row under ' .. r.also end
    return table.concat(lines, '\n')
end

-- 2.9.1's right-click on a row: Favorite, then Combat Only / Idle Only (none for a gate that's built in).
local function row_menu(c, r, id, no_favorite)
    local gates = not r.gate_fixed
    if no_favorite and not gates then return end
    if begin_item_menu('##sk_menu_' .. id) then
        if not no_favorite then
            local changed, on = check('Favorite##sk_fav_' .. id, c.favs[r.key] == true)
            if changed then set_favorite(c, r.key, on) end
            tip('Show this at the top of its list.\nDisplay only: casting order is unchanged.')
            if gates then imgui.Separator() end
        end
        if gates then
            local changed, on = check('Combat Only##sk_combat_' .. id, r.gate == 'combat')
            if changed then c.act.gate(r.key, on and 'combat' or nil) end
            tip('Only fire in combat: while there is a battle\ntarget, and for a few seconds after.')
            changed, on = check('Idle Only##sk_idle_' .. id, r.gate == 'idle')
            if changed then c.act.gate(r.key, on and 'idle' or nil) end
            tip('Only fire when out of combat (e.g. Boost on cooldown).')
        end
        if r.also then
            imgui.Separator()
            colored(GRAY, 'Shared with its row under ' .. r.also)
        end
        end_popup()
    end
end

-- How many an item row has (or a ninjutsu row's tools pay for), green, red at none.
local function count_after(r)
    local n = r.count or r.tools
    if n then
        imgui.SameLine()
        colored(n > 0 and GREEN or RED, ('(%d)'):format(n))
    end
end

-- A heal tier's checkbox, 2.9.1's one box per spell: ticked while its row is on and it's left ticked. Ticking one on
-- a row that's off turns the row on with it alone; unticking the last turns the row off.
local function tier_click(a, r, tr, want)
    if want then
        if r.on then return a.heal_spell(tr.name, true) end
        a.row(r.key, true)
        for _, o in ipairs(r.tiers) do
            if o ~= tr and o.on then a.heal_spell(o.name, false) end
        end
        if not tr.on then a.heal_spell(tr.name, true) end
        return
    end
    for _, o in ipairs(r.tiers) do
        if o ~= tr and o.on then return a.heal_spell(tr.name, false) end
    end
    a.row(r.key, false)
end

-- 2.9.1's ability checkbox: a row on or off, or a heal row's tiers one box each. Tinted by its gate, grey when it
-- isn't yours to use now.
local function check_row(c, sid, r, opts)
    opts = opts or NONE
    local id = sid .. '_' .. r.key
    local colors = row_colors(r, locked(r))
    if r.tiers then
        for _, tr in ipairs(r.tiers) do
            local tid = id .. '_' .. tr.name
            tint(colors)
            local changed, on = check(tr.label .. '##sk_' .. tid, r.on and tr.on)
            untint()
            if changed then tier_click(c.act, r, tr, on) end
            row_menu(c, r, tid, opts.no_favorite)
            tip(row_help(r, opts.help))
        end
        return
    end
    tint(colors)
    local changed, on = check(r.label .. '##sk_' .. id, r.on)
    untint()
    if changed then c.act.row(r.key, on) end
    row_menu(c, r, id, opts.no_favorite)
    tip(row_help(r, opts.help))
    count_after(r)
end

-- An item's checkbox, 2.9.1's Item Debuff Removal: its name and how many you carry, grey at none.
local function item_row(c, sid, r)
    local id = sid .. '_item_' .. r.key
    local n = r.count or 0
    tint(n == 0 and LOCKED_CHECK or row_colors(r, false))
    local changed, on = check(('%s (%d)###sk_%s'):format(r.label, n, id), r.on)
    untint()
    if changed then c.act.row(r.key, on) end
    row_menu(c, r, id, true)
    tip(row_help(r, n == 0 and ('No ' .. r.label .. ' in inventory') or ('Use ' .. r.label .. ' to remove a debuff')))
end

-- One of 2.9.1's ME/P1... buttons: lit ('on'), unlit ('off') or grey and dead ('dead'). Returns clicked (never dead).
local function chip_button(label, id, look, help, w)
    tint(look == 'dead' and DEAD_BUTTON or look == 'off' and OFF_BUTTON or NONE)
    local clicked = imgui.Button(label .. '##' .. id, { w or CHIP_W, 0 })
    untint()
    tip(help)
    return clicked and look ~= 'dead'
end

-- A buff chip clicked, as 2.9.1's buttons: a row is on while any is lit. Lighting one on a row that's off turns the
-- row on for that target alone; unlighting the last turns the row off.
local function chip_click(a, r, tg, lit)
    if lit then
        for _, o in ipairs(r.targets) do
            if o ~= tg and o.on then return a.target(r.key, tg.slot, false) end
        end
        return a.row(r.key, false)
    end
    if r.on then return a.target(r.key, tg.slot, true) end
    a.row(r.key, true)
    for _, o in ipairs(r.targets) do
        if o ~= tg and o.on then a.target(r.key, o.slot, false) end
    end
    if not tg.on then a.target(r.key, tg.slot, true) end
end

-- A trust that can't be hurt (core/game.lua: immune): its button is grey and dead, as 2.9.1's.
local function immune_help(name)
    return game_text(name) .. '\nTrust cannot take any damage'
end

local function member_help(c, name, warning)
    if not name then return 'empty slot' end
    local kind = c.kinds[name]
    return game_text(name) .. ((kind == 'trust' or kind == 'tracked') and warning or '')
end

-- A row's buttons: ME, P1-P5, then the alliance's and tracked players, each while someone is there (or it's lit, to
-- turn off). The alliance and tracked players a row can't reach are there greyed, as 2.9.1 had them.
local function buff_chips(c, sid, r)
    local id = sid .. '_' .. r.key
    local any, groups = false, {}
    local function next_one()
        if any then imgui.SameLine() end
        any = true
    end
    for _, tg in ipairs(r.targets) do
        groups[tg.group] = true
        local lit = r.on and tg.on
        if tg.present or lit then
            next_one()
            if chip_button(tg.label, 'sk_' .. id .. '_' .. tostring(tg.slot), tg.immune and 'dead' or lit and 'on' or 'off',
                    tg.immune and immune_help(tg.name) or member_help(c, tg.name, '\nTrust/Tracked Buff tracking is not totally reliable')) then
                chip_click(c.act, r, tg, lit)
            end
        end
    end
    local outside = 'Not compatible with out-of-party targets'
    if not groups.a then
        for _, p in ipairs(c.view.alliance) do
            next_one()
            chip_button(p.tag, 'sk_' .. id .. '_x_' .. p.tag, 'dead', outside)
        end
    end
    if not groups.tracked then
        for _, p in ipairs(c.view.party) do
            if p.kind == 'tracked' then
                next_one()
                chip_button(p.tag, 'sk_' .. id .. '_x_' .. p.tag, 'dead', outside)
            end
        end
    end
end

-- 2.9.1's ON/OFF button is as wide as a row of buttons for everyone there.
local function onoff_width(c)
    local n = math.max(1, #c.view.party + #c.view.alliance)
    return CHIP_W * n + GAP * (n - 1)
end

-- The S button (or E, N, D...) at the head of a row with modifiers: a popup of them and Hold, lit while one is on.
local function mods_button(c, sid, r)
    local id = sid .. '_' .. r.key
    local strat, any = false, false
    for _, m in ipairs(r.mods) do
        strat = strat or STRATAGEMS[m.name] == true
        any = any or m.on
    end
    local first = r.mods[1]
    local single = not strat and #r.mods == 1
    local popup = '##sk_mods_popup_' .. id
    tint(any and NONE or OFF_BUTTON)
    if imgui.Button((strat and 'S' or first.name:sub(1, 1)) .. '##sk_mods_' .. id, { SLOT_W, 0 }) then imgui.OpenPopup(popup) end
    untint()
    tip(strat and TIP.stratagem or ('%s: fire %s before this spell to boost\nit. Click to configure. Lit when enabled.'):format(first.label, first.label))
    if begin_popup(popup) then
        colored(POPUP_TITLE, strat and 'Scholar Stratagem' or first.label)
        imgui.Separator()
        for _, m in ipairs(r.mods) do
            local label = single and 'Enable' or (m.note and ('%s  (%s)'):format(m.label, m.note) or m.label)
            local changed, on = check(label .. '##sk_mod_' .. id .. '_' .. m.name, m.on)
            if changed then c.act.mod(r.key, m.name, on) end
            if single then tip('Fire ' .. m.label .. ' before this spell.') end
        end
        imgui.Separator()
        local changed, on = check((strat and 'Hold for Stratagem' or 'Hold for ' .. first.label) .. '##sk_hold_' .. id, r.hold == true)
        if changed then c.act.hold(r.key, on) end
        tip(strat and TIP.stratagem_hold or ('On: skip this spell until %s is ready.\n'
            .. 'Off (default): cast the spell without it when it is on cooldown.'):format(first.label))
        end_popup()
    end
    imgui.SameLine(0, GAP)
end

-- 2.9.1's buff row: [S] [ME][P1]... then the buff's name, or its drop-down when it has tiers or a pick; a buff on
-- you alone has [ON/OFF] instead of the buttons. `no_favorite` where the order is fixed (Geo).
local function buff_row(c, sid, r, has_mods, no_favorite)
    local id = sid .. '_' .. r.key
    if has_mods then
        if r.mods then mods_button(c, sid, r)
        else
            imgui.Dummy({ SLOT_W, 0 })
            imgui.SameLine(0, GAP)
        end
    end
    if r.targets then
        buff_chips(c, sid, r)
    else
        tint(r.on and NONE or OFF_BUTTON)
        if imgui.Button((r.on and 'ON' or 'OFF') .. '##sk_onoff_' .. id, { onoff_width(c), 0 }) then c.act.row(r.key, not r.on) end
        untint()
    end
    imgui.SameLine()
    tint(row_colors(r, locked(r)))
    if r.choices then
        width(DROPDOWN_W)
        if begin_combo('##sk_pick_' .. id, r.choice or '') then
            for _, ch in ipairs(r.choices) do
                -- Enspells, storms: Auto first, following the sky (Match); a tier picked leaves it.
                local selected = ch.match and r.match or not ch.match and not r.match and ch.name == r.pick
                if imgui.Selectable(ch.label .. '##sk_pick_' .. id .. '_' .. (ch.match and 'match' or ch.name or 'auto'), selected) then
                    if ch.match then c.act.match(r.key, true) else c.act.pick(r.key, ch.name) end
                end
                if ch.match then
                    tip(r.match_rule == 'weather' and 'Cast the storm matching the zone\'s weather.\nNo elemental weather: the last one you picked goes.'
                        or 'Cast the one your weather (a storm on you counts)\nand the day favor most. Neither on its side:\nthe last one you picked goes.')
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            end_combo()
        end
        unwidth()
    else
        text(r.label)
    end
    untint()
    row_menu(c, r, id, no_favorite)
    tip(row_help(r))
    count_after(r)
end

-- Songs: 2.9.1's rows, one per song with its tiers in a drop-down, over each target's song slots ----------------

local function song_path(set, i) return ('song.%s_%d'):format(set.key, i) end

-- Puts `tier` on `set`: in its first free slot (or one holding a song no longer had); full, the oldest goes.
local function place_song(a, m, set, tier, family_of)
    for i = 1, m.slots do
        if not family_of[set.picks[i]] then return a.set(song_path(set, i), tier) end
    end
    for i = 1, m.slots - 1 do a.set(song_path(set, i), set.picks[i + 1]) end
    a.set(song_path(set, m.slots), tier)
end

local function song_row(c, m, fam, family_of)
    local a, id = c.act, 'song_' .. fam.name
    local function held(set)
        local out = {}
        for i = 1, m.slots do
            if family_of[set.picks[i]] == fam.name then out[#out + 1] = i end
        end
        return out
    end
    -- The tier: the one picked here last, else one a target holds, else the highest.
    local tier = c.st.song_tier[fam.name]
    local known = {}
    for _, ch in ipairs(fam.tiers) do known[ch.name] = ch end
    if not known[tier] then
        tier = nil
        for _, set in ipairs(m.sets) do
            for _, i in ipairs(held(set)) do tier = tier or set.picks[i] end
        end
    end
    tier = tier or fam.tiers[#fam.tiers].name
    local first = true
    for _, set in ipairs(m.sets) do
        local slots = held(set)
        local lit = #slots > 0
        local area = set.key == 'area'
        if area or set.present or lit then
            if not first then imgui.SameLine(0, GAP) end
            first = false
            local dead = not area and (set.immune or not m.pianissimo) and not lit
            local help = area and TIP.area_song or set.immune and immune_help(set.name)
                or ((set.name and game_text(set.name) or 'empty slot') .. (m.pianissimo and '' or '\nNeeds Pianissimo (Bard 20)'))
            if chip_button(area and 'A' or set.label, 'sk_' .. id .. '_' .. set.key, dead and 'dead' or lit and 'on' or 'off',
                    help, area and SLOT_W or CHIP_W) then
                if lit then
                    for _, i in ipairs(slots) do a.set(song_path(set, i), '') end
                else
                    place_song(a, m, set, tier, family_of)
                end
            end
        end
    end
    imgui.SameLine()
    if #fam.tiers > 1 then
        width(DROPDOWN_W)
        if begin_combo('##sk_' .. id .. '_tier', known[tier].label) then
            for _, ch in ipairs(fam.tiers) do
                if imgui.Selectable(ch.label .. '##sk_' .. id .. '_' .. ch.name, ch.name == tier) then
                    c.st.song_tier[fam.name] = ch.name
                    for _, set in ipairs(m.sets) do
                        for _, i in ipairs(held(set)) do
                            if set.picks[i] ~= ch.name then a.set(song_path(set, i), ch.name) end
                        end
                    end
                end
            end
            end_combo()
        end
        unwidth()
    else
        text(known[tier].label .. (m.pianissimo and '' or ' (Pianissimo Lv20)'))
    end
end

-- Sections' bodies ---------------------------------------------------------------------------

local function section_rows(c, sid, s, opts)
    local rows, n = favorites_first(c, s.rows or {})
    for i, r in ipairs(rows) do
        check_row(c, sid, r, opts)
        divider(i, n, #rows)
    end
end

local function self_line(view)
    for _, p in ipairs(view.party) do
        if p.kind == 'self' then return p end
    end
end

-- Who's in the party but you (trusts too): Sleep Removal shows only then, as 2.9.1's.
local function others_here(view)
    for _, p in ipairs(view.party) do
        if p.kind == 'party' or p.kind == 'trust' then return true end
    end
    return false
end

-- A row of 2.9.1's slot buttons from chips (healing's targets, removal's), each present one with a name; `on_click(tg)`.
local function slot_buttons(chips, id, on_click, help_of)
    local any = false
    for _, tg in ipairs(chips or {}) do
        if tg.present and tg.name then
            if any then imgui.SameLine() end
            any = true
            if chip_button(tg.label, 'sk_' .. id .. '_' .. tostring(tg.slot), tg.immune and 'dead' or tg.on and 'on' or 'off',
                    tg.immune and immune_help(tg.name) or help_of(tg)) then on_click(tg) end
        end
    end
    return any
end

local function follow_body(c)
    local f = c.view.follow
    name_pick(c, 'Follow Target', 'follow.target', f.target, f.names, TIP.follow_target)
    slider(c, 'Distance (yalms)', 'follow.distance', f.distance, TIP.follow_distance)
end

-- The Maneuver row: its switch (the Maneuvers section's), then a drop-down per slot.
local function maneuver_row(c, with_switch)
    local m = c.view.maneuver
    if with_switch then
        local changed, on = check('Maneuver##sk_maneuver_on', c.sections.maneuver.on)
        if changed then c.act.section('maneuver', on) end
        tip(TIP.maneuver)
    else
        imgui.AlignTextToFramePadding()
        text('Maneuver')
        tip(TIP.maneuver)
    end
    for i = 1, #m.picks do
        imgui.SameLine()
        choice_pick(c, '##sk_maneuver_' .. i, 'maneuver.slot_' .. i, m.picks[i] or '', m.choices, 'label', MANEUVER_W)
        tip(TIP.maneuver)
    end
end

-- Pet Control: 2.9.1's Pet Control and Pet Healing together, as Sidekick 3 switches them together.
local function pet_body(c)
    local pet = c.sections.pet
    if c.sections.maneuver then maneuver_row(c, pet ~= nil) end
    if pet then
        slider(c, 'Pet (HP%)', 'pet.heal', c.view.pet_heal, TIP.pet_hp)
        if c.view.pet_sends then
            local changed, on = check('Send at your target##sk_pet_at_t', c.view.pet_at_t == true)
            if changed then c.act.set('pet.at_t', on) end
            tip(TIP.pet_at_t)
        end
        section_rows(c, 'pet', pet)
    end
end

local function focus_body(c)
    local h = c.view.heal
    name_pick(c, 'Focus Target', 'heal.focus', h.focus, h.focus_names, TIP.focus_target)
    slider(c, 'Focus (HP%)', 'heal.focus_threshold', h.focus_threshold, 'For the focus member:\n' .. TIP.group_hp)
    slider(c, 'Focus Danger (HP%)', 'heal.focus_danger', h.focus_danger, 'For the focus member:\n' .. TIP.danger_hp)
    slider(c, 'Focus Critical (HP%)', 'heal.focus_critical', h.focus_critical, 'For the focus member:\n' .. TIP.critical_hp)
    if h.focus_threshold <= h.focus_danger then
        colored(YELLOW, 'Focus is at or under Focus Danger: the focus member gets danger heals only.')
    end
end

local function heal_body(c)
    local h = c.view.heal
    slider(c, 'Group (HP%)', 'heal.threshold', h.threshold, TIP.group_hp)
    slider(c, 'Danger (HP%)', 'heal.danger', h.danger, TIP.danger_hp)
    slider(c, 'Critical (HP%)', 'heal.critical', h.critical, TIP.critical_hp)
    if h.threshold <= h.danger then colored(YELLOW, 'Group is at or under Danger: no efficient heals, only danger ones.') end
    if slot_buttons(h.targets, 'heal_targets', function (tg) c.act.skip(tg.name, tg.on) end,
            function (tg) return game_text(tg.name) .. TIP.group_target end) then
        imgui.SameLine()
        text('Group Targets')
    end
    section_rows(c, 'heal', c.sections.heal)
    if h.stratagems then
        local changed, on = check('Hold a Stratagem for Healing##sk_heal_reserve', h.reserve)
        if changed then c.act.set('heal.reserve', on) end
        tip(TIP.reserve)
    end
end

local function wake_body() colored(GRAY, 'Wakes with a cure or waltz; an area one for two or more.') end

-- A debuff's checkbox for `whose` set (nil: everyone's); grey and dead while nothing that's on removes it.
local function debuff_check(c, r, whose)
    local on = r.on
    if whose and r.own and r.own[whose] ~= nil then on = r.own[whose] end
    local usable = r.usable ~= false
    tint(usable and NONE or LOCKED_CHECK)
    local changed, v = check(r.label .. '##sk_debuff_' .. (whose or '*') .. '_' .. r.key, on)
    untint()
    if changed and usable then c.act.debuff(r.key, v, whose) end
    tip(((r.action or '') ~= '' and ('Removed by ' .. r.action .. '\n') or '') .. cap(r.avail)
        .. (usable and '' or '\nCheck something above that removes it.'))
end

-- Which debuffs are worth removing (2.9.1's right-click Remove: lists): everyone's, or one player's own.
local function debuff_tree(c, s, debuffs)
    if not imgui.TreeNode('Debuffs to Remove##sk_debuffs') then return end
    opened('TreePop')
    local st = c.st
    local tabs = { { label = 'Everyone' } }
    for _, tg in ipairs(s.who or {}) do
        if tg.on and tg.name then tabs[#tabs + 1] = { label = tg.label, name = tg.name } end
    end
    local active = tabs[1]
    for _, t in ipairs(tabs) do
        if t.name and t.name == st.debuff_whose then active = t end
    end
    st.debuff_whose = active.name
    for i, t in ipairs(tabs) do
        if i > 1 then imgui.SameLine() end
        if chip_button(t.label, 'sk_whose_' .. (t.name or '*'), t == active and 'on' or 'off',
                t.name and game_text(t.name) or TIP.whose, not t.name and text_w(t.label) + 16 or nil) then
            st.debuff_whose = t.name
        end
    end
    local names = {}
    for i, r in ipairs(debuffs) do names[i] = r.key end
    if imgui.Button('None##sk_debuffs_none') then c.act.debuffs(names, false, active.name) end
    tip('Leave all of these debuffs on.')
    imgui.SameLine()
    if imgui.Button('All##sk_debuffs_all') then c.act.debuffs(names, true, active.name) end
    tip('Remove all of these debuffs.')
    -- Long lists in columns, as 2.9.1 split its Remove: list.
    if imgui.BeginTable('##sk_debuff_columns', #debuffs > 24 and 3 or #debuffs > 10 and 2 or 1, LIST_FLAGS, { 0, 0 }) then
        opened('EndTable')
        for _, r in ipairs(debuffs) do
            imgui.TableNextColumn()
            debuff_check(c, r, active.name)
        end
        close('EndTable')
    end
    close('TreePop')
end

-- Debuff Removal: who it runs on, its spells and abilities, the debuffs worth removing, then 2.9.1's item boxes.
local function remove_body(c)
    local s = c.sections.remove
    if slot_buttons(s.who, 'remove_who', function (tg) c.act.who(tg.name, not tg.on) end,
            function (tg) return member_help(c, tg.name, '\nTrust/Tracked Removal is not totally reliable') .. TIP.remove_target end) then
        imgui.SameLine()
        text('Removal Targets')
    end
    local removers, debuffs, items = {}, {}, {}
    for _, r in ipairs(s.rows) do
        table.insert(r.remover and removers or r.debuff and debuffs or items, r)
    end
    local rows, n = favorites_first(c, removers)
    for i, r in ipairs(rows) do
        check_row(c, 'remove', r, { help = r.shared and TIP.shared or nil })
        if r.doom_retries then slider(c, 'Doom Retries', 'remove.doom_retries', r.doom_retries, TIP.doom_retries) end
        divider(i, n, #rows)
    end
    if #debuffs > 0 then debuff_tree(c, s, debuffs) end
    if #items > 0 then
        imgui.Separator()
        for _, r in ipairs(items) do
            if r.count then item_row(c, 'remove', r) else check_row(c, 'remove', r, { no_favorite = true }) end
        end
    end
end

local function rest_body(c)
    local r = c.view.rest
    slider(c, 'Rest (MP%)', 'rest.mp', r.mp, TIP.rest_mp)
    slider(c, 'Distance (yalms)', 'rest.distance', r.distance, TIP.rest_distance)
end

local function recover_body(c)
    local r = c.view.recover
    slider(c, 'Self Recover (TP)', 'recover.tp', r.tp, TIP.recover_tp)
    local me = self_line(c.view)
    if me and me.uses_mp then slider(c, 'Self Recover (MP%)', 'recover.mp', r.mp, TIP.recover_mp) end
    if r.spends_tp then slider(c, 'Chivalry Min TP', 'recover.min_tp', r.min_tp, TIP.min_tp) end
    if r.devotion then name_pick(c, 'Devotion Target', 'recover.target', r.target or '', r.names, TIP.devotion_target, 'Lowest MP') end
    section_rows(c, 'recover', c.sections.recover)
end

local function roll_pick(c, label, path, current, r)
    choice_pick(c, label, path, current, r.choices, 'name', NAME_W, function (ch)
        return ('%s\nLucky %d, unlucky %d'):format(ch.label, ch.lucky, ch.unlucky)
    end)
    tip(TIP.roll_slot)
    for _, ch in ipairs(r.choices) do
        if ch.name == current then
            imgui.SameLine()
            colored(GREEN, ('(%d)'):format(ch.lucky))
        end
    end
end

local function roll_body(c)
    local r = c.view.roll
    roll_pick(c, 'Roll 1##sk_roll_first', 'roll.first', r.first, r)
    if r.two then roll_pick(c, 'Roll 2##sk_roll_second', 'roll.second', r.second, r) end
    width(SLIDER_W)
    if begin_combo('Risk Tier##sk_roll_risk', cap(r.risk)) then
        for _, risk in ipairs(r.risks) do
            local selected = risk == r.risk
            if imgui.Selectable(cap(risk) .. '##sk_roll_risk_' .. risk, selected) then c.act.set('roll.risk', risk) end
            if selected then imgui.SetItemDefaultFocus() end
        end
        end_combo()
    end
    unwidth()
    tip(TIP.risk)
    if r.two then
        local changed, on = check('Max Risk at 11##sk_roll_max_at_11', r.max_at_11)
        if changed then c.act.set('roll.max_at_11', on) end
        tip(TIP.max_at_11)
    end
end

-- 2.9.1's rune rows: Idle Runes, then each ward's checkbox, a drop-down per rune slot (by what the rune does).
local function rune_body(c)
    local r = c.view.rune
    local function rune_help(rn) return ('%s: adds %s, resists %s,\nagainst %s.'):format(rn.label, rn.element, rn.resist, rn.ailments) end
    for _, set in ipairs(r.sets) do
        if set.ward then
            local changed, on = check(set.label .. '##sk_rune_' .. set.key, set.on)
            if changed then c.act.row(set.ward, on) end
        else
            imgui.AlignTextToFramePadding()
            text('Idle Runes')
        end
        tip(TIP.runes)
        for i = 1, r.slots do
            if i == 1 then imgui.SameLine(RUNE_LABEL_W, 0) else imgui.SameLine(0, 4) end
            choice_pick(c, ('##sk_rune_%s_%d'):format(set.key, i), ('rune.%s_%d'):format(set.key, i), set.picks[i] or '',
                r.runes, set.shows, RUNE_W, rune_help)
        end
    end
end

local function buff_body(c)
    local s = c.sections.buff
    local rows, n = favorites_first(c, s.rows)
    for i, r in ipairs(rows) do
        buff_row(c, 'buff', r, s.has_mods)
        divider(i, n, #rows)
    end
end

-- A song's family: its name less a tier's numeral ('Valor Minuet IV' -> 'Valor Minuet').
local function song_family(name) return name:match('^(.-)%s+[IVX]+$') or name end

local function song_body(c)
    local m = c.view.song
    local families, family_of = {}, {}
    for _, ch in ipairs(m.choices) do
        local f = song_family(ch.name)
        family_of[ch.name] = f
        local fam = families[#families]
        if not (fam and fam.name == f) then
            fam = nil
            for _, x in ipairs(families) do
                if x.name == f then fam = x end
            end
            if not fam then
                fam = { name = f, tiers = {} }
                families[#families + 1] = fam
            end
        end
        fam.tiers[#fam.tiers + 1] = ch
    end
    for _, fam in ipairs(families) do song_row(c, m, fam, family_of) end
end

-- 2.9.1's Geo section: the luopan rows, Full Circle over its Distance and Timer, Blaze of Glory, then Entrust's.
local GEO_TAIL = { ['Full Circle'] = true, ['Blaze of Glory'] = true, Entrust = true }
local function geo_body(c)
    local s, g = c.sections.geo, c.view.geo
    local tail = {}
    for _, r in ipairs(s.rows) do
        if GEO_TAIL[r.key] then tail[r.key] = r
        elseif r.choices or r.targets then buff_row(c, 'geo', r, s.has_mods, true)
        else check_row(c, 'geo', r, { no_favorite = true }) end
    end
    if tail['Full Circle'] then check_row(c, 'geo', tail['Full Circle'], { no_favorite = true, help = TIP.full_circle }) end
    slider(c, 'Distance (yalms)', 'geo.distance', g.distance, TIP.geo_distance)
    slider(c, 'Timer (seconds)', 'geo.linger', g.linger, TIP.geo_timer)
    if tail['Blaze of Glory'] then check_row(c, 'geo', tail['Blaze of Glory'], { no_favorite = true, help = TIP.blaze }) end
    if tail.Entrust then check_row(c, 'geo', tail.Entrust, { no_favorite = true, help = TIP.entrust }) end
    if #g.indi > 0 then
        name_pick(c, 'Entrust Target', 'geo.entrust', g.entrust, g.names, TIP.entrust_target)
        name_pick(c, 'Entrust Spell', 'geo.entrust_spell', g.entrust_spell, g.indi, TIP.entrust_spell)
    end
end

local function revive_body(c) section_rows(c, 'revive', c.sections.revive) end

-- Sections -----------------------------------------------------------------------------------------

local function switch_of(id) return function (c, on) c.act.section(id, on) end end

-- Focus Healing is checked while there's a focus (or once checked, until one is picked).
local function set_focus(c, on)
    c.st.focus_armed = on
    if not on and c.view.heal.focus ~= '' then c.act.set('heal.focus', '') end
end

-- The sections 2.9.1 had, in its order, from the view's: { id, label, group, on, set(c, on), body(c), tip }.
local function sections_of(c)
    local by = c.sections
    local list = {}
    local function add(id, label, group, on, set, body, help)
        list[#list + 1] = { id = id, label = label, group = group, on = on == true, set = set, body = body, tip = help }
    end
    if by.follow then add('follow', 'Auto Follow', 'Utility', by.follow.on, switch_of('follow'), follow_body, TIP.follow) end
    local pet = by.pet or by.maneuver
    if pet then add('pet', 'Pet Control', 'Utility', pet.on, switch_of(pet.id), pet_body, TIP.pet) end
    if by.heal then
        add('focus', 'Focus Healing', 'Healing', c.view.heal.focus ~= '' or c.st.focus_armed, set_focus, focus_body, TIP.focus)
        add('heal', 'Group Healing', 'Healing', by.heal.on, switch_of('heal'), heal_body, TIP.group)
    end
    if by.wake and others_here(c.view) then add('wake', 'Sleep Removal', 'Healing', by.wake.on, switch_of('wake'), wake_body, TIP.wake) end
    if by.remove then add('remove', 'Debuff Removal', 'Support', by.remove.on, switch_of('remove'), remove_body, TIP.remove) end
    local me = self_line(c.view)
    if by.rest and me and me.uses_mp then add('rest', 'Resting', 'Utility', by.rest.on, switch_of('rest'), rest_body, TIP.rest) end
    if by.recover then add('recover', 'Resource Recovery', 'Utility', by.recover.on, switch_of('recover'), recover_body, TIP.recover) end
    if by.roll then add('roll', 'Rolls', 'Support', by.roll.on, switch_of('roll'), roll_body, TIP.rolls) end
    if by.rune then add('rune', 'Runes', 'Support', by.rune.on, switch_of('rune'), rune_body, TIP.runes) end
    if by.buff then add('buff', 'Buffs', 'Support', by.buff.on, switch_of('buff'), buff_body, TIP.buffs) end
    if by.song then add('song', 'Songs', 'Support', by.song.on, switch_of('song'), song_body, TIP.songs) end
    if by.geo then add('geo', 'Geo', 'Support', by.geo.on, switch_of('geo'), geo_body, TIP.geo) end
    if by.revive then add('revive', 'Revive', 'Support', by.revive.on, switch_of('revive'), revive_body, TIP.revive) end
    return list
end

-- 2.9.1's right-click on a header or tab: the layout in force, then all three.
local function display_menu(c, id)
    if begin_item_menu('##sk_display_' .. id) then
        for _, m in ipairs(MODES) do
            if m.value == c.mode then colored(GRAY, m.hint) end
        end
        imgui.Separator()
        for _, m in ipairs(MODES) do
            local current = m.value == c.mode
            if imgui.Selectable(m.label .. '##sk_mode_' .. id .. '_' .. m.value, current) and not current then
                c.mine.set('ui.classic_display', m.value)
            end
        end
        end_popup()
    end
end

local function body_of(c, s)
    indent()
    s.body(c)
    unindent()
end

-- A collapsing header with its checkbox before it; checking it opens it.
local function header_section(c, s)
    local changed, on = check('##sk_on_' .. s.id, s.on)
    if changed then
        s.set(c, on)
        if on then imgui.SetNextItemOpen(true) end
    end
    imgui.SameLine()
    tint(HEADER)
    local is_open = imgui.CollapsingHeader(s.label, DEFAULT_OPEN)
    untint()
    tip(s.tip)
    display_menu(c, s.id)
    if is_open and on then body_of(c, s) end
end

-- A tab: its checkbox at the top of its body; dimmed, and after the others, while off. Switching it on keeps it
-- selected as it moves; switching it off goes back to the tab before it (2.9.1's). The dimming wraps the whole tab
-- item, so scopes close in the order they opened; a tab that's off has nothing in it but its checkbox.
local function tab_section(c, s, t)
    tint(s.on and NONE or TAB_OFF)
    local selected = imgui.BeginTabItem(s.label .. '###sk_tab_' .. s.id .. (s.on and '' or '_off'), nil,
        TAB_NO_PUSH_ID + (t.reselect == s.id and TAB_SET_SELECTED or 0))
    if selected then
        opened('EndTabItem')
        if t.reselect == s.id then t.reselect = nil end
        if t.selected ~= s.id then t.previous, t.selected = t.selected, s.id end
    end
    tip(s.tip)
    display_menu(c, s.id)
    if selected then
        local changed, on = check(s.label .. '##sk_on_' .. s.id, s.on)
        if changed then
            s.set(c, on)
            local back = on and s.id or (t.previous ~= s.id and t.previous or nil)
            if on then t.autoselect = 2 end
            if back then t.reselect, t.frames = back, 4 end
        end
        imgui.Separator()
        if on then body_of(c, s) end
        close('EndTabItem')
    end
    untint()
end

local function select_group(st, group)
    if group == st.group then return end
    st.group = group
    local t = st.tabs
    t.selected, t.previous, t.reselect, t.frames, t.autoselect = nil, nil, nil, 0, 0
end

-- The sections, in the layout picked (2.9.1's display_mode): headers, tabs, or a page of tabs per group.
local function draw_sections(c, list)
    local st = c.st
    local t = st.tabs
    if t.reselect then
        t.frames = t.frames - 1
        if t.frames <= 0 then t.reselect = nil end
    end
    local shown = list
    if c.mode == 'groups' then
        local has = {}
        for _, s in ipairs(list) do has[s.group] = true end
        if not has[st.group] then
            for _, g in ipairs(GROUPS) do
                if has[g] then select_group(st, g); break end
            end
        end
        local any = false
        for _, g in ipairs(GROUPS) do
            if has[g] then
                if any then imgui.SameLine() end
                any = true
                local w, h = imgui.CalcTextSize(g)
                if imgui.Selectable(g .. '##sk_group_' .. g, st.group == g, 0, { num(w, #g * 7), num(h, 13) }) then select_group(st, g) end
            end
        end
        imgui.Separator()
        shown = {}
        for _, s in ipairs(list) do
            if s.group == st.group then shown[#shown + 1] = s end
        end
    end
    if c.mode == 'tabs' or c.mode == 'groups' then
        local bar = BAR_SCROLL
        if t.autoselect > 0 then
            t.autoselect = t.autoselect - 1
            bar = bar + BAR_AUTOSELECT
        end
        if imgui.BeginTabBar(c.mode == 'groups' and ('##sk_sections_' .. st.group) or '##sk_sections', bar) then
            opened('EndTabBar')
            for _, s in ipairs(shown) do
                if s.on then tab_section(c, s, t) end
            end
            for _, s in ipairs(shown) do
                if not s.on then tab_section(c, s, t) end
            end
            close('EndTabBar')
            return
        end
    end
    t.selected, t.previous, t.reselect, t.autoselect = nil, nil, nil, 0
    for _, s in ipairs(shown) do header_section(c, s) end
end

-- 2.9.1's right-click on the window's empty space: the size mode it isn't in. Not over a row whose own menu took the
-- click (a row's name is text, which ImGui doesn't count as an item).
local function size_menu(c)
    local id = '##sk_window_size'
    if not win.item_popup and imgui.IsMouseReleased(1) and imgui.IsWindowHovered() and not imgui.IsAnyItemHovered() then
        imgui.OpenPopup(id)
    end
    win.item_popup = false
    if begin_popup(id) then
        local custom = c.ui.classic_size == 'custom'
        colored(GRAY, SIZE_HINT[custom and 'custom' or 'auto'])
        imgui.Separator()
        if imgui.Selectable(custom and 'Fit window to contents' or 'Use a custom window size') then
            c.mine.set('ui.classic_size', custom and 'auto' or 'custom')
        end
        end_popup()
    end
end

-- The header: the profile button and the job, Start/Stop and the status, Track Target ---------------------------

local function profile_button(c)
    local v, st = c.view, c.st
    local zoning = v.status.halted == 'zoning'
    local active = v.profiles.active
    if not zoning and active ~= st.profile_last then
        st.profile_buf[1], st.profile_last = active or '', active
    end
    style(zoning and VAR_ALPHA or nil, 0.5)
    local clicked = imgui.Button((active or 'Default') .. '##sk_profile_btn', { BUTTON_W, 0 })
    unstyle()
    if clicked and not zoning then
        st.profile_buf[1] = active or ''
        imgui.OpenPopup('##sk_profiles')
    end
    tip(zoning and 'Profiles are unavailable while zoning.' or TIP.profiles)
    if zoning then return end
    if begin_popup('##sk_profiles') then
        width(238)
        imgui.InputText('##sk_profile_name', st.profile_buf, 64)
        unwidth()
        local typed = st.profile_buf[1]:match('^%s*(.-)%s*$')
        if imgui.Button('New##sk_profile_new') then
            c.act.new_profile()
            st.profile_buf[1] = ''
        end
        tip('Reset the working copy to job defaults.\nSaved profiles are kept.')
        imgui.SameLine()
        if imgui.Button('Save##sk_profile_save') then c.act.save_profile(typed) end
        tip('Save current settings under this name.\nWith a profile selected and the name edited: rename it instead.')
        imgui.SameLine()
        if imgui.Button('Save As##sk_profile_save_as') then c.act.save_profile(typed, true) end
        tip('Always save current settings under this name,\noverwriting any profile already using it.')
        imgui.SameLine()
        if imgui.Button('Delete##sk_profile_delete') and active then
            c.act.delete_profile(active)
            st.profile_buf[1] = ''
        end
        tip('Delete the selected (highlighted) profile.')
        local names = v.profiles.names or {}
        local line = num(imgui.GetTextLineHeightWithSpacing(), 17)
        child('##sk_profile_list', { 0, (#names + 1) * line + 16 })
        if imgui.Selectable('Default##sk_profile_default', active == nil, KEEP_POPUP) then
            c.act.profile(nil)
            st.profile_buf[1] = ''
        end
        for i, name in ipairs(names) do
            if imgui.Selectable(name .. '##sk_profile_' .. i, name == active, KEEP_POPUP) then
                c.act.profile(name)
                st.profile_buf[1] = name
            end
        end
        end_child()
        end_popup()
    end
end

local function right_edge()
    if not imgui.GetContentRegionMax then return nil end
    local x = imgui.GetContentRegionMax()
    return type(x) == 'number' and x or nil
end

-- 2.9.1's right-click on Start/Stop: when automation stops by itself (ui.load_stopped, ui.zone_stop). Yours only: an
-- alt's can't be set from here.
local function run_menu(c)
    if c.act ~= c.mine or not begin_item_menu('##sk_run_menu') then return end
    local changed, on = check('Load stopped##sk_load_stopped', c.ui.load_stopped ~= false)
    if changed then c.mine.set('ui.load_stopped', on) end
    tip('Always load with automation stopped.\nOff: load in whatever state you left it.')
    changed, on = check('Stop after zone##sk_zone_stop', c.ui.zone_stop == true)
    if changed then c.mine.set('ui.zone_stop', on) end
    tip('Stop automation whenever you change zones,\nlogging in and out too.')
    end_popup()
end

-- `widget`: drawn in the widget, which sizes itself to its contents, so Track Target keeps one place.
local function header(c, widget)
    local v = c.view
    profile_button(c)
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    colored(GREEN, job_line(v.job))
    local running = v.status.running == true
    if imgui.Button((running and 'Stop' or 'Start') .. '##sk_run', { BUTTON_W, 0 }) then c.act.run(not running) end
    run_menu(c)
    imgui.SameLine()
    local words, color = status_words(v)
    colored(color, words)
    tip(TIP.automation .. '\n\n' .. v.status.state .. ': ' .. v.status.text .. (v.status.dim and (' (' .. v.status.dim .. ')') or ''))
    local who = v.track.target
    if widget then
        local w = math.max(BUTTON_W + 8 + text_w(WIDEST_JOB), BUTTON_W + 16 + text_w('Automation mounted') + TRACK_W)
        imgui.SameLine(w - TRACK_W)
        if not who then imgui.Dummy({ TRACK_W, 0 }) end
    elseif who then
        local x = right_edge()
        if x and x > TRACK_W then imgui.SameLine(x - TRACK_W) else imgui.SameLine() end
    end
    if who then
        if imgui.Button('Track Target##sk_track', { TRACK_W, 0 }) then c.act.track(who) end
        tip(TIP.tracked)
    end
end

-- The tracked players, under the header: [T1 Name][X].
local function tracked_list(c)
    local gone
    local n = 0
    for _, list in ipairs({ c.view.party, c.view.alliance }) do
        for _, p in ipairs(list) do
            if p.tracked then
                if n > 0 then imgui.SameLine() end
                n = n + 1
                tint(LABEL_BUTTON)
                imgui.Button(p.tag .. ' ' .. game_text(p.name) .. '##sk_tracked_' .. p.name)
                untint()
                tip(p.job or (p.away and 'Out of range' or nil))
                imgui.SameLine(0, 2)
                if imgui.Button('X##sk_untrack_' .. p.name) then gone = p.name end
                tip('Stop tracking ' .. game_text(p.name))
            end
        end
    end
    if gone then c.act.untrack(gone) end
end

-- Windows ---------------------------------------------------------------------------------------------

local states = {}  -- per session ('' for yours, else its name), this session only
local function state(key)
    local st = states[key]
    if not st then
        st = { tabs = { frames = 0, autoselect = 0 }, group = GROUPS[1], focus_armed = false, profile_buf = { '' },
               song_tier = {} }
        states[key] = st
    end
    return st
end

local function opacity(u) return util.clamp(num(u and u.classic_opacity, 100), 1, 100) / 100 end

-- One frame's view of a session: its view and act, yours (`mine`, for this UI's own settings), its sections by id.
local function context(view, act, mine, u, key)
    local c = { view = view, act = act, mine = mine, ui = u, st = state(key), favs = favorites_of(u), sections = {},
                kinds = {} }
    local mode = u.classic_display
    c.mode = (mode == 'tabs' or mode == 'groups') and mode or 'headers'
    for _, s in ipairs(view.sections) do c.sections[s.id] = s end
    for _, list in ipairs({ view.party, view.alliance }) do
        for _, p in ipairs(list) do c.kinds[p.name] = p.kind end
    end
    return c
end

-- `title`'s window, `body()` inside; ImGui left balanced whatever the body raised, which is returned.
local function window(key, title, p_open, wflags, alpha, body)
    local base = #open
    style(alpha < 1 and VAR_ALPHA or nil, alpha)
    win.key, win.alpha, win.item_popup = key, alpha, false
    local depth = #open
    local ok, err = true, nil
    if imgui.Begin(title, p_open, wflags) then
        ok, err = pcall(body)
        if not ok then unwind(depth) end
    end
    imgui.End()
    unwind(base)
    win.key, win.alpha = '', 1
    return not ok and err or nil
end

local shown_before, shown_now = {}, {}

-- A window opening: uncollapsed and in front (it may come up behind a bigger one), with no popup left from the last
-- time it was up.
local function opening(key)
    shown_now[key] = true
    if shown_before[key] then return end
    was_open[key] = nil
    imgui.SetNextWindowCollapsed(false)
    imgui.SetNextWindowFocus()
end

local function config_body(c, with_header)
    if with_header then header(c, false) end
    tracked_list(c)
    draw_sections(c, sections_of(c))
    size_menu(c)
end

-- Your Sidekick Configuration (`r` nil), or another session's (`r` from view.remote, the `index`th open).
local function config_window(view, act, r, index)
    local key = r and ('cfg|' .. r.name) or 'cfg|'
    local custom = view.ui.classic_size == 'custom'
    if custom then imgui.SetNextWindowSizeConstraints({ MIN_W, MIN_H }, { FLT_MAX, FLT_MAX }) end
    if r then imgui.SetNextWindowPos({ 100 + index * 36, 100 + index * 36 }, ImGuiCond_FirstUseEver) end
    opening(key)
    local p_open = { true }
    local title = r and ('Sidekick Configuration: %s###sk_classic_%s'):format(r.name, r.name) or 'Sidekick Configuration'
    local err = window(key, title, p_open, custom and 0 or AUTO_SIZE, opacity(view.ui), function ()
        if not r then return config_body(context(view, act, act, view.ui, ''), not view.ui.widget) end
        if r.view and not r.other then
            return config_body(context(r.view, act.remote(r.name), act, view.ui, r.name), true)
        end
        colored(GRAY, r.other and (r.name .. ' runs another version of Sidekick: /addon reload sidekick there.')
            or ('Waiting for ' .. r.name .. '\'s session...'))
    end)
    if not p_open[1] then
        if r then act.watch(r.name, false) else act.settings(false) end
    end
    return err
end

local widget_open = { true }  -- Ashita drops Begin's flags unless p_open is a table; with no title bar it's never closed

local function widget_window(view, act)
    opening('widget')
    return window('widget', 'Sidekick Widget', widget_open, WIDGET_FLAGS, opacity(view.ui), function ()
        header(context(view, act, act, view.ui, ''), true)
    end)
end

-- The Party State panel ---------------------------------------------------------------------------

local LOW = RED

local function job_cell(job) return job and (job:gsub(' ', '')) or '--' end  -- 'WHM 75 / BLM 37' -> 'WHM75/BLM37'

local function status_cell(p)
    if not p.alive and not p.away then return 'Dead' end
    if p.away then return p.kind == 'tracked' and 'Out of range' or 'Away' end
    if p.session then return p.session.running and 'SK running' or 'SK stopped' end
    return '--'
end

-- One line of the table in `color` (low HP and MP in red over it). Returns whether its cell drew a tooltip.
local function member_row(slot, color, p, job)
    local drew = false
    imgui.TableNextRow()
    tint({ { COL.text, color } })
    imgui.TableNextColumn()
    text(slot)
    imgui.TableNextColumn()
    text(p.name and game_text(p.name) or '--')
    imgui.TableNextColumn()
    text(job_cell(job))
    imgui.TableNextColumn()
    tint((p.hpp or 100) <= 50 and { { COL.text, LOW } } or NONE)
    text(p.hpp and ('%d%%'):format(p.hpp) or '--')
    untint()
    imgui.TableNextColumn()
    local mp = p.uses_mp and p.kind ~= 'tracked'
    tint(mp and (p.mpp or 100) <= 40 and { { COL.text, LOW } } or NONE)
    text(mp and ('%d%%'):format(p.mpp or 0) or '--')
    untint()
    imgui.TableNextColumn()
    text(p.kind ~= 'tracked' and p.tp and tostring(p.tp) or '--')
    imgui.TableNextColumn()
    if p.buffs and p.buffs ~= '' then
        text(p.buffs)
        if p.buffs_all and imgui.IsItemHovered() then
            tooltip(p.buffs_all)
            drew = true
        end
    else
        text('--')
    end
    imgui.TableNextColumn()
    text(p.dist and p.dist ~= '' and p.dist or '--')
    imgui.TableNextColumn()
    text(p.status_text or status_cell(p))
    untint()
    return drew
end

local function legend()
    if imgui.BeginTooltip() == false then return end
    opened('EndTooltip')
    colored(BLUE, 'Alliance B')
    colored(GREEN, 'Alliance C')
    colored(YELLOW, 'Tracked Target')
    colored(GRAY, 'Pet')
    text('Trust NPC^')
    close('EndTooltip')
end

local COLUMNS = { { 'Slot', 34 }, { 'Name', 150 }, { 'Job', 100 }, { 'HP', 60 }, { 'MP', 60 }, { 'TP', 38 },
                  { 'Buffs', 200 }, { 'Distance', 70 }, { 'Status', 80 } }

local function party_table(view)
    local tipped = false
    if imgui.BeginTable('##sk_ps_table', #COLUMNS, TABLE_FLAGS, { 0, 0 }) then
        opened('EndTable')
        for _, col in ipairs(COLUMNS) do imgui.TableSetupColumn(col[1], COLUMN_FIXED, col[2]) end
        imgui.TableHeadersRow()
        local function row(slot, color, p, job) tipped = member_row(slot, color, p, job) or tipped end
        for _, p in ipairs(view.party) do
            if p.kind ~= 'tracked' then
                row(p.tag .. (p.kind == 'trust' and '^' or ''), WHITE, p, p.kind == 'self' and view.job or p.job)
                if p.kind == 'self' and view.pet then
                    local pet = view.pet
                    row('PET', GRAY, { name = pet.name, hpp = pet.hpp, mpp = pet.mpp, uses_mp = pet.uses_mp, tp = pet.tp,
                                       dist = pet.dist, alive = true, status_text = '--' })
                end
            end
        end
        for _, p in ipairs(view.alliance) do row(p.tag, p.tag:sub(1, 1) == 'B' and BLUE or GREEN, p, p.job) end
        for _, p in ipairs(view.party) do
            if p.kind == 'tracked' then row(p.tag, YELLOW, p, p.job) end
        end
        close('EndTable')
    end
    if not tipped and imgui.IsItemHovered() then legend() end  -- the table, as a whole
end

-- 2.9.1's /sk panel: the status line, the party, then its settings (Sidekick 3's global ones).
-- The theme drawing Sidekick, every character's on this PC (view.themes): Standard, this one, or another in ui/. One
-- that failed to load says so, why in its tooltip, and isn't taken.
local function theme_pick(view, act)
    local th = view.themes
    if not (th and th.list and th.list[1]) then return end
    local shown = ui.name
    for _, it in ipairs(th.list) do
        if it.key == th.current then shown = it.name end
    end
    width(DROPDOWN_W / 2)
    if begin_combo('Theme##sk_ps_theme', shown) then
        for _, it in ipairs(th.list) do
            local on = it.key == th.current
            if imgui.Selectable((it.error and it.name .. ' (failed to load)' or it.name) .. '##sk_ps_theme_' .. it.key, on)
                    and not on and not it.error then
                act.theme(it.key)
            end
            if on then imgui.SetItemDefaultFocus() end
            tip(it.error and 'Failed to load: ' .. it.error or it.file)
        end
        end_combo()
    end
    unwidth()
    tip(TIP.theme)
end

local function panel_body(view, act)
    local c = context(view, act, act, view.ui, '')
    local afk_on = c.sections.afk and c.sections.afk.on
    local afk
    if not afk_on then afk = 'off'
    elseif not view.status.running then afk = 'idle'
    elseif view.afk.asleep then afk = 'asleep'
    else afk = ('awake (%ds)'):format(num(view.afk.left, 0)) end
    text(table.concat({
        'Action: ' .. (view.recent[1] and view.recent[1].text or 'None'),
        'Moving: ' .. tostring(has_flag(view, 'moving')),
        'AFK: ' .. afk,
        'Target: ' .. (view.bt and game_text(view.bt.name) or 'None'),
    }, '   '))
    party_table(view)

    local changed, on = check('Debug Mode##sk_ps_debug', view.log)
    if changed then act.log(on) end
    tip(TIP.debug)
    imgui.SameLine(0, 20)
    changed, on = check('Hold AOE for Group##sk_ps_hold_aoe', view.buff.hold_aoe)
    if changed then act.set('buff.hold_aoe', on) end
    tip(TIP.hold_aoe)
    imgui.SameLine(0, 20)
    style(not view.buff.hold_aoe and VAR_ALPHA or nil, 0.5)
    changed, on = check('Gather Alert##sk_ps_gather', view.buff.gather)
    unstyle()
    if changed then act.set('buff.gather', on) end
    tip(TIP.gather)
    imgui.SameLine(0, 20)
    changed, on = check('Pianissimo Fast Casting##sk_ps_fast', view.song.fast)
    if changed then act.set('song.fast', on) end
    tip(TIP.fast)
    imgui.SameLine(0, 20)
    changed, on = check('Cast with 1 Shadow##sk_ps_one_shadow', view.buff.one_shadow)
    if changed then act.set('buff.one_shadow', on) end
    tip(TIP.one_shadow)

    int_field(c, 'Cure Potency +%', 'heal.cure_potency', view.heal.cure_potency, INT_W, TIP.cure_potency)
    imgui.SameLine(0, 20)
    int_field(c, 'Waltz Potency +%', 'heal.waltz_potency', view.heal.waltz_potency, INT_W, TIP.waltz_potency)
    imgui.SameLine(0, 20)
    int_field(c, 'Regen Potency +', 'heal.regen_potency', view.heal.regen_potency, INT_W, TIP.regen_potency)
    imgui.SameLine(0, 20)
    int_field(c, 'Song Duration (s)', 'song.duration', view.song.duration, INT_W, TIP.song_duration)

    -- Debug Mode's readout: what was sent, newest first.
    if view.log then
        text('Recent:')
        if #view.recent == 0 then text('  nothing sent yet') end
        for _, r in ipairs(view.recent) do text(('%4ds  %s  (%s)'):format(r.age, r.text, r.why)) end
    end

    changed, on = check('AFK Sleep##sk_ps_afk', afk_on)
    if changed then act.section('afk', on) end
    tip(TIP.afk)
    imgui.SameLine(0, 20)
    int_field(c, 'Timeout (minutes)', 'afk.minutes', view.afk.minutes, 80, TIP.afk_minutes)
    imgui.SameLine(0, 20)
    local fade = { math.floor(opacity(view.ui) * 100 + 0.5) }
    width(460)
    if imgui.SliderInt('UI Opacity##sk_ps_opacity', fade, 1, 100) then act.set('ui.classic_opacity', fade[1]) end
    unwidth()
    tip(TIP.opacity)
    imgui.SameLine(0, 20)
    changed, on = check('Japanese Client##sk_ps_japanese', view.japanese)
    if changed then act.set('japanese', on) end
    tip(TIP.japanese)
    imgui.SameLine(0, 20)
    theme_pick(view, act)
end

local function panel_window(view, act)
    opening('panel')
    local p_open = { true }
    local err = window('panel', 'Sidekick: Party State', p_open, ImGuiWindowFlags_AlwaysAutoResize, 1, function ()
        panel_body(view, act)
    end)
    if not p_open[1] then act.close() end  -- /sk hud shows it again
    return err
end

-- One frame: each window that's up, apart from the others. An error in one is raised once every window is ended.
function ui.render(view, act)
    lang.drawable = view.japanese ~= true  -- ImGui's own font: the view stays English (names still go out in Japanese)
    if #open > 0 then open = {} end
    shown_before, shown_now = shown_now, {}
    local err = view.ui.open and panel_window(view, act) or nil
    if view.ui.widget then err = widget_window(view, act) or err end
    if view.ui.settings then err = config_window(view, act, nil, 0) or err end
    for i, r in ipairs(view.remote or {}) do err = config_window(view, act, r, i) or err end
    if err then error(err, 0) end
end

return ui
