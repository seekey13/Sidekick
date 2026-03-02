--[[
    Shared buff ID utility helpers
    Centralises the repeated "does this buff list contain any of these IDs?" pattern
    used across buff.lua, debuff_removal.lua, and wake.lua.
]]--

local buff_utils = {}

-- Normalize a buff_id value (single number or table) to a flat table of IDs.
-- Returns: table of numbers (may be empty)
function buff_utils.normalize_ids(ids)
    if ids == nil then return {} end
    return type(ids) == 'table' and ids or {ids}
end

-- Check if any ID in `active_buffs` matches any ID in `check_ids`.
-- Args:
--   active_buffs (table)       - flat array of currently active buff numbers
--   check_ids    (number|table) - one or more buff IDs to look for
-- Returns: boolean
function buff_utils.has_any_buff(active_buffs, check_ids)
    local ids = buff_utils.normalize_ids(check_ids)
    for _, active in ipairs(active_buffs or {}) do
        for _, check in ipairs(ids) do
            if active == check then return true end
        end
    end
    return false
end

-- Inverse of has_any_buff: returns true when the target is MISSING the buff.
-- When check_ids is nil (no tracking), always returns true (treat as always needed).
-- Args:
--   active_buffs (table)       - flat array of currently active buff numbers
--   check_ids    (number|table|nil) - buff IDs to search for, or nil for "always needed"
-- Returns: boolean
function buff_utils.needs_buff(active_buffs, check_ids)
    if check_ids == nil then return true end
    return not buff_utils.has_any_buff(active_buffs, check_ids)
end

return buff_utils
