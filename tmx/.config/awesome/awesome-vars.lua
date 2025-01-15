local M = {}

-- Standard awesome library
local gears = require("gears")
local awful = require("awful")

-- This is used later as the default terminal and editor to run.
M.terminal = os.getenv("TERMINAL") or "xterm"
M.editor = os.getenv("EDITOR") or "vim"
M.browserPersonal = os.getenv("BROWSER_PERSONAL") or "brave"
M.browserWork = os.getenv("BROWSER_WORK") or "google-chrome"
M.editor_cmd = M.terminal .. " -e " .. M.editor
M.launcher = os.getenv("LAUNCHER") or ""
M.screenshotter = os.getenv("SCREENSHOT") or "flameshot gui"
M.screenshotterOCR = "flameshot gui --raw --accept-on-select | tesseract stdin stdout | xclip -in -selection clipboard"

-- Default modkey.
-- Usually, Mod4 is the key with a logo between Control and Alt.
M.modkey = "Mod4"

-- Table of layouts to cover with awful.layout.inc, order matters.
M.layouts = {
    awful.layout.suit.tile,
    awful.layout.suit.tile.bottom,
    awful.layout.suit.tile.top,
    awful.layout.suit.fair.horizontal,
}

return M 