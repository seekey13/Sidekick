-- The scenarios tools/e2e.lua runs for 'all', in order: the quiet ones first, a job change near the end, a death last.
return { 'idle', 'heal', 'heal_self', 'heal_tracked', 'heal_alliance', 'remove', 'wake', 'doom', 'cursna_party',
         'cursna_alliance', 'cursna_tracked', 'buff', 'rest', 'job_change', 'revive' }
