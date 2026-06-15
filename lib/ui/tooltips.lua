--[[
    Static help tooltip strings for the Medic Configuration UI.
    Shown via ui_components.item_tooltip() when hovering the
    associated control. Lines are pre-wrapped (~40-50 chars)
    since imgui.SetTooltip does not word-wrap.
]]--

return {
    automation_status =
        'Start/Stop toggles all Medic automation.\n' ..
        'Status shows why it may be paused:\n' ..
        '- Loading: waiting for job data\n' ..
        '- Mounted: automation suspended\n' ..
        '- Dead: automation suspended\n' ..
        '- Resting: recovering MP (only rest-stop logic runs)\n' ..
        '- Paused: combat is currently blocked\n' ..
        '- Running: fully active',

    tracked_targets =
        'Tracks a player outside your party/alliance.\n' ..
        'Only abilities marked to target outside\n' ..
        'the party (heal, buff, wake, debuff removal)\n' ..
        'can affect tracked targets, and removal/wake\n' ..
        'on them is less reliable than on party members.\n' ..
        'They must still be in range.',

    attack_range =
        'Requires the Multisend addon (/ms).\n' ..
        'While in combat, Medic disables Multisend\n' ..
        'follow once you\'re within this distance\n' ..
        'of your battle target (<bt>), and re-enables\n' ..
        'follow if you fall outside it or leave combat.\n' ..
        '\'Off\' leaves follow control to you/Multisend.',

    focus_healing =
        'Gives one party/tracked/alliance member their\n' ..
        'own HP% healing threshold (usually higher),\n' ..
        'checked before the Group threshold.\n' ..
        'The Focus Target also gets priority for\n' ..
        'Debuff Removal over other members.',

    group_healing =
        'When a group member\'s HP drops below this %,\n' ..
        'Medic casts a heal sized to their missing HP\n' ..
        '(largest spell that won\'t overheal, or the\n' ..
        'smallest available if none fit).',

    critical_hp =
        'Critical abilities use their own (normally\n' ..
        'lower) threshold. If ANY group member drops\n' ..
        'below this %, Medic uses one of these abilities\n' ..
        'first - before Focus or Group healing.',

    aoe_healing =
        'When the group\'s average HP falls below this %\n' ..
        'AND at least 2 members are below it, Medic\n' ..
        'casts the checked AOE healing spell(s) instead\n' ..
        'of single-target heals.',

    pet_healing =
        'When your pet\'s HP falls below this %,\n' ..
        'Medic casts the checked pet-healing ability.',

    sleep_removal =
        'Scans party, tracked, and alliance members\n' ..
        '(never yourself) for Sleep/Sleep II.\n' ..
        '2+ asleep -> uses a checked AOE wake spell.\n' ..
        'Otherwise wakes the first sleeper (your Focus\n' ..
        'Target preferred) with the cheapest option.',

    debuff_removal =
        'Removes debuffs using abilities matched to\n' ..
        'specific status IDs. Priority: yourself, then\n' ..
        'your Focus Target, then whichever selected\n' ..
        'member has the most removable debuffs.',

    item_silence_removal =
        'Also auto-uses this item on yourself when\n' ..
        'you have Silence, independent of the spell-\n' ..
        'based removal above. Limited to once per 4s.',

    item_doom_removal =
        'Also auto-uses this item on yourself when\n' ..
        'you have Doom, independent of the spell-\n' ..
        'based removal above. Limited to once per 4s.',

    resting =
        'While idle (not moving/casting/engaged) and\n' ..
        'MP < 100%, Medic waits Timer seconds after\n' ..
        'conditions become favorable, then sends\n' ..
        '/heal on. Stops at full MP, on movement/\n' ..
        'casting, or if Follow Target exceeds Distance.',

    rest_timer =
        'Seconds to wait after conditions first become\n' ..
        'favorable (idle, not casting, MP < 100%)\n' ..
        'before Medic starts resting.',

    rest_follow_target =
        'Party member whose distance from you is\n' ..
        'watched while resting. If they move beyond\n' ..
        'the Distance below, resting stops (and won\'t\n' ..
        'start) so you aren\'t left behind.',

    rest_distance =
        'Max distance (yalms) from the Follow Target\n' ..
        'before resting is stopped or blocked from\n' ..
        'starting.',

    resource_recovery =
        'Self Recover (TP/MP%) casts the checked\n' ..
        'abilities when your TP/MP drops below the\n' ..
        'set value. Chivalry Min TP holds back TP-cost\n' ..
        'MP recovery until your TP reaches that amount.\n' ..
        'If a Recovery Target is set, Devotion is cast\n' ..
        'on them when THEIR MP drops below Target\n' ..
        'Recover %, sharing your MP with them.',

    buffs =
        'For each checked buff, Medic checks the\n' ..
        'target\'s active buff IDs. If none of this\n' ..
        'ability\'s buff IDs are active, it casts the\n' ..
        'configured spell on that target (self, party,\n' ..
        'or Trust). Grouped buffs let you pick one\n' ..
        'option; some require a target-modifier spell\n' ..
        '(e.g. Pianissimo) cast first.',

    geo =
        'Geomancer automation: keeps your luopan in\n' ..
        'range via Full Circle, and optionally casts\n' ..
        'an Indi spell on a party member via Entrust.',

    geo_distance =
        'If your luopan drifts beyond this many yalms\n' ..
        'from you, Medic uses Full Circle to recall it\n' ..
        'and recast your active Geo spell.',

    geo_full_circle =
        'When checked, Medic uses Full Circle to\n' ..
        'recast your current Geo spell once the\n' ..
        'luopan exceeds the Distance threshold above.',

    geo_entrust_target =
        'Party member who will receive the Entrust-\n' ..
        'assisted Indi spell selected below.',

    geo_entrust_spell =
        'Indi spell Medic casts on the Entrust Target.\n' ..
        'Medic uses Entrust on itself first, then casts\n' ..
        'this spell on the target while Entrust is active.',

    geo_entrust_enable =
        'Enables the Entrust automation above, using\n' ..
        'the Target and Spell selected.',

    revive =
        'Scans party, tracked, and alliance members\n' ..
        'for 0 HP / dead status and casts a raise spell\n' ..
        '(checks range and buff prerequisites, e.g.\n' ..
        'Addendum: White). Raise spells are idle-only,\n' ..
        'so this won\'t trigger while you\'re in combat.',
}
