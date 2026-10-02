local fake = require('tests.ashita');

ImGuiPopupFlags_MouseButtonRight = 1;
ImGuiPopupFlags_NoOpenOverItems = 2;
ImGuiStyleVar_WindowPadding = 1;
ImGuiTabBarFlags_FittingPolicyScroll = 1;
ImGuiTabBarFlags_AutoSelectNewTabs = 2;
ImGuiTabItemFlags_NoPushId = 1;
ImGuiTabItemFlags_SetSelected = 2;
ImGuiCol_Text = 1;
ImGuiCol_Tab = 2;
ImGuiCol_TabHovered = 3;
ImGuiCol_TabActive = 4;
ImGuiCol_TabUnfocused = 5;
ImGuiCol_TabUnfocusedActive = 6;
ImGuiCol_Header = 7;
ImGuiCol_HeaderHovered = 8;
ImGuiCol_HeaderActive = 9;
ImGuiTreeNodeFlags_DefaultOpen = 1;

local components = require('lib.ui.components');

local function render_sections(settings, click_group)
    local tab_bars, tab_items, group_choices, group_sizes = {}, {}, {}, {};
    local header_count = 0;
    fake.imgui = {
        CalcTextSize = function(label) return { x = #label * 8, y = 12 }; end,
        Selectable = function(label, selected, flags, size)
            if label == 'Healing' or label == 'Support' or label == 'Utility' then
                assert(size and size.x > 0, 'group selectables need explicit hit-box widths');
                group_choices[#group_choices + 1] = label;
                group_sizes[label] = size.x;
                return label == click_group;
            end
            return false;
        end,
        BeginTabBar = function(id)
            tab_bars[#tab_bars + 1] = id;
            return true;
        end,
        BeginTabItem = function(label)
            tab_items[#tab_items + 1] = label;
            return false;
        end,
        CollapsingHeader = function()
            header_count = header_count + 1;
            return false;
        end,
    };

    local ctx = { settings = settings, save_callback = function() end };
    components.begin_sections(ctx);
    return ctx, tab_bars, tab_items, group_choices, function() return header_count end, group_sizes;
end

test('the default header layout stays the default', function()
    fake.reset();
    local ctx, tab_bars, _, _, header_count = render_sections({ display_mode = 'headers' });
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(ctx.section_mode, 'headers');
    assert_eq(tab_bars, {});
    assert_eq(header_count(), 1);
    components.end_sections(ctx);
end);

test('the original tab layout still includes sections from each group', function()
    fake.reset();
    local ctx, tab_bars, tab_items = render_sections({ display_mode = 'tabs' });
    components.begin_section(ctx, 'Focus Healing', 'focus_enabled', true);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(ctx.section_mode, 'tabs');
    assert_eq(#tab_bars, 1);
    assert_eq(#tab_items, 2);
    components.end_sections(ctx);
end);

test('button groups filter tabs and keep unassigned future sections reachable', function()
    fake.reset();
    local settings = {
        display_mode = 'groups',
        focus_enabled = true,
        debuff_removal_enabled = true,
        follow_enabled = true,
        new_feature_enabled = true,
    };

    local ctx, tab_bars, tab_items, group_choices, _, group_sizes = render_sections(settings, 'Support');
    assert_eq(ctx.section_mode, 'tabs');
    assert_eq(ctx.section_page, 'Support');
    assert_eq(group_choices, { 'Healing', 'Support', 'Utility' });
    assert_eq(group_sizes, { Healing = 56, Support = 56, Utility = 56 },
        'button click targets should match the measured label widths');
    assert_eq(tab_bars, { '##sk_sections_Support' });
    assert_eq({ components.begin_section(ctx, 'Focus Healing', 'focus_enabled', true) }, { false, false });
    components.begin_section(ctx, 'Debuff Removal', 'debuff_removal_enabled', true);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(#tab_items, 1);
    components.end_sections(ctx);

    ctx, tab_bars, tab_items = render_sections(settings, 'Utility');
    assert_eq(ctx.section_page, 'Utility');
    assert_eq(tab_bars, { '##sk_sections_Utility' });
    components.begin_section(ctx, 'Future Feature', 'new_feature_enabled', true);
    assert_eq(#tab_items, 1);
    components.end_sections(ctx);
end);

test('button groups can be enabled from the section layout menu', function()
    fake.reset();
    local settings = { display_mode = 'headers', follow_enabled = true };
    fake.imgui = {
        BeginPopupContextItem = function() return true; end,
        Selectable = function(label)
            return label == 'Display as button groups';
        end,
        CollapsingHeader = function() return false; end,
    };

    local ctx = { settings = settings, save_callback = function() end };
    components.begin_sections(ctx);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    components.end_sections(ctx);
    assert_eq(settings.display_mode, 'headers', 'the mode change waits until the next frame');

    local tab_bar_id;
    fake.imgui = {
        CalcTextSize = function(label) return { x = #label * 8, y = 12 }; end,
        Selectable = function(label, selected, flags, size) return label == 'Healing'; end,
        BeginTabBar = function(id)
            tab_bar_id = id;
            return true;
        end,
    };
    components.begin_sections(ctx);
    assert_eq(settings.display_mode, 'groups');
    assert_eq(ctx.section_page, 'Healing');
    assert_eq(ctx.section_mode, 'tabs');
    assert_eq(tab_bar_id, '##sk_sections_Healing');
    components.end_sections(ctx);
end);

-- Keep file-local ImGui popup state from leaking into later test files.
components.reset_opaque_tracking();
fake.reset();
