-- Weakness on the party player at full, then taken off: left at 25%, Sidekick reads their own max HP again and heals
-- them. The status read from the client's icons, no max kept while it stands (tests/e2e/max_hp.lua).
package.loaded['tests.e2e.max_hp'] = nil  -- edits take effect, as the runner reloads a scenario
return require('tests.e2e.max_hp')('party', 'weakness')
