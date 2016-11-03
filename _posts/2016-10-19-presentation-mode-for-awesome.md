---
title: Presentation mode for awesome
categories: Coding
tags: awesome lua xscreensaver
image_dir: /images/2016-10-19-presentation-mode-for-awesome
---
After user's inactivity, you want to dim the screen for power saving or to lock the screen for a security reason.
But it's annoying when you try to watch a video or to take part in a meeting.
Since Awesome is the framework window manager, we can programme this the rigth way.

The code is based on the approach described in the [Disable DPMS](https://awesome.naquadah.org/wiki/Disable_DPMS) wiki page. 
Here are used only Awesome rules and external utility *xset*.
When a client sends the signal about itself fullscreened, we call the function that will break the energy saving. After closing the application or disabling the fullscreen mode, the energy saving mode is switched on again.

```lua
local fullscreened_clients = {}

local function remove_client(tabl, c)
    local index = awful.util.table.hasitem(tabl, c)
    if index then
        table.remove(tabl, index)
        if #tabl == 0 then
            awful.util.spawn("xset s on")
            awful.util.spawn("xset +dpms")
        end             
    end
end

client.connect_signal("property::fullscreen",
    function(c)
        if c.fullscreen then
            table.insert(fullscreened_clients, c)
            if #fullscreened_clients == 1 then
                awful.util.spawn("xset s off")
                awful.util.spawn("xset -dpms")
            end
        else
            remove_client(fullscreened_clients, c)
        end
    end)
    
client.connect_signal("unmanage",
    function(c)
        if c.fullscreen then
            remove_client(fullscreened_clients, c)
        end
    end)
```

But I use the *xscreensaver* to lock the screen, and disabling DPMS does not help me at all. The only way I could find is running `xscreensaver-command -deactivate` from time to time. So, we need a timer to run this command periodically (let's say, once in 2 minutes). Thus, we need to start/stop the timer instead of `awful.util.spawn("xset s on")` etc.

```lua
local capi = { timer = (type(timer) == 'table' and timer or require ("gears.timer")) }

local keeping_timer = capi.timer({timeout = 2 * 60, started = false})
keeping_timer:connect_signal("timeout", function () awful.util.spawn("xscreensaver-command -deactivate", false) end)

-- disable the screensaver
keeping_timer:start()

-- enable the screensaver
keeping_timer:stop()
```

OK, this works fine now, but after some time I understand, that I need to switch into the "presentation mode" without fullscreening.
Let's add key binding for the toggle presentation mode. Also we need to change rules to start/stop our `keeping_timer`.


```lua 
-- Key bindings
globalkeys = awful.util.table.join(
    -- Toggle presentation mode
    awful.key({ modkey }, "p", function ()
            presentation_mode = not presentation_mode
            handle_screen_keeper()
        end),
```
{% highlight lua %}
function handle_screen_keeper()
    if keeping_timer.started then
        if #fullscreened_clients == 0 and not presentation_mode then
            keeping_timer:stop()
        end
    else
        if #fullscreened_clients > 0 or presentation_mode then
            keeping_timer:start()
        end
    end
end
{% endhighlight %}

And the last thing that I want to add is the presentation mode widget for indicating the current status. I'm using the **Powerarrow Darker** theme from [Awesome WM Copycats](https://github.com/copycat-killer/awesome-copycats#awesome-wm-copycats). The current status line looks like:

![]({{ page.image_dir }}/status_line.png)

In the "presentation mode" I want to have the following status line:

![]({{ page.image_dir }}/status_line_presentation_mode.png)

Let's see how this status line is organized. Here is the code from the original **rc.lua.powerarrow-darker**:

{% highlight lua linenos %}
    -- Widgets that are aligned to the upper right
    local right_layout_toggle = true
    local function right_layout_add (...)
        local arg = {...}
        if right_layout_toggle then
            right_layout:add(arrl_ld)
            for i, n in pairs(arg) do
                right_layout:add(wibox.widget.background(n ,beautiful.bg_focus))
            end
        else
            right_layout:add(arrl_dl)
            for i, n in pairs(arg) do
                right_layout:add(n)
            end
        end
        right_layout_toggle = not right_layout_toggle
    end

    -- <some code>
    
    right_layout_add(volicon, volumewidget)
    right_layout_add(memicon, memwidget)
{% endhighlight %}

Let's take a look at the `right_layout_add` function. It adds the arrow and the list of widgets with the background that depends on the `right_layout_toggle`. Thus, the line 21 adds the arrow (black < gray), the speaker icon, and the text widget ("40%"). The next arrow (gray < black) belongs to the line 22. As you can see from pictures above, I plan to put the presentation mode widget between the keyboard layout and the datetime widgets if needed. This means that the arrow (black < gray) in this place must be changed to the following sequence: the arrow (black < red), the text widget ("P"), and the arrow (red < grey). From lines 6 and 11, it turns out that the arrow will be added in every `right_layout_add` call. Let's rewrite it to control this behaviour.

```lua
    local function right_layout_add_(isArr, widgets)
        if right_layout_toggle then
            if isArr then right_layout:add(arrl_ld) end
            for i, n in ipairs(widgets) do
                right_layout:add(wibox.widget.background(n ,beautiful.bg_focus))
            end
        else
            if isArr then right_layout:add(arrl_dl) end
            for i, n in ipairs(widgets) do
                right_layout:add(n)
            end
        end
        right_layout_toggle = not right_layout_toggle
    end
    local function right_layout_add(...)
        local arg = {...}
        right_layout_add_(true, arg)
    end
```

I've found that awesome v3.5 has no way to change the widget visibility, but I've got the hack from [The Mail Archive](http://www.mail-archive.com/awesome-devel@naquadah.org/msg06713.html):

```lua
-- Awesome v3.4
somewidget = wibox.widget.textbox("Foo")
somewidget.visible = false
somewidget.visible = true
-- hack for Awesome v3.5
somewidget_internal = wibox.widget.textbox("Foo")
somewidget = wibox.layout.margin(somewidget_internal)
somewidget:set_widget(nil)
somewidget:set_widget(somewidget_internal)
```

And here is the working result:

```lua
-- put this in the top
local capi   = { timer = (type(timer) == 'table' and timer or require ("gears.timer")) }

-- The presentation mode widget
presentwidget = wibox.layout.margin()
presentwidget_inner = nil
presentwidget_inner_stub = nil

-- The separators
red = "#ff0000"
arrl_dr = separators.arrow_left(beautiful.bg_focus, red)
arrl_lr = separators.arrow_left("alpha", red)
arrl_rd = separators.arrow_left(red, beautiful.bg_focus)
arrl_rl = separators.arrow_left(red, "alpha")

-- in the existing screen loop
for s = 1, screen.count() do

    -- Some other code

    -- Widgets that are aligned to the upper right
    local right_layout_toggle = true
    local function right_layout_add_(isArr, widgets)
        if right_layout_toggle then
            if isArr then right_layout:add(arrl_ld) end
            for i, n in ipairs(widgets) do
                right_layout:add(wibox.widget.background(n ,beautiful.bg_focus))
            end
        else
            if isArr then right_layout:add(arrl_dl) end
            for i, n in ipairs(widgets) do
                right_layout:add(n)
            end
        end
        right_layout_toggle = not right_layout_toggle
    end
    local function right_layout_add(...)
        local arg = {...}
        right_layout_add_(true, arg)
    end
    
    -- adding other widgets
    
    right_layout_add(neticon, netwidget)
    right_layout_add(kbdwidget)
    right_layout:add(presentwidget)
    presentwidget_inner_stub = wibox.layout.fixed.horizontal()
    presentwidget_inner = wibox.layout.fixed.horizontal()
    local p_widget = wibox.widget.background(wibox.widget.textbox(" P "), red)
    if right_layout_toggle then
        presentwidget_inner_stub:add(arrl_ld)
        presentwidget_inner:add(arrl_lr)
        presentwidget_inner:add(p_widget)
        presentwidget_inner:add(arrl_rd)
    else
        presentwidget_inner_stub:add(arrl_dl)
        presentwidget_inner:add(arrl_dr)
        presentwidget_inner:add(p_widget)
        presentwidget_inner:add(arrl_rl)
    end
    presentwidget:set_widget(presentwidget_inner_stub)
    right_layout_add_(false, {mytextclock, spr})
    right_layout_add(mylayoutbox[s])

-- Lines of code

-- Key bindings
globalkeys = awful.util.table.join(
    -- Toggle presentation mode
    awful.key({ modkey }, "p", function ()
            presentation_mode = not presentation_mode
            handle_screen_keeper()
        end),
        
-- Lines of code

local fullscreened_clients = {}
presentation_mode = false

local keeping_timer = capi.timer({timeout = 2 * 60, started = false})
keeping_timer:connect_signal("timeout", function () awful.util.spawn("xscreensaver-command -deactivate", false) end)

function handle_screen_keeper()
    if keeping_timer.started then
        if #fullscreened_clients == 0 and not presentation_mode then
            keeping_timer:stop()
            presentwidget:set_widget(presentwidget_inner_stub)
        end
    else
        if #fullscreened_clients > 0 or presentation_mode then
            keeping_timer:start()
            presentwidget:set_widget(presentwidget_inner)
        end
    end
end

local function remove_client(tabl, c)
    local index = awful.util.table.hasitem(tabl, c)
    if index then
        table.remove(tabl, index)
        handle_screen_keeper()
    end
end

client.connect_signal("property::fullscreen",
    function(c)
        if c.fullscreen then
            table.insert(fullscreened_clients, c)
            handle_screen_keeper()
        else
            remove_client(fullscreened_clients, c)
        end
    end)

client.connect_signal("unmanage",
    function(c)
        if c.fullscreen then
            remove_client(fullscreened_clients, c)
        end
    end)
```

Have fun!
