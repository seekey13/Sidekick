-- Weakness on the alliance player at full, then taken off. Their statuses come from packets: read, no max is kept;
-- missed, the max seen under it is dropped once their HP and HP% disagree with it (tests/e2e/max_hp.lua).
package.loaded['tests.e2e.max_hp'] = nil  -- edits take effect, as the runner reloads a scenario
return require('tests.e2e.max_hp')('alliance', 'weakness')
