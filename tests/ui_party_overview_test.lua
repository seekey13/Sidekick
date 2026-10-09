local fake = require('tests.ashita');

ImGuiPopupFlags_MouseButtonRight = 1;
ImGuiPopupFlags_NoOpenOverItems = 2;
ImGuiStyleVar_WindowPadding = 1;
ImGuiTreeNodeFlags_DefaultOpen = 1;

local common = require('lib.core.common');
local components = require('lib.ui.components');

test('the overview does no work while the setting is off', function()
    fake.reset();
    fake.imgui = {
        CollapsingHeader = function() error('disabled overview was rendered'); end,
    };
    components.render_party_overview({ settings = { party_overview_enabled = false } });
end);

test('the overview lists the active player, party, and sorted tracked targets once', function()
    fake.reset();
    common.game_state = {
        refreshed_at = os.clock(),
        player = { name = 'Main', server_id = 1, hpp = 95, hpp_valid = true, is_active = true },
        party = {
            [1] = { name = 'PartyMate', server_id = 2, hpp = 55, hpp_valid = true, is_active = true },
            [2] = { name = 'Duplicate', server_id = 1, hpp = 1, hpp_valid = true, is_active = true },
        },
        tracked = {
            [1] = { name = 'Zulu', server_id = 4, hpp = 90, hpp_valid = true, is_active = true },
            [2] = { name = 'Main copy', server_id = 1, hpp = 1, hpp_valid = true, is_active = true },
            [3] = { name = 'Alpha', server_id = 3, hpp = 20, hpp_valid = true, is_active = true },
            [5] = { name = 'Inactive', server_id = 5, hpp = 0, is_active = false },
        },
    };

    local names, hp_values, hp_colors, progress, child_end_count = {}, {}, {}, {}, 0;
    fake.imgui = {
        CollapsingHeader = function() return true; end,
        GetTextLineHeightWithSpacing = function() return 10; end,
        GetTextLineHeight = function() return 8; end,
        BeginChild = function(id, size)
            assert_eq(id, '##sk_party_overview');
            assert_eq(size, { 420, 40 });
            return true;
        end,
        Text = function(text) names[#names + 1] = text; end,
        TextColored = function(color, text)
            hp_colors[#hp_colors + 1] = color;
            hp_values[#hp_values + 1] = text;
        end,
        ProgressBar = function(value) progress[#progress + 1] = value; end,
        EndChild = function() child_end_count = child_end_count + 1; end,
    };

    components.render_party_overview({
        settings = { party_overview_enabled = true, critical_threshold = 30, heal_threshold = 75 },
    });

    assert_eq(names, { 'Main', 'PartyMate', 'Alpha', 'Zulu' });
    assert_eq(hp_values, { ' 95%', ' 55%', ' 20%', ' 90%' });
    assert_eq(hp_colors, { components.LIGHT_GREEN, components.LIGHT_YELLOW,
        components.LIGHT_RED, components.LIGHT_GREEN });
    assert_eq(progress, { 0.95, 0.55, 0.2, 0.9 });
    assert_eq(child_end_count, 1);
end);

test('unavailable HP is distinct from a valid zero percent member', function()
    fake.reset();
    common.game_state = {
        refreshed_at = os.clock(),
        player = { name = 'Unavailable', server_id = 1, hpp = 0, hpp_valid = false, is_active = true },
        party = {
            [1] = { name = 'Dead', server_id = 2, hpp = 0, hpp_valid = true, is_active = true },
        },
        tracked = {},
    };

    local names, unavailable, values, colors, progress = {}, {}, {}, {}, {};
    fake.imgui = {
        CollapsingHeader = function() return true; end,
        GetTextLineHeightWithSpacing = function() return 10; end,
        GetTextLineHeight = function() return 8; end,
        BeginChild = function() return true; end,
        Text = function(text) names[#names + 1] = text; end,
        TextDisabled = function(text) unavailable[#unavailable + 1] = text; end,
        TextColored = function(color, text)
            colors[#colors + 1] = color;
            values[#values + 1] = text;
        end,
        ProgressBar = function(value) progress[#progress + 1] = value; end,
        EndChild = function() end,
    };

    components.render_party_overview({ settings = { party_overview_enabled = true } });

    assert_eq(names, { 'Unavailable', 'Dead' });
    assert_eq(unavailable, { '--' });
    assert_eq(values, { '  0%' });
    assert_eq(colors, { components.LIGHT_RED });
    assert_eq(progress, { 0 });
end);
test('a render error leaves the child panel balanced through abort_sections', function()
    fake.reset();
    common.game_state = {
        refreshed_at = os.clock(),
        player = { name = 'Main', server_id = 1, hpp = 95, hpp_valid = true, is_active = true },
        party = {},
        tracked = {},
    };

    local child_end_count = 0;
    fake.imgui = {
        CollapsingHeader = function() return true; end,
        GetTextLineHeightWithSpacing = function() return 10; end,
        GetTextLineHeight = function() return 8; end,
        BeginChild = function() return true; end,
        ProgressBar = function() error('simulated UI error'); end,
        EndChild = function() child_end_count = child_end_count + 1; end,
    };

    local ok = pcall(function()
        components.render_party_overview({ settings = { party_overview_enabled = true } });
    end);
    assert_eq(ok, false);
    components.abort_sections();
    assert_eq(child_end_count, 1);
end);

test('the /sk panel checkbox saves the optional overview setting', function()
    fake.reset();
    common.game_state = {
        refreshed_at = os.clock(),
        player = nil,
        party = {},
        tracked = {},
        stratagems = 0,
        ready_charges = 0,
    };
    bit = require('bit');
    ImGuiWindowFlags_AlwaysAutoResize = 1;
    ImGuiTableFlags_Borders = 1;
    ImGuiTableFlags_RowBg = 2;
    ImGuiTableFlags_SizingFixedFit = 4;
    ImGuiTableFlags_NoHostExtendX = 8;

    local panel = require('lib.ui.panel');
    local saves = 0;
    panel.show();
    fake.imgui = {
        Begin = function() return true; end,
        BeginTable = function() return false; end,
        Checkbox = function(label, value)
            if label == 'Show Party Overview in Configuration' then
                value[1] = true;
                return true;
            end
            return false;
        end,
        IsItemHovered = function() return false; end,
    };

    local settings = { party_overview_enabled = false };
    panel.render(settings, function() saves = saves + 1; end);
    panel.hide();
    assert_eq(settings.party_overview_enabled, true);
    assert_eq(saves, 1);
end);

fake.reset();
