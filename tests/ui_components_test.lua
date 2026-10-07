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

local GROUPS = { Healing = true, Support = true, Utility = true };

-- One begin_sections call with a recording imgui. click_group is the group button
-- that reports a click this frame.
local function render_sections(settings, click_group)
    local frame = { tab_bars = {}, tab_items = {}, group_choices = {}, group_sizes = {}, headers = 0 };
    fake.imgui = {
        -- Ashita's binding returns width and height as two numbers.
        CalcTextSize = function(label) return #label * 8, 12; end,
        Selectable = function(label, _, flags, size)
            if GROUPS[label] then
                assert_eq(type(flags), 'number');
                assert(size and type(size[1]) == 'number' and size[1] > 0,
                    'group selectables need an explicit hit-box width');
                assert(type(size[2]) == 'number' and size[2] > 0,
                    'group selectables need an explicit hit-box height');
                frame.group_choices[#frame.group_choices + 1] = label;
                frame.group_sizes[label] = size[1];
                return label == click_group;
            end
            return false;
        end,
        BeginTabBar = function(id)
            frame.tab_bars[#frame.tab_bars + 1] = id;
            return true;
        end,
        BeginTabItem = function(label)
            frame.tab_items[#frame.tab_items + 1] = label;
            return false;
        end,
        CollapsingHeader = function()
            frame.headers = frame.headers + 1;
            return false;
        end,
    };

    local ctx = { settings = settings, save_callback = function() end };
    components.begin_sections(ctx);
    return ctx, frame;
end

-- A full frame submitting the given sections, so the next begin_sections knows
-- which groups this "job" has.
local function render_frame(settings, sections)
    local ctx = render_sections(settings);
    for _, setting_name in ipairs(sections) do
        components.begin_section(ctx, setting_name, setting_name, true);
    end
    components.end_sections(ctx);
end

test('the header layout renders headers and no tab bar', function()
    fake.reset();
    local ctx, frame = render_sections({ display_mode = 'headers' });
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(ctx.section_mode, 'headers');
    assert_eq(ctx.section_page, nil);
    assert_eq(frame.tab_bars, {});
    assert_eq(frame.headers, 1);
    components.end_sections(ctx);
end);

test('the tab layout still includes sections from each group', function()
    fake.reset();
    local ctx, frame = render_sections({ display_mode = 'tabs' });
    components.begin_section(ctx, 'Focus Healing', 'focus_enabled', true);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(ctx.section_mode, 'tabs');
    assert_eq(frame.tab_bars, { '##sk_sections' });
    assert_eq(#frame.tab_items, 2);
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
    render_frame(settings, { 'focus_enabled', 'debuff_removal_enabled', 'follow_enabled', 'new_feature_enabled' });

    local ctx, frame = render_sections(settings, 'Support');
    assert_eq(ctx.section_mode, 'tabs');
    assert_eq(ctx.section_page, 'Support');
    assert_eq(frame.group_choices, { 'Healing', 'Support', 'Utility' });
    assert_eq(frame.group_sizes, { Healing = 56, Support = 56, Utility = 56 },
        'button click targets should match the measured label widths');
    assert_eq(frame.tab_bars, { '##sk_sections_Support' });
    assert_eq({ components.begin_section(ctx, 'Focus Healing', 'focus_enabled', true) }, { false, false });
    components.begin_section(ctx, 'Debuff Removal', 'debuff_removal_enabled', true);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    components.begin_section(ctx, 'Future Feature', 'new_feature_enabled', true);
    assert_eq(frame.tab_items, { 'Debuff Removal###debuff_removal_enabled' });
    components.end_sections(ctx);

    ctx, frame = render_sections(settings, 'Utility');
    assert_eq(ctx.section_page, 'Utility');
    assert_eq(frame.tab_bars, { '##sk_sections_Utility' });
    components.begin_section(ctx, 'Debuff Removal', 'debuff_removal_enabled', true);
    components.begin_section(ctx, 'Future Feature', 'new_feature_enabled', true);
    assert_eq(frame.tab_items, { 'Future Feature###new_feature_enabled' });
    components.end_sections(ctx);
end);

test('a group with no sections gets no button and does not stay on show', function()
    fake.reset();
    local settings = { display_mode = 'groups' };
    render_frame(settings, { 'focus_enabled' });
    local ctx = render_sections(settings, 'Healing');
    assert_eq(ctx.section_page, 'Healing');
    components.end_sections(ctx);

    -- A job change to one without healing: the Healing page has nothing to show.
    render_frame(settings, { 'debuff_removal_enabled', 'follow_enabled' });
    local frame;
    ctx, frame = render_sections(settings);
    assert_eq(frame.group_choices, { 'Support', 'Utility' });
    assert_eq(ctx.section_page, 'Support');
    assert_eq(frame.tab_bars, { '##sk_sections_Support' });
    components.end_sections(ctx);
end);

test('button groups can be enabled from the section layout menu', function()
    fake.reset();
    local settings = { display_mode = 'headers', focus_enabled = true, follow_enabled = true };
    fake.imgui = {
        BeginPopupContextItem = function() return true; end,
        Selectable = function(label)
            return label == 'Display as button groups';
        end,
        CollapsingHeader = function() return false; end,
    };

    local ctx = { settings = settings, save_callback = function() end };
    components.begin_sections(ctx);
    components.begin_section(ctx, 'Focus Healing', 'focus_enabled', true);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    components.end_sections(ctx);
    assert_eq(settings.display_mode, 'headers', 'the mode change waits until the next frame');

    local frame;
    ctx, frame = render_sections(settings, 'Healing');
    assert_eq(settings.display_mode, 'groups');
    assert_eq(frame.group_choices, { 'Healing', 'Utility' });
    assert_eq(ctx.section_page, 'Healing');
    assert_eq(ctx.section_mode, 'tabs');
    assert_eq(frame.tab_bars, { '##sk_sections_Healing' });
    components.end_sections(ctx);
end);

-- Keep file-local ImGui popup state from leaking into later test files.
components.reset_opaque_tracking();
fake.reset();
