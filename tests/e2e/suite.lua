-- The scenarios tools/e2e.lua runs for 'all', in order: the quiet ones first, a job change near the end, a death last.
-- Not here, still run by name: doom (cursna_party checks all it does, and more).
return { 'idle', 'heal', 'heal_self', 'heal_tracked', 'heal_alliance', 'max_hp_weakness', 'max_hp_curse',
         'max_hp_alliance', 'remove', 'wake', 'charm_wake', 'cursna_party', 'cursna_alliance', 'cursna_tracked',
         'doom_count', 'charm_alliance', 'buff', 'rest', 'job_change', 'revive' }
