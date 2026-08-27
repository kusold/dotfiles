--- === InputLevel.streamdeck ===
---
--- The knob and its strip segment: turn to change input gain, press to toggle mute,
--- and read the peak level and clip status off the segment above it.
---
--- Subscribing to the monitor rather than polling is the whole point: this surface
--- adds no reads of its own, and repaints on the same tick the monitor already
--- publishes on.

return function(cfg, deck, monitor)

local M = {}

local token = nil       -- our monitor.subscribe() token
local lastState = nil   -- last state, for a repaint the broker asks for outside a tick

local BG    = {red=0.09, green=0.09, blue=0.11, alpha=1}
local FG    = {red=0.97, green=0.96, blue=0.94, alpha=1}
local DIM   = {red=0.60, green=0.60, blue=0.62, alpha=1}
local TRACK = {red=0.22, green=0.22, blue=0.26, alpha=1}
local GREEN = {red=0.35, green=0.78, blue=0.45, alpha=1}
local YELLOW= {red=0.95, green=0.78, blue=0.25, alpha=1}
local RED   = {red=0.86, green=0.20, blue=0.20, alpha=1}

local FONT = "Menlo-Bold"

local function render(w, h, elements)
    local c = hs.canvas.new({x = 0, y = 0, w = w, h = h})
    c:appendElements(elements)
    local img = c:imageFromCanvas()
    c:delete()
    return img
end

-- Green under meterWarnDb, yellow up to clipThresholdDb, red at or past it — the
-- same boundary the clip latch itself fires at, so the bar's own colour never
-- disagrees with whether "CLIP" is about to show.
local function zoneColor(peakDb)
    if peakDb >= cfg.clipThresholdDb then return RED end
    if peakDb >= cfg.meterWarnDb then return YELLOW end
    return GREEN
end

-- A microphone glyph, drawn as a path rather than set as text for the same reason
-- media.lua's transport glyphs are: nothing in Menlo looks like a microphone, so as
-- text it would fall back to whatever face the system picks and could change out
-- from under this. Traced at a 96-unit reference size (capsule head, an open arc
-- cradling it, a stem and a base) and scaled uniformly from there, so one set of
-- proportions serves whatever pixel size the caller asks for.
--
-- When muted, a corner-to-corner slash is appended over the same reference square
-- so it scales with the rest of the glyph rather than needing its own geometry.
local function micIcon(x, y, s, color, muted)
    local function f(rx, ry, rw, rh)
        return {x = x + rx * s, y = y + ry * s, w = rw * s, h = rh * s}
    end
    local elements = {
        {
            type = "rectangle", frame = f(36, 8, 24, 44),
            roundedRectRadii = {xRadius = 12 * s, yRadius = 12 * s},
            fillColor = color, action = "fill",
        },
        {
            type = "ellipticalArc", frame = f(20, 20, 56, 56),
            startAngle = 90, endAngle = 270, arcClockwise = true, arcRadii = false,
            strokeColor = color, strokeWidth = 8 * s, action = "stroke",
        },
        { type = "rectangle", frame = f(44, 72, 8, 20), fillColor = color, action = "fill" },
        { type = "rectangle", frame = f(32, 90, 32, 6), fillColor = color, action = "fill" },
    }
    if muted then
        elements[#elements + 1] = {
            type = "segments",
            coordinates = {
                {x = x + 8 * s, y = y + 2 * s},
                {x = x + 88 * s, y = y + 98 * s},
            },
            strokeColor = color, strokeWidth = 10 * s, strokeCapStyle = "round",
            action = "stroke",
        }
    end
    return elements
end

local function drawClip(W, H)
    return {
        {type = "rectangle", frame = {x=0, y=0, w=W, h=H}, fillColor = RED, action = "fill"},
        {
            type = "text", text = "CLIP",
            frame = {x=0, y=18, w=W, h=44},
            textColor = FG, textSize = 40, textAlignment = "center", textFont = FONT,
        },
    }
end

local function drawMeter(W, H, state)
    local label = "INPUT"
    if state.stale or state.error then label = "--"
    elseif state.muted then label = "MUTED"
    elseif not state.hasGainControl then label = "NO GAIN"
    elseif state.active == false then label = "IDLE" end

    local gainText = (state.hasGainControl and state.gain)
        and string.format("%d%%", math.floor(state.gain + 0.5)) or ""

    local peakText = state.peakDb and string.format("%.0f", state.peakDb) or "--"
    local peakColor = state.peakDb and FG or DIM
    local ink = (state.stale or state.error or state.muted or state.active == false) and DIM or FG

    local elements = {
        {type = "rectangle", frame = {x=0, y=0, w=W, h=H}, fillColor = BG, action = "fill"},
        {
            type = "text", text = label,
            frame = {x=8, y=8, w=W/2 - 8, h=18},
            textColor = ink,
            textSize = 14, textAlignment = "left", textFont = FONT,
        },
        {
            type = "text", text = gainText,
            frame = {x=W/2, y=8, w=W/2 - 8, h=18},
            textColor = DIM, textSize = 14, textAlignment = "right", textFont = FONT,
        },
        {
            type = "text", text = peakText,
            frame = {x=0, y=24, w=W, h=48},
            textColor = peakColor, textSize = 42, textAlignment = "center", textFont = FONT,
        },
        {
            type = "rectangle",
            frame = {x=24, y=78, w=W-48, h=8},
            fillColor = TRACK, action = "fill",
            roundedRectRadii = {xRadius=4, yRadius=4},
        },
    }

    for _, el in ipairs(micIcon(14, 24, 0.42, ink, state.muted)) do
        elements[#elements + 1] = el
    end

    if state.peakDb then
        local fraction = math.max(0, math.min(1, (state.peakDb - cfg.meterFloorDb) / -cfg.meterFloorDb))
        if fraction > 0 then
            table.insert(elements, {
                type = "rectangle",
                frame = {x=24, y=78, w=(W-48) * fraction, h=8},
                fillColor = zoneColor(state.peakDb), action = "fill",
                roundedRectRadii = {xRadius=4, yRadius=4},
            })
        end
    end

    return elements
end

--- InputLevel.streamdeck.screenImage([state]) -> hs.image
--- Function
--- The strip artwork for a state, defaulting to the current one. Public so the
--- readout can be previewed with no deck connected.
function M.screenImage(state)
    state = state or lastState or monitor.state()
    local W, H = deck().SEGMENT_W, deck().SEGMENT_H
    local elements = state.clipped and drawClip(W, H) or drawMeter(W, H, state)
    return render(W, H, elements)
end

local function paint(state)
    lastState = state
    deck():paintStrip(cfg.levelEncoder)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- InputLevel.streamdeck.start()
--- Function
--- Claim the knob and its strip segment.
function M.start()
    if token then return end
    token = monitor.subscribe(paint)

    deck():addStrip(cfg.levelEncoder, {paint = function() return M.screenImage() end})

    deck():addEncoder(cfg.levelEncoder, function(pressed, left, right)
        if left or right then
            -- Turns report `pressed` false and one direction true; presses report
            -- neither direction. See hs.streamdeck:encoderCallback().
            monitor.nudgeGain(right)
        elseif pressed then
            monitor.toggleMute()
        end
    end)
end

--- InputLevel.streamdeck.stop()
--- Function
--- Release the knob and strip segment, and stop mirroring.
function M.stop()
    if token then
        monitor.unsubscribe(token)
        token = nil
    end
    deck():addEncoder(cfg.levelEncoder, nil)
    deck():addStrip(cfg.levelEncoder, nil)
    deck():blankStrip(cfg.levelEncoder)
    lastState = nil
end

return M

end
