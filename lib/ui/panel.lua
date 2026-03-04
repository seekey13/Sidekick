--[[
    Game State Info Panel for Medic
    Displays a per-frame snapshot of common.game_state for all party members.
    Toggle visibility with: /med panel
]]--

local panel = {}

local imgui = require('imgui')
local common = require('lib.core.common')

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

function panel.render()
    if not panel_visible then return end

    -- Refresh if stale (automation tick may have already done it this frame)
    if os.clock() - common.game_state.refreshed_at > 0.1 then
        common.refresh_game_state()
    end

    local gs = common.game_state

    local window_flags = ImGuiWindowFlags_AlwaysAutoResize

    if imgui.Begin('Medic: Party State', is_open, window_flags) then

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
        local alliance_count = 0
        if gs.alliance then
            for pi = 2, 3 do
                if gs.alliance[pi] then
                    for _ in pairs(gs.alliance[pi]) do alliance_count = alliance_count + 1 end
                end
            end
        end
        local header_str = string.format('Party: %d member(s)', main_count)
        if alliance_count > 0 then
            header_str = header_str .. string.format('   Alliance: %d', alliance_count)
        end
        if tracked_count > 0 then
            header_str = header_str .. string.format('   Tracked: %d', tracked_count)
        end
        header_str = header_str .. string.format('   Last refresh: %.2fs ago', staleness)
        imgui.TextColored(stale_color, header_str)
        imgui.Separator()

        -- Column definitions
        -- Slot | Name | Job | HP | MP% | TP | Position | Buffs | Pet HP% | Pet Pos
        local TABLE_FLAGS = bit.bor(
            ImGuiTableFlags_Borders,
            ImGuiTableFlags_RowBg,
            ImGuiTableFlags_SizingFixedFit
        )

        if imgui.BeginTable('##ps_table', 11, TABLE_FLAGS, { 0, 0 }) then
            imgui.TableSetupColumn('Slot',    ImGuiTableColumnFlags_WidthFixed,  30)
            imgui.TableSetupColumn('Name',    ImGuiTableColumnFlags_WidthFixed,  100)
            imgui.TableSetupColumn('SrvID',   ImGuiTableColumnFlags_WidthFixed,  85)
            imgui.TableSetupColumn('Job',     ImGuiTableColumnFlags_WidthFixed, 110)
            imgui.TableSetupColumn('HP',       ImGuiTableColumnFlags_WidthFixed, 140)
            imgui.TableSetupColumn('MP',       ImGuiTableColumnFlags_WidthFixed, 140)
            imgui.TableSetupColumn('TP',      ImGuiTableColumnFlags_WidthFixed,  46)
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
                        local sorted = {}
                        for local_idx, m in pairs(sub_party) do
                            table.insert(sorted, { local_idx = local_idx, m = m })
                        end
                        table.sort(sorted, function(a, b) return a.local_idx < b.local_idx end)

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
