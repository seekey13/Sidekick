local fake = require('tests.ashita');

ImGuiPopupFlags_MouseButtonRight = 1;
ImGuiPopupFlags_NoOpenOverItems = 2;
ImGuiStyleVar_WindowPadding = 1;
ImGuiStyleVar_WindowRounding = 2;
ImGuiStyleVar_FrameRounding = 3;
ImGuiStyleVar_ItemSpacing = 4;
ImGuiStyleVar_Alpha = 5;
ImGuiTreeNodeFlags_DefaultOpen = 1;
ImGuiCol_Header = 1;
ImGuiCol_HeaderHovered = 2;
ImGuiCol_HeaderActive = 3;
ImGuiCol_Button = 4;
ImGuiCol_ButtonHovered = 5;
ImGuiCol_ButtonActive = 6;
ImGuiCol_Tab = 7;
ImGuiCol_TabHovered = 8;
ImGuiCol_TabActive = 9;
ImGuiCol_TabUnfocused = 10;
ImGuiCol_TabUnfocusedActive = 11;
ImGuiCol_CheckMark = 12;
ImGuiCol_SliderGrab = 13;
ImGuiCol_SliderGrabActive = 14;
ImGuiCol_WindowBg = 15;
ImGuiCol_ChildBg = 16;
ImGuiCol_TitleBg = 17;
ImGuiCol_TitleBgActive = 18;
ImGuiCol_TitleBgCollapsed = 19;
ImGuiCol_Border = 20;
ImGuiCol_Text = 21;
ImGuiCol_FrameBg = 22;
ImGuiCol_ScrollbarBg = 23;
ImGuiCol_ScrollbarGrab = 24;
ImGuiCol_ScrollbarGrabHovered = 25;
ImGuiCol_ScrollbarGrabActive = 26;
ImGuiWindowFlags_AlwaysAutoResize = 1;
ImGuiWindowFlags_NoResize = 2;
ImGuiWindowFlags_NoTitleBar = 4;
ImGuiTableFlags_Borders = 1;
ImGuiTableFlags_RowBg = 2;
ImGuiTableFlags_SizingFixedFit = 4;
ImGuiTableFlags_NoHostExtendX = 8;
ImGuiColorEditFlags_NoInputs = 1;

local common = require('lib.core.common');
local components = require('lib.ui.components');
local ui_config = require('lib.ui.config');

test('no saved accent leaves the current ImGui colors alone', function()
    fake.reset();
    local pushed = 0;
    fake.imgui = { PushStyleColor = function() pushed = pushed + 1; end };
    assert_eq(components.push_ui_accent({}), 0);
    components.pop_ui_accent(0);
    assert_eq(pushed, 0);
end);

test('custom accents are normalized and applied to UI controls', function()
    fake.reset();
    local settings = {};
    assert_eq(components.set_ui_accent_color(settings, { 1.2, -0.1, 0.5, 0.4 }), true);
    assert_eq(settings.ui_accent_color, { 1, 0, 0.5, 0.4 });
    assert_eq(components.get_ui_accent_color(settings), { 1, 0, 0.5, 0.4 });
    assert_eq(components.set_ui_accent_color(settings, { 0.1, 'bad', 0.2, 1 }), false);
    assert_eq(settings.ui_accent_color, { 1, 0, 0.5, 0.4 });

    local pushed, popped = {}, nil;
    fake.imgui = {
        PushStyleColor = function(color_id, color)
            pushed[#pushed + 1] = { color_id, color };
        end,
        PopStyleColor = function(count) popped = count; end,
    };
    local count = components.push_ui_accent({ ui_accent_color = { 0.2, 0.4, 0.8, 0.5 } });
    assert_eq(count, 14);
    assert_eq(#pushed, 14);
    assert_eq(pushed[1], { ImGuiCol_Header, { 0.2, 0.4, 0.8, 0.09 } });
    assert_eq(pushed[12], { ImGuiCol_CheckMark, { 0.2, 0.4, 0.8, 0.5 } });
    components.pop_ui_accent(count);
    assert_eq(popped, 14);

    settings.ui_accent_color = { 0.2, 0.4, 0.8, 0 / 0 };
    assert_eq(components.get_ui_accent_color(settings), nil);
end);

test('section headers retain their original colors until an accent is selected', function()
    fake.reset();
    local pushed = {};
    fake.imgui = {
        PushStyleColor = function(color_id, color)
            pushed[#pushed + 1] = { color_id, color };
        end,
        CollapsingHeader = function() return false; end,
    };

    local ctx = { settings = { display_mode = 'headers' } };
    components.begin_sections(ctx);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(pushed, {
        { ImGuiCol_Header, { 0.2, 0.2, 0.2, 0.31 } },
        { ImGuiCol_HeaderHovered, { 0.2, 0.2, 0.2, 0.45 } },
        { ImGuiCol_HeaderActive, { 0.2, 0.2, 0.2, 0.65 } },
    });

    pushed = {};
    ctx = { settings = { display_mode = 'headers', ui_accent_color = { 0.2, 0.4, 0.8, 0.5 } } };
    components.begin_sections(ctx);
    components.begin_section(ctx, 'Auto Follow', 'follow_enabled', true);
    assert_eq(pushed, {
        { ImGuiCol_Header, { 0.2, 0.4, 0.8, 0.09 } },
        { ImGuiCol_HeaderHovered, { 0.2, 0.4, 0.8, 0.18 } },
        { ImGuiCol_HeaderActive, { 0.2, 0.4, 0.8, 0.27 } },
    });
end);

test('the /sk panel saves Midnight and lets the accent reset back to that skin', function()
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

    local panel = require('lib.ui.panel');
    local settings, saves = {}, 0;
    panel.show();
    local skin_click = true;
    fake.imgui = {
        Begin = function() return true; end,
        BeginTable = function() return false; end,
        Checkbox = function(label, value)
            if label == 'Midnight Skin' and skin_click then
                skin_click = false;
                value[1] = true;
                return true;
            end
            return false;
        end,
        IsItemHovered = function() return false; end,
        ColorEdit4 = function(label, color)
            if label ~= 'UI Accent Color' then return false; end
            color[1], color[2], color[3], color[4] = 0.2, 0.6, 0.4, 0.8;
            return true;
        end,
    };
    panel.render(settings, function() saves = saves + 1; end);
    assert_eq(settings.ui_skin, 'midnight');
    assert_eq(settings.ui_accent_color, { 0.2, 0.6, 0.4, 0.8 });
    assert_eq(saves, 2);

    fake.imgui.Button = function(label) return label == 'Reset UI Accent'; end;
    fake.imgui.ColorEdit4 = function() return false; end;
    panel.render(settings, function() saves = saves + 1; end);
    panel.hide();
    assert_eq(settings.ui_accent_color, nil);
    assert_eq(settings.ui_skin, 'midnight');
    assert_eq(saves, 3);
end);

test('configuration and widget windows scope accent colors through guarded render errors', function()
    fake.reset();
    common.game_state = {
        refreshed_at = os.clock(),
        player = nil,
        party = {},
        tracked = {},
        stratagems = 0,
        ready_charges = 0,
    };

    local settings = { ui_accent_color = { 0.2, 0.4, 0.8, 0.5 } };
    local previous_errorf = common.errorf;
    local ok, err = pcall(function()
        common.errorf = function() end;

        local function assert_accent_scope(render)
            local pushed, popped, events = 0, {}, {};
            fake.imgui = {
                PushStyleColor = function() pushed = pushed + 1; end,
                PopStyleColor = function(count)
                    popped[#popped + 1] = count;
                    events[#events + 1] = 'PopStyleColor';
                end,
                PushStyleVar = function() events[#events + 1] = 'PushStyleVar'; end,
                PopStyleVar = function() events[#events + 1] = 'PopStyleVar'; end,
                SetNextWindowCollapsed = function() end,
                SetNextWindowFocus = function() end,
                Begin = function() events[#events + 1] = 'Begin'; return true; end,
                End = function() events[#events + 1] = 'End'; end,
                Button = function()
                    events[#events + 1] = 'BodyError';
                    error('simulated guarded render error');
                end,
            };

            local render_ok, render_err = pcall(render);
            assert(render_ok, tostring(render_err));
            assert_eq(pushed, 14, 'each window should apply all accent style colors');
            assert_eq(popped, { 14 }, 'each window should pop its full accent style scope');
            assert_eq(events, {
                'PushStyleVar', 'Begin', 'BodyError', 'End', 'PopStyleVar', 'PopStyleColor',
            }, 'accent colors should remain scoped until the window body has unwound');
        end;

        if ui_config.is_widget_visible() then ui_config.toggle_widget(); end;
        ui_config.show();
        assert_accent_scope(function() ui_config.render(settings, nil); end);
        ui_config.hide();

        if not ui_config.is_widget_visible() then ui_config.toggle_widget(); end;
        assert_accent_scope(function() ui_config.render_widget(settings, nil); end);
        ui_config.toggle_widget();
    end);

    common.errorf = previous_errorf;
    if ui_config.is_visible() then ui_config.hide(); end
    if ui_config.is_widget_visible() then ui_config.toggle_widget(); end
    assert(ok, tostring(err));
end);

test('Midnight pushes the full charcoal and blue palette and custom accent overlays only controls', function()
    fake.reset();
    local settings = {};
    assert_eq(components.get_ui_skin(settings), 'original');
    assert_eq(components.set_ui_skin(settings, 'midnight'), true);
    assert_eq(components.get_ui_skin(settings), 'midnight');
    assert_eq(components.set_ui_skin(settings, 'neon'), false);
    assert_eq(components.get_default_ui_accent_color(settings), { 0.059, 0.541, 0.862, 1.0 });
    local normal, hovered, active = components.get_ui_header_colors(settings);
    assert_eq({ normal, hovered, active }, {
        { 0.059, 0.541, 0.862, 0.18 },
        { 0.059, 0.541, 0.862, 0.34 },
        { 0.059, 0.541, 0.862, 0.50 },
    });

    local pushed_colors, pushed_vars, popped_colors, popped_vars = {}, {}, {}, {};
    fake.imgui = {
        PushStyleColor = function(id, color) pushed_colors[#pushed_colors + 1] = { id, color }; end,
        PushStyleVar = function(id, value) pushed_vars[#pushed_vars + 1] = { id, value }; end,
        PopStyleColor = function(count) popped_colors[#popped_colors + 1] = count; end,
        PopStyleVar = function(count) popped_vars[#popped_vars + 1] = count; end,
    };

    local scope = components.push_ui_theme(settings);
    assert_eq(scope, { color_count = 26, style_var_count = 4, accent_color_count = 0 });
    assert_eq(#pushed_colors, 26);
    assert_eq(pushed_colors[1], { ImGuiCol_WindowBg, { 0.063, 0.067, 0.067, 0.97 } });
    assert_eq(pushed_colors[2], { ImGuiCol_ChildBg, { 0.039, 0.043, 0.043, 0.75 } });
    assert_eq(pushed_colors[9], { ImGuiCol_Border, { 0.059, 0.541, 0.862, 0.72 } });
    assert_eq(pushed_colors[10], { ImGuiCol_Text, { 0.933, 0.914, 0.863, 1.0 } });
    assert_eq(pushed_colors[11], { ImGuiCol_FrameBg, { 0.094, 0.102, 0.102, 1.0 } });
    assert_eq(pushed_colors[23], { ImGuiCol_ScrollbarBg, { 0.039, 0.043, 0.043, 0.82 } });
    assert_eq(pushed_colors[26], { ImGuiCol_ScrollbarGrabActive, { 0.098, 0.858, 1.0, 1.0 } });
    assert_eq(pushed_vars, {
        { ImGuiStyleVar_WindowRounding, 10 },
        { ImGuiStyleVar_FrameRounding, 5 },
        { ImGuiStyleVar_WindowPadding, { 14, 12 } },
        { ImGuiStyleVar_ItemSpacing, { 8, 6 } },
    });
    components.pop_ui_theme(scope);
    assert_eq(popped_colors, { 26 });
    assert_eq(popped_vars, { 4 });

    pushed_colors, pushed_vars, popped_colors, popped_vars = {}, {}, {}, {};
    settings.ui_accent_color = { 0.2, 0.4, 0.8, 0.5 };
    scope = components.push_ui_theme(settings);
    assert_eq(scope, { color_count = 26, style_var_count = 4, accent_color_count = 14 });
    assert_eq(#pushed_colors, 40);
    assert_eq(pushed_colors[1], { ImGuiCol_WindowBg, { 0.063, 0.067, 0.067, 0.97 } });
    assert_eq(pushed_colors[27], { ImGuiCol_Header, { 0.2, 0.4, 0.8, 0.09 } });
    assert_eq(pushed_colors[30], { ImGuiCol_Button, { 0.2, 0.4, 0.8, 0.1 } });
    components.pop_ui_theme(scope);
    assert_eq(popped_colors, { 14, 26 });
    assert_eq(popped_vars, { 4 });

    settings.ui_accent_color = nil;
    pushed_colors, pushed_vars, popped_colors, popped_vars = {}, {}, {}, {};
    scope = components.push_ui_theme(settings);
    assert_eq(scope.accent_color_count, 0);
    assert_eq(scope.color_count, 26);
    components.pop_ui_theme(scope);
    assert_eq(popped_colors, { 26 });
end);

test('config and widget render paths balance default, Midnight, accent and error scopes', function()
    fake.reset();
    common.game_state = {
        refreshed_at = os.clock(), player = nil, party = {}, tracked = {},
        stratagems = 0, ready_charges = 0,
    };
    local original_errorf = common.errorf;
    common.errorf = function() end;

    local function render_case(settings, should_error, expected_colors, expected_vars)
        local color_pushes, color_pops = 0, 0;
        local var_pushes, var_pops = 0, 0;
        local color_depth, var_depth = 0, 0;
        local begins, ends, body_errors = 0, 0, 0;
        fake.imgui = {
            PushStyleColor = function() color_pushes = color_pushes + 1; color_depth = color_depth + 1; end,
            PopStyleColor = function(count)
                count = count or 1;
                color_pops = color_pops + count;
                color_depth = color_depth - count;
            end,
            PushStyleVar = function() var_pushes = var_pushes + 1; var_depth = var_depth + 1; end,
            PopStyleVar = function(count)
                count = count or 1;
                var_pops = var_pops + count;
                var_depth = var_depth - count;
            end,
            SetNextWindowCollapsed = function() end,
            SetNextWindowFocus = function() end,
            Begin = function() begins = begins + 1; return should_error; end,
            End = function() ends = ends + 1; end,
            Button = function()
                body_errors = body_errors + 1;
                error('simulated guarded render error');
            end,
            Text = function()
                body_errors = body_errors + 1;
                error('simulated guarded render error');
            end,
            SameLine = function()
                body_errors = body_errors + 1;
                error('simulated guarded render error');
            end,
        };

        if ui_config.is_widget_visible() then ui_config.toggle_widget(); end
        if ui_config.is_visible() then ui_config.hide(); end
        ui_config.show();
        local render_ok, render_err = pcall(function() ui_config.render(settings, { abilities = {} }); end);
        assert(render_ok, tostring(render_err));
        ui_config.hide();

        if not ui_config.is_widget_visible() then ui_config.toggle_widget(); end
        render_ok, render_err = pcall(function() ui_config.render_widget(settings, { abilities = {} }); end);
        assert(render_ok, tostring(render_err));
        ui_config.toggle_widget();

        assert_eq(begins, 2);
        assert_eq(ends, 2);
        assert_eq(color_pushes, expected_colors);
        assert_eq(color_pops, expected_colors);
        assert_eq(var_pushes, expected_vars);
        assert_eq(var_pops, expected_vars);
        assert_eq(color_depth, 0);
        assert_eq(var_depth, 0);
        if should_error then assert_eq(body_errors > 0, true); end
    end

    local ok, err = pcall(function()
        render_case({}, false, 0, 2);
        render_case({ ui_skin = 'midnight' }, false, 52, 10);
        render_case({ ui_accent_color = { 0.2, 0.4, 0.8, 0.5 } }, false, 28, 2);
        render_case({
            ui_skin = 'midnight', ui_accent_color = { 0.2, 0.4, 0.8, 0.5 },
        }, false, 80, 10);
        render_case({ ui_skin = 'midnight' }, true, 52, 10);
        render_case({
            ui_skin = 'midnight', ui_accent_color = { 0.2, 0.4, 0.8, 0.5 },
        }, true, 80, 10);
    end);

    common.errorf = original_errorf;
    if ui_config.is_visible() then ui_config.hide(); end
    if ui_config.is_widget_visible() then ui_config.toggle_widget(); end
    assert(ok, tostring(err));
end);

test('Midnight defaults persist globally and remain outside job profiles', function()
    local function source_has(path, literal)
        local file = assert(io.open(path, 'r'));
        local source = file:read('*a');
        file:close();
        return source:find(literal, 1, true) ~= nil;
    end
    assert_eq(source_has('Sidekick.lua', "ui_skin = 'original'"), true);
    assert_eq(source_has('lib/ui/config.lua', 'ui_skin = true,'), true);
end);

fake.reset();
