--[[
    Status icons for ImGui: icons.status(id) is the texture of a status's icon, as
    the client draws it, for dl:AddImage or imgui.Image; nil when it can't be had
    (offline, as in the tests, or a build without what it needs). The view gives
    a party line's statuses by id (view.party[i].statuses, ui/README.md): a
    texture is this process's alone, and another session's view is drawn here too.

    Each icon is read from the client's resources and made a texture the first
    time it's asked for, as statustimers does (resources.lua:
    load_status_icon_from_resource, Copyright (c) 2022 Heals, GPL-3.0-or-later),
    then kept. Loads are guarded as Floaties' and TargetBar's are: on some Ashita
    builds an unresolved D3DX symbol raises rather than failing, and a throw here
    would be a throw in the HUD every frame. A load that failed is kept as such,
    never retried. The texture's cdata stays in the cache beside the number
    ImGui takes: gc_safe_release frees the texture with it.
]]--

local ffi = require('ffi')

local icons = {}

local ok_d3d, d3d8 = pcall(require, 'd3d8')
local cache = {}  -- [status id] = { tex, id } or false (it failed)
local ready  -- nil until the first load: then whether D3DX can be called at all

-- Ashita 4.16 and older v4 builds: their D3DX declarations lack this one (statustimers' compat.lua), and their
-- status icons' ImageSize leaves out the 14 bytes of the bitmap's file header.
local function prepare()
    if ready ~= nil then return ready end
    ready = false
    if not ok_d3d or not d3d8 then return false end
    local declared = pcall(function () return ffi.C.D3DXCreateTextureFromFileInMemoryEx end)
    if not declared then
        local ok = pcall(ffi.cdef, [[
            HRESULT __stdcall D3DXCreateTextureFromFileInMemoryEx(IDirect3DDevice8* pDevice, LPCVOID pSrcData,
                UINT SrcDataSize, UINT Width, UINT Height, UINT MipLevels, DWORD Usage, D3DFORMAT Format, D3DPOOL Pool,
                DWORD Filter, DWORD MipFilter, D3DCOLOR ColorKey, void* pSrcInfo, PALETTEENTRY* pPalette,
                IDirect3DTexture8** ppTexture);
        ]])
        if not ok then return false end
    end
    ready = true
    return true
end

local SHORT_HEADER = 4153  -- an older build's ImageSize for a stock icon (4167 with the header)
local short

local function image_size(icon)
    if short == nil then
        local first = AshitaCore:GetResourceManager():GetStatusIconByIndex(0)
        short = first ~= nil and first.ImageSize == SHORT_HEADER
    end
    return icon.ImageSize + (short and 0x0E or 0)
end

local function load(id)
    local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(id)
    if icon == nil then return nil end
    local C, out = ffi.C, ffi.new('IDirect3DTexture8*[1]')
    if C.D3DXCreateTextureFromFileInMemoryEx(d3d8.get_device(), icon.Bitmap, image_size(icon), 0xFFFFFFFF, 0xFFFFFFFF,
            1, 0, C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF000000, nil, nil, out) ~= C.S_OK then
        return nil
    end
    local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', out[0]))
    return { tex = tex, id = tonumber(ffi.cast('uint32_t', tex)) }
end

-- The texture of status `id`'s icon (0 to 1023), for ImGui: a number, or nil.
function icons.status(id)
    if type(id) ~= 'number' or id < 1 or id > 0x3FF or id == 255 then return nil end
    local hit = cache[id]
    if hit ~= nil then return hit and hit.id or nil end
    local entry = false
    if prepare() then
        local ok, got = pcall(load, id)
        entry = ok and got or false
    end
    cache[id] = entry
    return entry and entry.id or nil
end

return icons
