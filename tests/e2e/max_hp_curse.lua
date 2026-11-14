-- Curse on the party player at full, then taken off: left between their danger line and threshold, where efficient
-- healing's band missed them while the max seen under it was kept (tests/e2e/max_hp.lua).
package.loaded['tests.e2e.max_hp'] = nil  -- edits take effect, as the runner reloads a scenario
return require('tests.e2e.max_hp')('party', 'curse')
