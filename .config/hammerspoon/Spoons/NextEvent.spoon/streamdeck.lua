--- === NextEvent.streamdeck ===
---
--- The Stream Deck surface: one key showing what is next and how long until it.
---
--- This paints and does not listen. hs.streamdeck:buttonCallback() is per-device and
--- covers every key on it, so a surface that installed one would answer for keys
--- belonging to other modules; presses are claimed a key at a time from the broker
--- instead, and NextEvent:toggleCalendar() is what a claim on this key is wired to.
--- Painting is not exclusive in that way, so it needs no claim and happens here.

return function(cfg, monitor)

local M = {}

local device = nil    -- the device we were handed, if connected
local token = nil     -- our monitor.subscribe() token
local lastState = nil -- last state, to repaint on reconnect

local BG     = {red=0.09, green=0.09, blue=0.11, alpha=1}
local TEXT   = {red=0.97, green=0.96, blue=0.94, alpha=1}
local DIM    = {red=0.60, green=0.60, blue=0.62, alpha=1}
local URGENT = {red=0.90, green=0.25, blue=0.22, alpha=1}
local SOON   = {red=0.98, green=0.75, blue=0.35, alpha=1}
local CALM   = {red=0.45, green=0.70, blue=0.95, alpha=1}

-- The accent stripe carries the urgency on its own, so the key reads from across a
-- desk before any of the text resolves.
local ACCENT = {
    now   = URGENT,
    soon  = SOON,
    later = CALM,
    idle  = DIM,
    error = DIM,
}

local SIZE = 120

--- What the key says, given a state. Copy lives here rather than in the monitor so
--- that a second surface can word the same state differently.
local function copy(state)
    if state.showing then
        local title = state.showing.title or "(no title)"
        -- Wrapping is the canvas's job, but a pathological title would run off the
        -- bottom of the key rather than being clipped visibly, so it is cut here.
        if #title > 60 then title = title:sub(1, 59) .. "…" end
        return state.timeText, title
    end
    if state.error then return "!", state.error end
    if state.hasData then return "", "Nothing left today" end
    return "", "…"
end

local function drawButton(state)
    local time, title = copy(state)
    local accent = ACCENT[state.urgency] or DIM

    local elements = {
        {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = SIZE},
            fillColor = BG,
            action = "fill",
        },
        {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = 7},
            fillColor = accent,
            action = "fill",
        },
    }

    -- The time is what the key is for, so it gets the accent colour and the size that
    -- survives being glanced at; the title is context and takes what is left.
    if time ~= "" then
        table.insert(elements, {
            type = "text",
            text = time,
            frame = {x = 0, y = 12, w = SIZE, h = 34},
            textColor = accent,
            textSize = 30,
            textAlignment = "center",
            textFont = "Menlo-Bold",
        })
    end

    table.insert(elements, {
        type = "text",
        text = title,
        frame = {x = 5, y = time ~= "" and 50 or 34, w = SIZE - 10, h = SIZE - 54},
        textColor = state.error and DIM or TEXT,
        textSize = 14,
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

    -- The device can vanish between the state change and this call, and a write to an
    -- unplugged one throws; dropping the handle leaves discovery to hand us the next.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawButton(state))
    end)
    if not ok then
        hs.printf("[NextEvent] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

--- NextEvent.streamdeck.setDevice(dev)
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

--- NextEvent.streamdeck.stop()
--- Function
--- Stop mirroring and blank the key.
function M.stop()
    if token then
        monitor.unsubscribe(token)
        token = nil
    end
    if device then
        -- buttonCallback is deliberately not cleared here: this surface never installed
        -- one, and clearing it would strip the broker's dispatcher off the device and
        -- with it every other key's claim.
        pcall(function()
            device:setButtonColor(cfg.streamDeckButton, {red=0, green=0, blue=0, alpha=1})
        end)
        device = nil
    end
    lastState = nil
end

return M

end
