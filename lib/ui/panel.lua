--[[
    Game State Info Panel for Sidekick
    Displays a per-frame snapshot of common.game_state for all party members.
    Toggle visibility with: /sk panel
]]--

local panel = {}

local imgui = require('imgui')
local common = require('lib.core.common')
local afk = require('lib.core.afk')
local tooltips = require('lib.ui.tooltips')

-- Window state
local is_open = { true }
local panel_visible = false

-- ============================================================================
-- Visibility Control
-- ============================================================================

function panel.show()
    panel_visible = true
    is_open[1] = true
end

function panel.hide()
    panel_visible = false
    is_open[1] = false
end

function panel.toggle()
    if panel_visible then
        panel.hide()
    else
        panel.show()
    end
end

function panel.is_visible()
    return panel_visible
end

-- ============================================================================
-- Helpers
-- ============================================================================

-- HP color: red <=25%, orange <=50%, normal otherwise
local function push_hp_color(hpp)
    if hpp <= 25 then
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 })
        return true
    elseif hpp <= 50 then
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.75, 0.2, 1.0 })
        return true
    end
    return false
end

-- MP color: red <=20%, orange <=40%, normal otherwise
local function push_mp_color(mpp)
    if mpp <= 20 then
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 })
        return true
    elseif mpp <= 40 then
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.75, 0.2, 1.0 })
        return true
    end
    return false
end

-- Format position as "X, Y, Z"
local function fmt_pos(pos)
    if not pos then return '0.0, 0.0, 0.0' end
    return string.format('%.1f, %.1f, %.1f', pos.x or 0, pos.y or 0, pos.z or 0)
end

-- Short label for entity status values
local STATUS_LABELS = { [0]='Idle', [1]='Engaged', [2]='Dead 2', [3]='Dead', [5]='Mounted', [33]='Resting', [47]='Sitting' }
local function fmt_status(s)
    if s == nil or s == -1 then return '--' end
    -- tonumber() ensures cdata/boxed integers from Ashita's Lua bindings
    -- compare correctly against the integer keys in STATUS_LABELS.
    return STATUS_LABELS[tonumber(s)] or tostring(s)
end

-- Resolve a buff ID to a display string (name if available, else "#ID")
local function buff_name(buff_id)
    local ok, name = pcall(function()
        return AshitaCore:GetResourceManager():GetString('buffs.names', buff_id)
    end)
    if ok and name and name ~= '' then
        return name
    end
    return '#' .. tostring(buff_id)
end

-- Build a comma-separated buff list string for display
local function fmt_buffs(buffs)
    if not buffs or #buffs == 0 then return '' end
    local parts = {}
    for _, id in ipairs(buffs) do
        table.insert(parts, buff_name(id))
    end
    return table.concat(parts, ', ')
end

-- ============================================================================
-- Render
-- ============================================================================

function panel.render(addon_settings, save_settings)
    if not panel_visible then return end

    -- Refresh if stale (automation tick may have already done it this frame)
    if os.clock() - common.game_state.refreshed_at > 0.1 then
        common.refresh_game_state()
    end

    local gs = common.game_state

    local window_flags = ImGuiWindowFlags_AlwaysAutoResize

    if imgui.Begin('Sidekick: Party State', is_open, window_flags) then

        -- Header line
        local staleness = os.clock() - gs.refreshed_at
        local stale_color = staleness > 2.0 and { 1.0, 0.4, 0.4, 1.0 } or { 0.5, 0.5, 0.5, 1.0 }
        local tracked_count = 0
        if gs.tracked then
            for _ in pairs(gs.tracked) do tracked_count = tracked_count + 1 end
        end
        local main_count = 0
        if gs.player then main_count = main_count + 1 end
        for i = 1, 5 do if gs.party[i] then main_count = main_count + 1 end end
        local alliance_count = common.get_alliance_count()
        local header_str = string.format('Party: %d member(s)', main_count)
        if alliance_count > 0 then
            header_str = header_str .. string.format('   Alliance: %d', alliance_count)
        end
        if tracked_count > 0 then
            header_str = header_str .. string.format('   Tracked: %d', tracked_count)
        end
        header_str = header_str .. string.format('   Last refresh: %.2fs ago', staleness)
        imgui.TextColored(stale_color, header_str)

        -- Scholar Stratagem charges
        if gs.stratagems and gs.stratagems > 0 then
            imgui.SameLine(0, 20)
            local strat_color = gs.stratagems <= 1
                and { 1.0, 0.4, 0.4, 1.0 }   -- red when low
                or  { 0.4, 0.8, 1.0, 1.0 }   -- cyan
            imgui.TextColored(strat_color, string.format('Stratagems: %d', gs.stratagems))
        end

        -- Beastmaster Ready charges (same treatment as Scholar stratagems)
        if gs.ready_charges and gs.ready_charges > 0 then
            imgui.SameLine(0, 20)
            local ready_color = gs.ready_charges <= 1
                and { 1.0, 0.4, 0.4, 1.0 }   -- red when low
                or  { 0.4, 0.8, 1.0, 1.0 }   -- cyan
            imgui.TextColored(ready_color, string.format('Ready: %d', gs.ready_charges))
        end

        -- Debug Mode toggle (next to Stratagems in header row)
        local debug_var = { common.debug }
        imgui.SameLine(0, 20)
        if imgui.Checkbox('Debug Mode', debug_var) then
            common.debug = debug_var[1]
        end

        -- AFK Sleep toggle + timeout (global). Timeout shows minutes; afk_timeout is
        -- stored in seconds, so read afk_timeout/60 and write value*60.
        if addon_settings then
            local afk_var = { addon_settings.afk_enabled == true }
            imgui.SameLine(0, 20)
            if imgui.Checkbox('AFK Sleep', afk_var) then
                addon_settings.afk_enabled = afk_var[1]
                if not afk_var[1] then afk.reset() end  -- never leave it stuck asleep
                if save_settings then save_settings() end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(tooltips.afk_sleep)
            end
            if addon_settings.afk_enabled then
                local mins_var = { math.floor((addon_settings.afk_timeout or 600) / 60) }
                imgui.SameLine(0, 20)
                imgui.PushItemWidth(80)
                if imgui.InputInt('Timeout (minutes)', mins_var) then
                    local m = mins_var[1]
                    if m < 1 then m = 1 end
                    if m > 30 then m = 30 end
                    addon_settings.afk_timeout = m * 60
                    afk.reset()  -- restart the interval with the new timeout
                    if save_settings then save_settings() end
                end
                imgui.PopItemWidth()
            end
        end

        -- Multisend Follow mode (global). ON = Attack Range shown, native Follow off.
        if addon_settings then
            local ms_var = { addon_settings.multisend_follow == true }
            imgui.SameLine(0, 20)
            if imgui.Checkbox('Multisend Follow', ms_var) then
                addon_settings.multisend_follow = ms_var[1]
                -- Disabling Multisend Follow reverts attack range to Off.
                if not ms_var[1] then addon_settings.attack_range = 'Off' end
                if save_settings then save_settings() end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(tooltips.multisend_follow)
            end
        end

        -- Bard: Pianissimo Fast Casting toggle (next to Debug Mode). Persisted
        -- per-job in addon_settings. BRD as main or sub.
        local main_job, sub_job = common.get_player_job()
        if (main_job == 10 or sub_job == 10) and addon_settings then
            local fast_var = { addon_settings.pianissimo_fast_casting == true }
            imgui.SameLine(0, 20)
            if imgui.Checkbox('Pianissimo Fast Casting', fast_var) then
                addon_settings.pianissimo_fast_casting = fast_var[1]
                if save_settings then save_settings() end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(tooltips.pianissimo_fast_casting)
            end
        end

        -- Ninja: Cast with 1 Shadow toggle (next to Debug Mode). Persisted
        -- per-job in addon_settings. NIN as main or sub.
        if (main_job == 13 or sub_job == 13) and addon_settings then
            local one_shadow_var = { addon_settings.cast_with_1_shadow == true }
            imgui.SameLine(0, 20)
            if imgui.Checkbox('Cast with 1 Shadow', one_shadow_var) then
                addon_settings.cast_with_1_shadow = one_shadow_var[1]
                if save_settings then save_settings() end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(tooltips.cast_with_1_shadow)
            end
        end

        -- Debug scalars (moved from config window) — same header line.
        -- Only the values NOT already shown as table columns above.
        if common.debug then
            local target_id = common.get_target_id()
            local dbg = string.format('Zone: %d   Target: %s   Moving: %s   Casting: %s',
                common.get_zone_id(), tostring(target_id),
                tostring(common.is_player_moving()), tostring(common.is_casting()))

            -- Append the target's party slot + target index when the target is a party member
            local party = common.get_party()
            if party and target_id and target_id > 0 then
                for i = 0, 5 do
                    if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) == target_id then
                        dbg = dbg .. string.format('   TargetIdx P%d: %s', i, tostring(party:GetMemberTargetIndex(i)))
                        break
                    end
                end
            end

            -- AFK Sleep state, beside Moving/Casting.
            if afk.is_sleeping() then
                dbg = dbg .. '   AFK: asleep'
            else
                dbg = dbg .. string.format('   AFK: awake (%.0fs)', afk.seconds_remaining(addon_settings))
            end

            imgui.SameLine(0, 20)
            imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 }, dbg)
        end

        imgui.Separator()

        -- Column definitions
        -- Slot | Name | Job | HP | MP% | TP | Position | Buffs | Pet HP% | Pet Pos
        local TABLE_FLAGS = bit.bor(
            ImGuiTableFlags_Borders,
            ImGuiTableFlags_RowBg,
            ImGuiTableFlags_SizingFixedFit
        )

        if imgui.BeginTable('##ps_table', 12, TABLE_FLAGS, { 0, 0 }) then
            imgui.TableSetupColumn('Slot',    ImGuiTableColumnFlags_WidthFixed,  30)
            imgui.TableSetupColumn('Name',    ImGuiTableColumnFlags_WidthFixed,  100)
            imgui.TableSetupColumn('SrvID',   ImGuiTableColumnFlags_WidthFixed,  85)
            imgui.TableSetupColumn('Job',     ImGuiTableColumnFlags_WidthFixed, 110)
            imgui.TableSetupColumn('HP',       ImGuiTableColumnFlags_WidthFixed, 140)
            imgui.TableSetupColumn('MP',       ImGuiTableColumnFlags_WidthFixed, 140)
            imgui.TableSetupColumn('TP',      ImGuiTableColumnFlags_WidthFixed,  46)
            imgui.TableSetupColumn('Status',  ImGuiTableColumnFlags_WidthFixed,  80)
            imgui.TableSetupColumn('Position',ImGuiTableColumnFlags_WidthFixed, 168)
            imgui.TableSetupColumn('Buffs',   ImGuiTableColumnFlags_WidthStretch)
            imgui.TableSetupColumn('Pet HP%', ImGuiTableColumnFlags_WidthFixed,  58)
            imgui.TableSetupColumn('Pet Pos', ImGuiTableColumnFlags_WidthFixed, 168)
            imgui.TableHeadersRow()

            -- Collect active members in index order (player first)
            local members = {}
            if gs.player then
                table.insert(members, gs.player)
            end
            for i = 1, 5 do
                if gs.party[i] then
                    table.insert(members, gs.party[i])
                end
            end

            for _, m in ipairs(members) do
                imgui.TableNextRow()

                -- ── Slot ──────────────────────────────────────────────────
                imgui.TableNextColumn()
                local slot_label = 'P' .. m.index
                if m.is_trust then
                    imgui.TextColored({ 0.7, 0.7, 1.0, 1.0 }, slot_label .. '*')
                else
                    imgui.Text(slot_label)
                end

                -- ── Name ──────────────────────────────────────────────────
                imgui.TableNextColumn()
                imgui.Text(m.name or '')

                -- ── Server ID ────────────────────────────────────────────
                imgui.TableNextColumn()
                if m.server_id and m.server_id > 0 then
                    imgui.Text(string.format('0x%X', m.server_id))
                else
                    imgui.TextDisabled('--')
                end

                -- ── Job  WHM75/SCH37 ──────────────────────────────────────
                imgui.TableNextColumn()
                local job_str = string.format('%s%d/%s%d',
                    m.job_name    or '??', m.main_level or 0,
                    m.sub_job_name or '??', m.sub_level  or 0)
                imgui.Text(job_str)

                -- ── HP  1250/9999 63% ─────────────────────────────────────
                imgui.TableNextColumn()
                local hp_str
                if m.max_hp and m.max_hp > 0 then
                    hp_str = string.format('%d/%d (%d%%%%)', m.hp or 0, m.max_hp, m.hpp or 0)
                else
                    hp_str = string.format('%d  %d%%%%', m.hp or 0, m.hpp or 0)
                end
                local hp_colored = push_hp_color(m.hpp or 0)
                imgui.Text(hp_str)
                if hp_colored then imgui.PopStyleColor() end

                -- ── MP  800/1200 66% ──────────────────────────────────────
                imgui.TableNextColumn()
                local mp_str
                if m.max_mp and m.max_mp > 0 then
                    mp_str = string.format('%d/%d (%d%%%%)', m.mp or 0, m.max_mp, m.mpp or 0)
                else
                    mp_str = string.format('%d  %d%%%%', m.mp or 0, m.mpp or 0)
                end
                local mp_colored = push_mp_color(m.mpp or 0)
                imgui.Text(mp_str)
                if mp_colored then imgui.PopStyleColor() end

                -- ── TP ────────────────────────────────────────────────────
                imgui.TableNextColumn()
                imgui.Text(tostring(m.tp or 0))

                -- ── Status ────────────────────────────────────────────────
                imgui.TableNextColumn()
                imgui.Text(fmt_status(m.entity_status))

                -- ── Position ──────────────────────────────────────────────
                imgui.TableNextColumn()
                imgui.Text(fmt_pos(m.position))

                -- ── Buffs (inline list) ──────────────────────────────────
                imgui.TableNextColumn()
                local buff_count = m.buffs and #m.buffs or 0
                if buff_count > 0 then
                    imgui.Text(fmt_buffs(m.buffs))
                else
                    imgui.TextDisabled('--')
                end

                -- ── Pet HP% (player only) ─────────────────────────────────
                imgui.TableNextColumn()
                if m.index == 0 then
                    local php = m.pet_hpp or 0
                    local pet_colored = push_hp_color(php)
                    imgui.Text(string.format('%d%%', php))
                    if pet_colored then imgui.PopStyleColor() end
                else
                    imgui.TextDisabled('--')
                end

                -- ── Pet Position (player only) ────────────────────────────
                imgui.TableNextColumn()
                if m.index == 0 then
                    imgui.Text(fmt_pos(m.pet_position))
                else
                    imgui.TextDisabled('--')
                end
            end

            -- Pet row (only when player has an active pet)
            if gs.player and (gs.player.pet_hpp or 0) > 0 then
                imgui.TableNextRow()

                -- Slot
                imgui.TableNextColumn()
                imgui.TextColored({ 1.0, 0.85, 0.4, 1.0 }, 'Pet')

                -- Name / SrvID / Job  (not available)
                imgui.TableNextColumn() imgui.TextDisabled('--')
                imgui.TableNextColumn() imgui.TextDisabled('--')
                imgui.TableNextColumn() imgui.TextDisabled('--')

                -- HP%
                imgui.TableNextColumn()
                local pet_hp_colored = push_hp_color(gs.player.pet_hpp)
                imgui.Text(string.format('%d%%%%', gs.player.pet_hpp))
                if pet_hp_colored then imgui.PopStyleColor() end

                -- MP / TP  (not available)
                imgui.TableNextColumn() imgui.TextDisabled('--')
                imgui.TableNextColumn() imgui.TextDisabled('--')

                -- Status (not available for pet)
                imgui.TableNextColumn() imgui.TextDisabled('--')

                -- Position
                imgui.TableNextColumn()
                imgui.Text(fmt_pos(gs.player.pet_position))

                -- Buffs / Pet HP% / Pet Pos  (redundant / not available)
                imgui.TableNextColumn() imgui.TextDisabled('--')
                imgui.TableNextColumn() imgui.TextDisabled('--')
                imgui.TableNextColumn() imgui.TextDisabled('--')
            end

            -- Tracked targets
            if gs.tracked then
                local sorted_tracked = {}
                for sid, tt in pairs(gs.tracked) do
                    table.insert(sorted_tracked, tt)
                end
                table.sort(sorted_tracked, function(a, b) return (a.name or '') < (b.name or '') end)

                for t_idx, m in ipairs(sorted_tracked) do
                    imgui.TableNextRow()

                    -- Slot
                    imgui.TableNextColumn()
                    imgui.TextColored({ 0.4, 1.0, 0.7, 1.0 }, 'T' .. t_idx)

                    -- Name
                    imgui.TableNextColumn()
                    imgui.Text(m.name or '')

                    -- Server ID
                    imgui.TableNextColumn()
                    if m.server_id and m.server_id > 0 then
                        imgui.Text(string.format('0x%X', m.server_id))
                    else
                        imgui.TextDisabled('--')
                    end

                    -- Job column: show job/sub+level when resolved, else '--'
                    imgui.TableNextColumn()
                    if m.main_level and m.main_level > 0 then
                        local function job_abbr(id)
                            if not id or id == 0 then return '??' end
                            local ok, s = pcall(function()
                                return AshitaCore:GetResourceManager():GetString('jobs.names_abbr', id)
                            end)
                            return (ok and s and s ~= '') and s or ('J' .. id)
                        end
                        local job_str
                        if m.main_job and m.main_job > 0 then
                            job_str = string.format('%s%d/%s%d',
                                job_abbr(m.main_job), m.main_level,
                                job_abbr(m.sub_job),  m.sub_level or 0)
                        else
                            job_str = string.format('Lv.%d', m.main_level)
                        end
                        imgui.Text(job_str)
                    else
                        imgui.TextDisabled('--')
                    end

                    -- HP: show estimated hp/max_hp when available, otherwise just hp%
                    -- Values are derived: max_hp from level table or 100%-cache; hp = hpp*max_hp/100
                    imgui.TableNextColumn()
                    local hp_colored = push_hp_color(m.hpp or 0)
                    if m.max_hp and m.max_hp > 0 then
                        imgui.Text(string.format('~%d/%d (%d%%%%)', m.hp or 0, m.max_hp, m.hpp or 0))
                    else
                        imgui.Text(string.format('%d%%%%', m.hpp or 0))
                    end
                    if hp_colored then imgui.PopStyleColor() end

                    -- MP (not available)
                    imgui.TableNextColumn()
                    imgui.TextDisabled('--')

                    -- TP (not available)
                    imgui.TableNextColumn()
                    imgui.TextDisabled('--')

                    -- Status
                    imgui.TableNextColumn()
                    imgui.Text(fmt_status(m.entity_status))

                    -- Position
                    imgui.TableNextColumn()
                    imgui.Text(fmt_pos(m.position))

                    -- Buffs
                    imgui.TableNextColumn()
                    local buff_count = m.buffs and #m.buffs or 0
                    if buff_count > 0 then
                        imgui.Text(fmt_buffs(m.buffs))
                    else
                        imgui.TextDisabled('--')
                    end

                    -- Pet HP% (not applicable)
                    imgui.TableNextColumn()
                    imgui.TextDisabled('--')

                    -- Pet Pos (not applicable)
                    imgui.TableNextColumn()
                    imgui.TextDisabled('--')
                end
            end

            -- Alliance sub-parties B and C
            if gs.alliance then
                local party_prefixes = { [2] = 'B', [3] = 'C' }
                local party_colors   = { [2] = { 1.0, 0.85, 0.4, 1.0 }, [3] = { 0.6, 0.9, 1.0, 1.0 } }
                for pi = 2, 3 do
                    local sub_party = gs.alliance[pi]
                    if sub_party and next(sub_party) ~= nil then
                        local prefix     = party_prefixes[pi]
                        local col        = party_colors[pi]
                        local leader_sid = (gs.alliance_leaders and gs.alliance_leaders[pi]) or 0

                        -- Sort by local slot index (0-5)
                        local sorted = common.sorted_alliance_members(sub_party)

                        for _, entry in ipairs(sorted) do
                            local local_idx = entry.local_idx
                            local m         = entry.m
                            imgui.TableNextRow()

                            -- ── Slot ──────────────────────────────────────
                            imgui.TableNextColumn()
                            local slot_lbl = prefix .. local_idx
                            if leader_sid ~= 0 and m.server_id == leader_sid then
                                slot_lbl = slot_lbl .. '^'
                            end
                            if m.is_trust then
                                imgui.TextColored({ 0.7, 0.7, 1.0, 1.0 }, slot_lbl .. '*')
                            else
                                imgui.TextColored(col, slot_lbl)
                            end

                            -- ── Name ──────────────────────────────────────
                            imgui.TableNextColumn()
                            imgui.Text(m.name or '')

                            -- ── Server ID ─────────────────────────────────
                            imgui.TableNextColumn()
                            if m.server_id and m.server_id > 0 then
                                imgui.Text(string.format('0x%X', m.server_id))
                            else
                                imgui.TextDisabled('--')
                            end

                            -- ── Job ───────────────────────────────────────
                            imgui.TableNextColumn()
                            local job_str = string.format('%s%d/%s%d',
                                m.job_name     or '??', m.main_level or 0,
                                m.sub_job_name or '??', m.sub_level  or 0)
                            imgui.Text(job_str)

                            -- ── HP ────────────────────────────────────────
                            imgui.TableNextColumn()
                            local hp_str
                            if m.max_hp and m.max_hp > 0 then
                                hp_str = string.format('%d/%d (%d%%%%)', m.hp or 0, m.max_hp, m.hpp or 0)
                            else
                                hp_str = string.format('%d  %d%%%%', m.hp or 0, m.hpp or 0)
                            end
                            local hp_colored = push_hp_color(m.hpp or 0)
                            imgui.Text(hp_str)
                            if hp_colored then imgui.PopStyleColor() end

                            -- ── MP ────────────────────────────────────────
                            imgui.TableNextColumn()
                            local mp_str
                            if m.max_mp and m.max_mp > 0 then
                                mp_str = string.format('%d/%d (%d%%%%)', m.mp or 0, m.max_mp, m.mpp or 0)
                            else
                                mp_str = string.format('%d  %d%%%%', m.mp or 0, m.mpp or 0)
                            end
                            local mp_colored = push_mp_color(m.mpp or 0)
                            imgui.Text(mp_str)
                            if mp_colored then imgui.PopStyleColor() end

                            -- ── TP ────────────────────────────────────────
                            imgui.TableNextColumn()
                            imgui.Text(tostring(m.tp or 0))

                            -- ── Status ────────────────────────────────────
                            imgui.TableNextColumn()
                            imgui.Text(fmt_status(m.entity_status))

                            -- ── Position ──────────────────────────────────
                            imgui.TableNextColumn()
                            imgui.Text(fmt_pos(m.position))

                            -- ── Buffs ─────────────────────────────────────
                            imgui.TableNextColumn()
                            local buff_count = m.buffs and #m.buffs or 0
                            if buff_count > 0 then
                                imgui.Text(fmt_buffs(m.buffs))
                            else
                                imgui.TextDisabled('--')
                            end

                            -- ── Pet HP% / Pet Pos (n/a for alliance) ──────
                            imgui.TableNextColumn() imgui.TextDisabled('--')
                            imgui.TableNextColumn() imgui.TextDisabled('--')
                        end
                    end
                end
            end

            imgui.EndTable()
        end

        imgui.Spacing()
        imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 }, '* Trust NPC')
        if alliance_count > 0 then
            imgui.TextColored({ 1.0, 0.85, 0.4, 1.0 }, 'B = Alliance Party B   ')
            imgui.SameLine(0, 0)
            imgui.TextColored({ 0.6, 0.9, 1.0, 1.0 }, 'C = Alliance Party C   ')
            imgui.SameLine(0, 0)
            imgui.TextColored({ 0.8, 0.8, 0.8, 1.0 }, '^ = Party Leader')
        end
        if tracked_count > 0 then
            imgui.TextColored({ 0.4, 1.0, 0.7, 1.0 }, 'T = Tracked Target')
            imgui.TextColored({ 0.5, 0.5, 0.5, 1.0 }, '~ HP values estimated from level average for Tracked Targets')
        end
    end
    imgui.End()

    -- Sync close button
    if not is_open[1] then
        panel_visible = false
    end
end

return panel
