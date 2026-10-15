--[[
    The Sidekick3 window: ImGui only. It draws what ui/model.lua builds and
    turns clicks into model mutators; it reads no game state and decides nothing.
    Ashita's binding takes widget values as one-element tables ({ true }, { 75 }).
]]--

local imgui = require('imgui')

local window = {}

-- One frame. `save` writes the settings file.
function window.render(cfg, status, save)
    local open = { true }
    if imgui.Begin('Sidekick3', open, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text(status.running and 'Running' or 'Stopped')
    end
    imgui.End()
    if not open[1] then
        status.open, cfg.ui.open = false, false
        save()
    end
end

return window
