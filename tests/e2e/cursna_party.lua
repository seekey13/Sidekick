-- Doom on the party player, Cursna until it's gone, Sidekick still acting after each (tests/e2e/cursna.lua).
package.loaded['tests.e2e.cursna'] = nil  -- edits take effect, as the runner reloads a scenario
return require('tests.e2e.cursna')('party')
