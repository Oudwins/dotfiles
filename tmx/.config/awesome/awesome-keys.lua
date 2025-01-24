local awful = require("awful")
local gears = require("gears")
local hotkeys_popup = require("awful.hotkeys_popup")
local vars = require("awesome-vars")
local leader = require("awesome-leader")
local naughty = require("naughty") -- notifications

local M = {}

-- Language leader keys
local language_keys = leader.bind_actions({
    {"e",
     function(args)
        awful.spawn("setxkbmap us")
     end,
     "Change keyboard language to english"
    },
    {"s",
     function(args)
        awful.spawn("setxkbmap es")
     end,
     "Change keyboard language to spanish"
    },
}) 
local language_leader = leader.leader(language_keys)

-- Dmenu picker keys
-- rofi -show calc -modi calc -no-show-match -no-sort -automatic-save-to-history > /dev/null
local dmenu_picker_keys = leader.bind_actions({
    {"d",
        function()
            -- TODO
        end,
        "Dmenu Scripts picker"
    },
    {
        "w",
        function()
            awful.spawn.with_shell("$HOME/dotfiles/tmx/.local/bin/dscripts/rofi-nm.sh")
        end,
        "Network Manager"
    },
    {
        "o",
        function()
            awful.spawn.with_shell("$HOME/dotfiles/tmx/.local/bin/dscripts/powermenu.sh")
        end,
        "[D]menu Power [O]n off"
    },
    {
        "p",
        function()
            awful.spawn.with_shell("$HOME/dotfiles/tmx/.config/dmscripts-custom/dmenu-projects.sh")
        end,
        "[D]menu open [P]rojects"
    },
    {
        "n",
        function()
            awful.spawn.with_shell("$HOME/dotfiles/tmx/.config/dmscripts-custom/dmenu-obsidian-vaults.sh")
        end,
        "[D]menu [n]otes"
    },
    {
        "c",
        function()
        
            awful.spawn.with_shell("rofi -show calc -modi calc -no-show-match -no-sort -automatic-save-to-history -calc-command \"echo -n '{result}' | xclip\"")
        end,
        "[D]menu [c]alculator"
    },
    {
        "e",
        function()
            -- Depends on: https://github.com/Mange/rofi-emoji
            -- Only copy
            --awful.spawn.with_shell("rofi -modi emoji -show emoji -emoji-mode copy")
            awful.spawn.with_shell("rofi -modi emoji -show emoji -emoji-mode insert")
        end,
        "[D]menu [E]mojis"
    }
})
local dmenu_picker_leader = leader.leader(dmenu_picker_keys)

-- AI keys
local ai_keys = leader.bind_actions({
    -- "a" -> rofi over AI scripts
    {"s",
     function(args)
        awful.spawn.with_shell(vars.screenshotterOCR)
     end,
     "Screenshot OCR to Copy"
    },
}) 
local ai_leader = leader.leader(ai_keys)

-- Global keys
local globalkeys = gears.table.join(
    awful.key({ vars.modkey, "Control" }, "a",      hotkeys_popup.show_help,
              {description="show help", group="awesome"}),
    awful.key({ vars.modkey, "Control" }, "r", awesome.restart,
              {description = "reload awesome", group = "awesome"}),
    awful.key({ vars.modkey,           }, "Left",   awful.tag.viewprev,
              {description = "view previous", group = "tag"}),
    awful.key({ vars.modkey,           }, "Right",  awful.tag.viewnext,
              {description = "view next", group = "tag"}),
    awful.key({ vars.modkey,           }, "Escape", awful.tag.history.restore,
              {description = "go back", group = "tag"}),
    -- KEYBOARD HOTKEYS
    awful.key({"Mod1"}, "l", language_leader,
        {description="Change keyboard language", group="system"}),
    awful.key({ vars.modkey}, "a",      ai_leader,
              {description="Run AI scripts", group="launcher"}),
    
    -- START OF BRIGHTNESS & AUDIO CONTROLS
    -- ALSA volume control
    awful.key({ }, "XF86AudioRaiseVolume", function ()
       awful.util.spawn("amixer set Master 5%+", false) end),
    awful.key({ }, "XF86AudioLowerVolume", function ()
       awful.util.spawn("amixer set Master 5%-", false) end),
    -- Brightness
    awful.key({ }, "XF86MonBrightnessUp", function () awful.util.spawn("light -A 5") end),
    awful.key({ }, "XF86MonBrightnessDown", function () awful.util.spawn("light -U 5") end),
    -- END OF BRIGHTNESS & AUDIO CONTROLS
    awful.key({ vars.modkey,           }, "u", awful.client.urgent.jumpto,
              {description = "jump to urgent client", group = "client"}),
    awful.key({ vars.modkey,           }, "Tab",
        function ()
            awful.client.focus.history.previous()
            if client.focus then
                client.focus:raise()
            end
        end,
        {description = "go back", group = "client"}),

    -- MY PROGRAM HOTKEYS
    awful.key({ vars.modkey,           }, "space", function()
        awful.spawn(vars.launcher)
    end,
              {description = "Launch app launcher", group = "launcher"}),
    awful.key({  }, "Print", function()
        awful.spawn(vars.screenshotter)
    end,
              {description = "Launch screenshot", group = "launcher"}),

    awful.key({ vars.modkey,           }, "t", function () awful.spawn(vars.terminal) end,
              {description = "open a terminal", group = "launcher"}),
    awful.key({ vars.modkey,           }, "d", dmenu_picker_leader,
              {description = "Launch dmenu scripts", group = "launcher"}),

    awful.key({ vars.modkey }, "x",
              function ()
                  awful.prompt.run {
                    prompt       = "Run Lua code: ",
                    textbox      = awful.screen.focused().mypromptbox.widget,
                    exe_callback = awful.util.eval,
                    history_path = awful.util.get_cache_dir() .. "/history_eval"
                  }
              end,
              {description = "lua execute prompt", group = "awesome"})
)

-- Client keys
local clientkeys = gears.table.join(
    awful.key({ vars.modkey,           }, "f",
        function (c)
            c.fullscreen = not c.fullscreen
            c:raise()
        end,
        {description = "toggle fullscreen", group = "client"}),
    awful.key({ vars.modkey,}, "q",      function (c) c:kill()                         end,
              {description = "close client", group = "client"}),
    awful.key({ vars.modkey, "Shift"}, "q", function()
        for _, c in ipairs(mouse.screen.selected_tag:clients()) do
            c:kill()
        end
     end,
    {description = "close all clients in tag", group = "client"}),
    awful.key({ vars.modkey, "Control" }, "f",  awful.client.floating.toggle                     ,
              {description = "toggle floating", group = "client"}),
    awful.key({ vars.modkey, "Control" }, "Return", function (c) c:swap(awful.client.getmaster()) end,
              {description = "move to master", group = "client"}),
    -- Focusing & switching between clients
    awful.key({ vars.modkey,           }, "j",
        function (c)
            awful.client.focus.bydirection("down")
            c:lower()
        end,
        {description = "Focus client by direction 'down'", group = "client"}
    ),
    awful.key({ vars.modkey,           }, "k",
        function (c)
            awful.client.focus.bydirection("up");
            c:lower()
        end,
        {description = "Focus client by direction 'up'", group = "client"}
    ),
    awful.key({ vars.modkey,           }, "l",
        function (c)
            awful.client.focus.bydirection("right")
            c:lower()
        end, {description = "Focus client by direction 'right'", group = "client"}),
    awful.key({ vars.modkey,           }, "h",     
        function (c)
            awful.client.focus.bydirection("left")
            c:lower()
        end,
              {description = "Focus client by direction 'left'", group = "client"}),
-- Layout manipulation Swapping clients
    awful.key({ vars.modkey, "Shift"   }, "j", function () awful.client.swap.bydirection("down")    end,
              {description = "swap with client by direction down", group = "client"}),
    awful.key({ vars.modkey, "Shift"   }, "k", function () awful.client.swap.bydirection("up")    end,
              {description = "swap with client by direction up", group = "client"}),
    awful.key({ vars.modkey, "Shift"   }, "h", function () awful.client.swap.bydirection("left")    end,
              {description = "swap with client by direction left", group = "client"}),
    awful.key({ vars.modkey, "Shift"   }, "l", function () awful.client.swap.bydirection("right")    end,
              {description = "swap with client by direction right", group = "client"}),
-- screen manipulation -> switching between screens
    awful.key({ vars.modkey, "Control"   }, "j", function () awful.screen.focus_bydirection("down", _screen)    end,
              {description = "swap with client by direction left", group = "client"}),
    awful.key({ vars.modkey, "Control"   }, "k", function () awful.screen.focus_bydirection("up", _screen)    end,
              {description = "swap with client by direction right", group = "client"}),
    awful.key({ vars.modkey, "Control"   }, "h", function () awful.screen.focus_bydirection("left", _screen)    end,
              {description = "swap with client by direction left", group = "client"}),
    awful.key({ vars.modkey, "Control"   }, "l", function () awful.screen.focus_bydirection("right", _screen)    end,
              {description = "swap with client by direction right", group = "client"}),
    awful.key({vars.modkey, "Control", "Shift"}, "k", function (c) c:move_to_screen() end,
              {description = "Move client to new screen", group = "client"})
)

-- Mouse bindings
local clientbuttons = gears.table.join(
    awful.button({ }, 1, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
    end),
    awful.button({ vars.modkey }, 1, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.move(c)
    end),
    awful.button({ vars.modkey }, 3, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.resize(c)
    end)
)

-- Bind all key numbers to tags
for i = 1, 9 do
    globalkeys = gears.table.join(globalkeys,
        -- View tag only.
        awful.key({ vars.modkey }, "#" .. i + 9,
                  function ()
                        local screen = awful.screen.focused()
                        local tag = screen.tags[i]
                        if tag then
                           tag:view_only()
                        end
                  end,
                  {description = "view tag #"..i, group = "tag"}),
        -- Toggle tag display.
        awful.key({ vars.modkey, "Control" }, "#" .. i + 9,
                  function ()
                      local screen = awful.screen.focused()
                      local tag = screen.tags[i]
                      if tag then
                         awful.tag.viewtoggle(tag)
                      end
                  end,
                  {description = "toggle tag #" .. i, group = "tag"}),
        -- Move client to tag.
        awful.key({ vars.modkey, "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = client.focus.screen.tags[i]
                          if tag then
                              client.focus:move_to_tag(tag)
                          end
                     end
                  end,
                  {description = "move focused client to tag #"..i, group = "tag"}),
        -- Toggle tag on focused client.
        awful.key({ vars.modkey, "Control", "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = client.focus.screen.tags[i]
                          if tag then
                              client.focus:toggle_tag(tag)
                          end
                      end
                  end,
                  {description = "toggle focused client on tag #" .. i, group = "tag"})
    )
end

-- Export the key bindings
M.globalkeys = globalkeys
M.clientkeys = clientkeys
M.clientbuttons = clientbuttons

return M
