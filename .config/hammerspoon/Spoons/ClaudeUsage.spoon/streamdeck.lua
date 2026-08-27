--- === ClaudeUsage.streamdeck ===
---
--- The Stream Deck surface: one key showing Clawd over the session percentage.
---
--- Subscribing to the monitor rather than polling is the whole point: this surface
--- adds no API requests at all.
---
--- Whether it handles the press is the caller's choice, because it cannot handle only
--- its own: see ClaudeUsage.manageButtonCallback.

return function(cfg, monitor, clawd)

local M = {}

local device = nil    -- the claimed hs.streamdeck device, if connected
local token = nil     -- our monitor.subscribe() token
local lastState = nil -- last state, to repaint on reconnect
local owns = false    -- whether the buttonCallback currently installed is ours

local BG      = {red=0.09, green=0.09, blue=0.11, alpha=1}
local TEXT    = {red=0.97, green=0.96, blue=0.94, alpha=1}
local STALE   = {red=0.98, green=0.75, blue=0.35, alpha=1}
local MISSING = {red=0.60, green=0.60, blue=0.62, alpha=1}

-- Compose the 120x120 key: Clawd from the shared pixel map, scaled up, over the
-- display string. The percentage is what carries at arm's length, so it gets the
-- lower third at a size that stays readable on the device.
local function drawButton(state)
    local size = 120
    local px = 8                                    -- 11x8 pixel map -> 88x64
    local artW = clawd.COLS * px
    local elements = {
        {
            type = "rectangle",
            frame = {x = 0, y = 0, w = size, h = size},
            fillColor = BG,
            action = "fill",
        },
    }

    for _, el in ipairs(clawd.elements(state.level, px, (size - artW) / 2, 12)) do
        table.insert(elements, el)
    end

    local color = TEXT
    if not state.utilization then
        color = MISSING
    elseif state.error then
        color = STALE
    end

    table.insert(elements, {
        type = "text",
        text = state.text,
        frame = {x = 0, y = 82, w = size, h = 34},
        textColor = color,
        -- Sized for the widest routine case, "62/11%" (both velocity and the
        -- plain percentage) — smaller than a lone "11%" needed, since that
        -- string is roughly twice as long.
        textSize = 20,
        textAlignment = "center",
        textFont = "Menlo-Bold",
    })

    return clawd.render(size, size, elements)
end

local function paint(state)
    lastState = state
    if not device then return end

    -- The device can vanish between the state change and this call; a write to a
    -- unplugged device throws, which would otherwise take down the whole publish.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawButton(state))
    end)
    if not ok then
        hs.printf("[ClaudeUsage] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

local function attach(dev)
    device = dev

    -- Pressing opens the usage page rather than forcing a fetch: no request means
    -- no way for an impatient press to deepen a backoff. `pressed` is false on
    -- release, and acting on both would open the page twice.
    --
    -- The callback is per-device and covers every key on the deck, so installing one
    -- here takes presses away from every other surface sharing it. A config that
    -- brokers presses clears manageButtonCallback and routes its own claim on this key
    -- to openUsage() instead.
    if cfg.manageButtonCallback then
        dev:buttonCallback(function(_dev, button, pressed)
            if pressed and button == cfg.streamDeckButton then
                hs.urlevent.openURL(cfg.usageURL)
            end
        end)
        owns = true
    end

    paint(lastState or monitor.state())
end

--- ClaudeUsage.streamdeck.start()
--- Function
--- Claim a Stream Deck and mirror the usage onto one of its keys.
function M.start()
    if token then return end

    token = monitor.subscribe(paint)

    hs.streamdeck.init(function(connected, dev)
        if connected then
            attach(dev)
        elseif device and dev == device then
            device = nil
        end
    end)
end

--- ClaudeUsage.streamdeck.setDevice(dev)
--- Function
--- Use an already-discovered device instead of managing discovery here, for
--- configs that call hs.streamdeck.init() themselves. Pass nil to detach.
function M.setDevice(dev)
    if not token then
        token = monitor.subscribe(paint)
    end
    if dev then
        attach(dev)
    else
        device = nil
    end
end

--- ClaudeUsage.streamdeck.stop()
--- Function
--- Stop mirroring and blank the key.
function M.stop()
    if token then
        monitor.unsubscribe(token)
        token = nil
    end
    if device then
        pcall(function()
            device:setButtonColor(cfg.streamDeckButton, {red=0, green=0, blue=0, alpha=1})
            -- Only ours is ours to clear. Under a broker the callback on the device
            -- belongs to it and dispatches every other key on the deck, so clearing it
            -- here would silence all of them on the way out.
            if owns then device:buttonCallback(nil) end
        end)
        device = nil
        owns = false
    end
    lastState = nil
end

return M

end
