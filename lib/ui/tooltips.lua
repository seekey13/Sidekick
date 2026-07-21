--[[
    Static help tooltip strings for the Sidekick Configuration UI.
    Shown via ui_components.item_tooltip() or imgui.SetTooltip()
    when hovering the associated control. Lines are pre-wrapped
    (~40-50 chars) since imgui.SetTooltip does not word-wrap.
    A few carry %s placeholders and are string.format'ed at the
    call site; %% is a literal percent (SetTooltip is printf-style).
]]--

return {
    automation_status =
        'Start/Stop toggles all Sidekick automation.\n' ..
        'Status shows why it may be paused:\n' ..
        '- Loading: waiting for job data\n' ..
        '- Mounted: automation suspended\n' ..
        '- Dead: automation suspended\n' ..
        '- Resting: recovering MP (only rest-stop logic runs)\n' ..
        '- Paused: combat is currently blocked\n' ..
        '- Running: fully active',

    tracked_targets =
        'Tracks a player outside your party/alliance.\n' ..
        'Some abilities are disabled on targets outside\n' ..
        'the party (heal, buff, wake, debuff removal)\n' ..
        'can affect tracked targets, and removal/wake\n' ..
        'on them is less reliable than on party members.\n' ..
        'Sidekick will /check the player to get their level\n' ..
        'for spell sizing, as exact HP is not available.\n',

    multisend_follow =
        'Movement mode switch. ON: use the Multisend\n' ..
        'plugin\'s follow (shows Attack Range in /sk)\n' ..
        'and disables the native Follow feature.\n' ..
        'OFF: use native Follow and hide Attack Range.\n' ..
        'The two never run at once.',

    attack_range =
        'Requires the Multisend plugin (/ms).\n' ..
        'While in combat, Sidekick disables Multisend\n' ..
        'follow once you\'re within the set distance\n' ..
        'of your battle target (<bt>), and re-enables\n' ..
        'follow if you fall outside it or leave combat.\n' ..
        '\'Off\' stops this behavior.',

    focus_healing =
        'Gives one party/tracked/alliance member their\n' ..
        'own HP%% healing threshold (usually higher),\n' ..
        'checked before the Group threshold.\n' ..
        'The Focus Target also gets priority for\n' ..
        'Debuff Removal over other members.',

    group_healing =
        'When a group member\'s HP drops below this %%,\n' ..
        'Sidekick casts a heal sized to their missing HP\n' ..
        '(largest spell that won\'t overheal, or the\n' ..
        'smallest available if none fit).\n\n' ..
        'Check Targets picks who is scanned. Party and\n' ..
        'tracked members are ON by default; alliance\n' ..
        '(B/C) members are OFF by default. Toggle any\n' ..
        'button to include/exclude that person. These\n' ..
        'choices are per-session and reset each load.',

    critical_hp =
        'Critical abilities use their own (normally\n' ..
        'lower) threshold. If ANY group member drops\n' ..
        'below this %%, Sidekick uses one of these abilities\n' ..
        'first - before Focus or Group healing.',

    aoe_healing =
        'When the group\'s average HP falls below this %%\n' ..
        'AND at least 2 members are below it, Sidekick\n' ..
        'casts the checked AOE healing spell(s) instead\n' ..
        'of single-target heals.\n\n' ..
        'AOE healing is party-scoped (Curaga-style), so\n' ..
        'Check Targets only lists ME and party members.\n' ..
        'All are ON by default; toggle a button to\n' ..
        'exclude that person from the average. These\n' ..
        'choices are per-session and reset each load.',

    pet_healing =
        'When your pet\'s HP falls below this %%,\n' ..
        'Sidekick casts the checked pet-healing ability.',

    sleep_removal =
        'Scans party, tracked, and alliance members\n' ..
        '(never yourself) for Sleep/Sleep II.\n' ..
        '2+ asleep -> uses an AOE wake spell.\n' ..
        'Otherwise wakes the first sleeper (your Focus\n' ..
        'Target preferred) with the cheapest option.',

    debuff_removal =
        'Removes debuffs using abilities matched to\n' ..
        'specific status IDs. Priority: yourself, then\n' ..
        'your Focus Target, then whichever selected\n' ..
        'member has the most removable debuffs.',

    item_removal =
        'Auto-uses consumables on yourself to cure\n' ..
        'status ailments, independent of spell-based\n' ..
        'removal. Only shows items you are carrying.\n' ..
        'Limited to once per 4s; never fires while moving.',

    resting =
        'While idle (not moving/casting/engaged) and\n' ..
        'MP < 100%%, Sidekick waits Timer seconds after\n' ..
        'conditions become favorable, then sends\n' ..
        '/heal on. Stops (/heal off) at full MP, casting,\n' ..
        'or if Follow Target exceeds Distance.',

    rest_timer =
        'Seconds to wait after conditions first become\n' ..
        'favorable (idle, not casting, MP < 100%%)\n' ..
        'before Sidekick starts resting.',

    rest_follow_target =
        'Party member whose distance from you is\n' ..
        'watched while resting. If they move beyond\n' ..
        'the Distance below, resting stops (and won\'t\n' ..
        'start) so you aren\'t left behind.',

    rest_distance =
        'Max distance (yalms) from the Follow Target\n' ..
        'before resting is stopped or blocked from\n' ..
        'starting.',

    follow =
        'Auto-follows a party member when they move\n' ..
        'away. Sends /follow once they pass the\n' ..
        'Distance below; healing and every other\n' ..
        'support action always take priority. Off by\n' ..
        'default -- Sidekick never moves you unless\n' ..
        'this is enabled.',

    follow_target =
        'Party member to follow. Switching targets\n' ..
        'stops running at the old one and follows the\n' ..
        'new one. Also used as the Resting distance\n' ..
        'watch target below.',

    follow_distance =
        'Distance (yalms) the Follow Target must pass\n' ..
        'before Sidekick sends /follow. The client\n' ..
        'holds position once you catch up.',

    afk_sleep =
        'Pauses automation after the Timeout with no\n' ..
        'party movement or combat. Move to resume.',

    resource_recovery =
        'Self Recover (TP/MP%%) casts the checked\n' ..
        'abilities when your TP/MP drops below the\n' ..
        'set value. Chivalry Min TP holds back TP-cost\n' ..
        'MP recovery until your TP reaches that amount.\n' ..
        'If a Recovery Target is set, Devotion is used\n' ..
        'on them when THEIR MP drops below Target\n' ..
        'Recover %%.',

    buffs =
        'For each checked buff, Sidekick checks the\n' ..
        'target\'s active buff IDs. If the configured\n' ..
        'ability\'s buff IDs is missing, it casts the\n' ..
        'spell/ability on that target (self, party/alliance,\n' ..
        'or Tracked). Grouped buffs let you pick one\n' ..
        'option; Bard will automatically use a target-\n' ..
        'modifier ability (e.g. Pianissimo) first.',

    rolls =
        'Corsair automation: keeps the two rolls below\n' ..
        'active and uses Double-Up on each until it is\n' ..
        'good enough. While Bust is up only one roll slot\n' ..
        'is used, so Sidekick holds off recasting the other.',

    roll_slot =
        'Roll cast in this slot. Changing it clears the\n' ..
        'tracked totals so the old roll\'s result can\'t\n' ..
        'carry over. Set to None to leave the slot unused.',

    risk_tier =
        'How far Double-Up chases a total. Every tier\n' ..
        'doubles at 5 or less (no die can bust) unless it\n' ..
        'is already on the lucky number, never doubles at\n' ..
        '11, and all three use Snake Eye at 10 for a\n' ..
        'guaranteed 11.\n' ..
        'Lowest: banks lucky, stops at 6+, never takes a\n' ..
        'bust chance.\n' ..
        'Medium: banks lucky, chases it while it is still\n' ..
        'one die away, and rerolls off the unlucky number.\n' ..
        'Highest: 11 or nothing -- it rolls straight past\n' ..
        'the lucky number, and keeps doubling at 6-10\n' ..
        'whenever Fold is up to undo a Bust (otherwise it\n' ..
        'plays like Medium). Expect to give up lucky often.\n' ..
        'Fold is always used the moment you Bust.',

    geo =
        'Geomancer automation: automatically triggers\n' ..
        'Full Circle if your luopan is out of range, and\n' ..
        'casts an Indi spell on a party member via Entrust.',

    geo_distance =
        'If your luopan drifts beyond this many yalms\n' ..
        'from the selected Geo target, Sidekick uses Full Circle\n' ..
        'to recall it and recast once stationary. Skipped\n' ..
        'when no Geo target is selected in Buffs.',

    geo_bt_timer =
        'After your Geo-bt battle target dies, Sidekick waits\n' ..
        'this many seconds before Full Circle dismisses the\n' ..
        'luopan. If a new battle target appears in that window,\n' ..
        'the luopan is kept and reused instead.',

    geo_full_circle =
        'When checked, Sidekick uses Full Circle to\n' ..
        'recast your current Geo spell once the\n' ..
        'luopan exceeds the Distance threshold above.',

    geo_entrust_target =
        'Party member who will receive the Entrust-\n' ..
        'assisted Indi spell selected below.',

    geo_entrust_spell =
        'Indi spell Sidekick casts on the Entrust Target.\n' ..
        'Sidekick uses Entrust on itself first, then casts\n' ..
        'this spell on the target while Entrust is active.',

    geo_entrust_enable =
        'Enables the Entrust automation below, using\n' ..
        'the Target and Spell selected.',

    revive =
        'Scans party, tracked, and alliance members\n' ..
        'for 0 HP / dead status and casts a raise spell\n' ..
        '(checks range and buff prerequisites, e.g.\n' ..
        'Addendum: White). Raise spells are idle-only,\n' ..
        'so this won\'t trigger while you\'re in combat.',

    pianissimo_fast_casting =
        'Requires the Debuff addon (/debuff). Will precast with Pianissimo,\n' ..
        'but once casting starts issues /debuff 409 to remove Pianissimo.\n' ..
        'Result: faster cast and still an area song.',

    cast_with_1_shadow =
        'Requires the Debuff addon (/debuff). Recasts Utsusemi when you are\n' ..
        'down to 1 shadow (still blocks at 2+ shadows). Once casting starts\n' ..
        'issues /debuff 66 to clear the last shadow so the new set applies.',

    -- Recast-gated precast JA buttons (see render_recast_gate_button): each needs a
    -- button, Enable and Hold tip. Nether Void's take a %s noun -- its column covers
    -- both Absorb spells and the Drain/Aspir rows.
    nether_void_button =
        'Nether Void: fire Nether Void before this %s\n' ..
        'to boost its effect. Click to configure. Lit when enabled.',

    nether_void_enable =
        'Fire Nether Void before the selected %s.',

    nether_void_hold =
        'On: skip the %s until Nether Void is ready.\n' ..
        'Off (default): cast the %s without Nether Void when it is on cooldown.',

    diffusion_button =
        'Diffusion: fire Diffusion before this buff to spread it\n' ..
        'to the whole party. Click to configure. Lit when enabled.',

    diffusion_enable =
        'Fire Diffusion before this buff so it applies to the party.',

    diffusion_hold =
        'On: skip this buff until Diffusion is ready.\n' ..
        'Off (default): cast the buff self-only when Diffusion is on cooldown.',

    embolden_button =
        'Embolden: fire Embolden before this spell to boost\n' ..
        'its potency. Click to configure. Lit when enabled.',

    embolden_enable =
        'Fire Embolden before this spell so its effect is stronger.',

    embolden_hold =
        'On: skip this spell until Embolden is ready.\n' ..
        'Off (default): cast the spell unboosted when Embolden is on cooldown.',

    -- Enlightenment toggles rather than opening a popup, so it needs only the button
    -- tip: Enable is the click itself, and Hold is implicit.
    enlightenment_button =
        'Enlightenment: fire Enlightenment before this spell so it can\n' ..
        'be cast in Dark Arts without Addendum: White. Click to toggle.\n' ..
        'Lit when enabled. The spell waits until Enlightenment is ready.',
}
