--- === MemoryUsage.streamdeck ===
---
--- The Stream Deck surface: one key showing the percentage in use over a rolling bar
--- graph of it, coloured by memory pressure.
---
--- Height is usage and colour is pressure, because the two disagree often enough to
--- matter: macOS runs routinely at a high percentage in use with no pressure at all.
--- Each bar is coloured by the pressure at its own sample rather than the whole graph
--- by the latest one, so an episode that has since passed still reads as it was.
---
--- This paints and does not listen, for the same reason NextEvent's key does not: the
--- press callback covers every key on the deck, so presses are claimed from the broker
--- a key at a time and MemoryUsage:openActivityMonitor() is what the claim is wired to.

return function(cfg, monitor)

local M = {}

local device = nil    -- the device we were handed, if connected
local token = nil     -- our monitor.subscribe() token
local lastState = nil -- last state, to repaint on reconnect

local BG    = {red=0.09, green=0.09, blue=0.11, alpha=1}
local TRACK = {red=0.16, green=0.16, blue=0.19, alpha=1}
local TEXT  = {red=0.97, green=0.96, blue=0.94, alpha=1}
local DIM   = {red=0.60, green=0.60, blue=0.62, alpha=1}

local SIZE = 120
local GRAPH_TOP = 58
local GRAPH_H = SIZE - GRAPH_TOP - 4

-- The colour for a pressure level, and DIM for a sample whose pressure read failed.
local function colorFor(pressure)
    return pressure and cfg.pressureColors[pressure] or DIM
end

local function gigabytes(bytes)
    return bytes / (1024 ^ 3)
end

local function drawButton(state)
    local elements = {
        {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = SIZE},
            fillColor = BG,
            action = "fill",
        },
        {
            type = "rectangle",
            frame = {x = 4, y = GRAPH_TOP, w = SIZE - 8, h = GRAPH_H},
            fillColor = TRACK,
            roundedRectRadii = {xRadius = 3, yRadius = 3},
            action = "fill",
        },
    }

    -- Newest sample on the right, like Activity Monitor's own graph. Bars are laid out
    -- for a full history from the first sample on, so the graph fills in from the right
    -- rather than stretching as it grows.
    local history = state.history
    local slot = (SIZE - 8) / cfg.historyLength
    local offset = cfg.historyLength - #history
    for i, entry in ipairs(history) do
        local h = math.max(1, entry.fraction * GRAPH_H)
        table.insert(elements, {
            type = "rectangle",
            frame = {
                x = 4 + (offset + i - 1) * slot,
                y = GRAPH_TOP + GRAPH_H - h,
                -- A hairline gap between bars once they are wide enough to afford one.
                w = slot >= 3 and slot - 1 or slot,
                h = h,
            },
            fillColor = colorFor(entry.pressure),
            action = "fill",
        })
    end

    local headline, detail, color
    if state.fraction then
        headline = string.format("%d%%", math.floor(state.fraction * 100 + 0.5))
        detail = string.format("%.1f / %.0f GB", gigabytes(state.used), gigabytes(state.total))
        -- A failed sample leaves the last good reading up, dimmed so it reads as stale.
        color = state.error and DIM or colorFor(state.pressure)
    else
        headline, detail, color = "RAM", state.error and "unavailable" or "…", DIM
    end

    table.insert(elements, {
        type = "text",
        text = headline,
        frame = {x = 0, y = 4, w = SIZE, h = 34},
        textColor = color,
        textSize = 30,
        textAlignment = "center",
        textFont = "Menlo-Bold",
    })
    table.insert(elements, {
        type = "text",
        text = detail,
        frame = {x = 0, y = 38, w = SIZE, h = 18},
        textColor = state.error and DIM or TEXT,
        textSize = 13,
        textAlignment = "center",
        textFont = "Helvetica-Bold",
    })

    local canvas = hs.canvas.new({x = 0, y = 0, w = SIZE, h = SIZE})
    canvas:appendElements(elements)
    local image = canvas:imageFromCanvas()
    canvas:delete()
    return image
end

local function paint(state)
    lastState = state
    if not device then return end

    -- The device can vanish between a sample and this call, and a write to an unplugged
    -- one throws; dropping the handle leaves discovery to hand us the next.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawButton(state))
    end)
    if not ok then
        hs.printf("[MemoryUsage] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

--- MemoryUsage.streamdeck.setDevice(dev)
--- Function
--- Use an already-discovered device. Pass nil to detach.
function M.setDevice(dev)
    if not token then
        token = monitor.subscribe(paint)
    end
    device = dev
    if dev then
        paint(lastState or monitor.state())
    end
end

--- MemoryUsage.streamdeck.stop()
--- Function
--- Stop mirroring and blank the key.
function M.stop()
    if token then
        monitor.unsubscribe(token)
        token = nil
    end
    if device then
        -- buttonCallback is deliberately not cleared: this surface never installed one,
        -- and clearing it would strip the broker's dispatcher off the device.
        pcall(function()
            device:setButtonColor(cfg.streamDeckButton, {red=0, green=0, blue=0, alpha=1})
        end)
        device = nil
    end
    lastState = nil
end

return M

end
