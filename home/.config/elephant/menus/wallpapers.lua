-- Wallpaper menu for walker (elephant-menus): the wallpaper folder with thumbnails and a large
-- preview. Opened by "Browse" in the settings popup (or "Wallpaper and colours" in the walker menu)
-- (walker -m menus:wallpapers -t driftless-wallpapers). Enter hands the entry's value (an image, or
-- random|previous|other|folder) to settings-menu.sh wallpaper-pick.
Name = "wallpapers"
NamePretty = "Wallpaper"
Icon = "preferences-desktop-wallpaper"
HideFromProviderlist = true
SearchName = true
Cache = false
-- actions first, then the images newest first (as thumbs.py lists them), not alphabetical
FixedOrder = true

local home = os.getenv("HOME")
Action = home .. "/.config/quickshell/scripts/settings-menu.sh wallpaper-pick '%VALUE%'"

local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(cmd)
    local handle = io.popen(cmd)
    if not handle then
        return ""
    end
    local out = handle:read("*a")
    handle:close()
    return out
end

function GetEntries()
    -- the actions get Nerd Font glyphs (drawn as text, so they stay small next to the thumbnails)
    local entries = {
        { Text = "Random wallpaper", Subtext = "another image from the folder", Icon = "󰒝", Value = "random" },
        { Text = "Back to the previous wallpaper", Icon = "󰕌", Value = "previous",
          Preview = home .. "/.cache/theme/wall.prev.png", PreviewType = "file" },
        { Text = "Choose another image ...", Icon = "󰉏", Value = "other" },
        { Text = "Open the wallpaper folder", Icon = "󰝰", Value = "folder" },
    }
    -- the same folder as the settings menu: WALLPAPER_DIR in the personal layer
    local walls = run("bash -c '[[ -r ~/.config/driftless/personal/config ]] && source ~/.config/driftless/personal/config; "
        .. "readlink -f \"${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}\" | tr -d \"\\n\"'")
    local current = run("cat ~/.cache/theme/wall.source 2>/dev/null"):gsub("%s+$", "")
    local list = run(home .. "/.config/theme/thumbs.py " .. quote(walls) .. " 2>/dev/null")
    for image, thumb in list:gmatch("([^\t\n]+)\t([^\n]+)") do
        local name = image:match("([^/]+)$")
        table.insert(entries, {
            Text = name:gsub("%.[^.]+$", ""),
            Subtext = (image == current) and "current wallpaper" or "",
            Value = image,
            Icon = thumb,
            Preview = image,
            PreviewType = "file",
        })
    end
    return entries
end
