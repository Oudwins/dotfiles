local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")

local widget = wibox.widget {
    align = "center",
    valign = "center",
    widget = wibox.widget.textbox,
}

local function update(text)
    if text:match("Powered:%s+yes") then
        widget.markup = " BT:on "
    else
        widget.markup = " BT:off "
    end
end

awful.widget.watch("bluetoothctl show", 10, function(_, stdout)
    update(stdout)
end, widget)

widget:buttons(gears.table.join(
    awful.button({}, 1, function()
        awful.spawn.easy_async_with_shell("bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on", function()
            awful.spawn.easy_async("bluetoothctl show", function(stdout)
                update(stdout)
            end)
        end)
    end),
    awful.button({}, 3, function()
        awful.spawn("blueman-manager")
    end)
))

return widget
