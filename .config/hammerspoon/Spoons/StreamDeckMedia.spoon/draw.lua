--- === StreamDeckMedia.draw ===
---
--- The palette, the fonts, and the canvas work the two knob surfaces share.
---
--- Shared so that the volume readout and the track readout are the same object at a
--- glance: they sit next to each other on one strip, and a stray background or a
--- second grey is visible from across the room even when neither is wrong on its
--- own.
---
--- The palette and the two faces are kept whole rather than split by who currently
--- uses which. They are one set of decisions — the greys are chosen against each
--- other and against BG — and a colour that lives here because both surfaces happen
--- to want it today is a colour that moves file the first time one of them stops.
--- The canvas and text-fitting functions are here on the ordinary grounds instead:
--- more than one caller, or an obvious next one.

local M = {}

--- StreamDeckMedia.draw.BG
--- Constant
--- Strip background. The rest of the palette is layered on this and named for the
--- job it does, not for the colour it is: FG for whatever the segment is chiefly
--- reporting, DIM for a label, a secondary line, or a chief reading that is paused
--- or silent, FAINT for a secondary line under one of those, BAR for the filled part
--- of a level or progress track, TRACK for the empty part of one and for a
--- placeholder standing in for a missing image, OFF for muted.
M.BG    = {red=0.09, green=0.09, blue=0.11, alpha=1}
M.FG    = {red=0.97, green=0.96, blue=0.94, alpha=1}
M.DIM   = {red=0.60, green=0.60, blue=0.62, alpha=1}
M.FAINT = {red=0.42, green=0.42, blue=0.45, alpha=1}
M.BAR   = {red=0.45, green=0.72, blue=0.95, alpha=1}
M.TRACK = {red=0.22, green=0.22, blue=0.26, alpha=1}
M.OFF   = {red=0.85, green=0.35, blue=0.30, alpha=1}

--- StreamDeckMedia.draw.TITLE_FONT
--- Constant
--- The face for anything being read at arm's length: a level, a song title, a label.
M.TITLE_FONT = "Menlo-Bold"

--- StreamDeckMedia.draw.BODY_FONT
--- Constant
--- The face for a secondary line — an artist, an album, a clock.
M.BODY_FONT = "Menlo"

-- ---------------------------------------------------------------------------
-- Canvas
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.draw.render(w, h, elements) -> hs.image
--- Function
--- Draw elements onto a fresh canvas of that size and hand back the image.
---
--- The canvas is deleted on the way out: these are drawn to be handed to the device
--- and never shown, so leaving one alive per repaint is a leak on a timer.
function M.render(w, h, elements)
    local c = hs.canvas.new({x = 0, y = 0, w = w, h = h})
    c:appendElements(elements)
    local img = c:imageFromCanvas()
    c:delete()
    return img
end

--- StreamDeckMedia.draw.background(w, h) -> table
--- Function
--- The filled backdrop every readout starts with, as a canvas element.
function M.background(w, h)
    return {type = "rectangle", frame = {x = 0, y = 0, w = w, h = h},
            fillColor = M.BG, action = "fill"}
end

-- ---------------------------------------------------------------------------
-- Text fitting
-- ---------------------------------------------------------------------------

-- The style table wants the font as a name and the size beside it: passing
-- `font` as a {name, size} table is valid hs.styledtext and invalid here, and
-- getTextDrawingSize validates it through the canvas defaults, which reject it.
local function measure(text, font, size)
    local m = hs.drawing.getTextDrawingSize(text, {font = font, size = size})
    return (m and m.w) or 0
end

-- Drop one character, not one byte: titles arrive with typographic quotes, dashes
-- and accents in them, and half a UTF-8 sequence renders as a replacement glyph.
local function dropLast(s)
    local i = #s
    while i > 1 do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then break end   -- not a continuation byte
        i = i - 1
    end
    return s:sub(1, i - 1)
end

-- Greedy word wrap into at most `maxLines` lines, reporting whether anything had to
-- be given up. Canvas will wrap text inside a frame by itself, but it will not say
-- where it broke or that it ran out of room and clipped a line — which is how a
-- title loses its last word with no ellipsis to admit it. Wrapping here instead
-- means the string that gets measured is the string that gets drawn.
local function wrapLines(text, font, size, width, maxLines)
    local lines, current, overflow = {}, "", false
    for word in text:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if measure(candidate, font, size) <= width then
            current = candidate
        elseif current ~= "" and #lines + 1 < maxLines then
            lines[#lines + 1] = current
            current = word
        else
            -- Out of lines, or one word too wide for any line. Either way it is the
            -- last line's problem and it is going to need trimming.
            overflow = true
            current = candidate
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if #lines == 0 then return {""}, false end

    local last = lines[#lines]
    if overflow or measure(last, font, size) > width then
        while #last > 1 and measure(last .. "…", font, size) > width do
            last = dropLast(last)
        end
        lines[#lines] = last .. "…"
    end
    return lines, overflow
end

--- StreamDeckMedia.draw.fitText(text, font, maxSize, minSize, width, maxLines)
--- Function
--- The text laid out at the largest size from maxSize down to minSize that needs no
--- more than maxLines lines, with its size and line count.
---
--- Returns the laid-out string, the size it fits at, and how many lines it took.
--- Newlines are explicit in the result, so the caller can size the frame from the
--- count and canvas has nothing left to decide. Text that will not fit even at
--- minSize comes back ellipsised at minSize rather than clipped.
function M.fitText(text, font, maxSize, minSize, width, maxLines)
    local lines, overflow
    for size = maxSize, minSize, -1 do
        lines, overflow = wrapLines(text, font, size, width, maxLines)
        if not overflow then
            return table.concat(lines, "\n"), size, #lines
        end
    end
    return table.concat(lines, "\n"), minSize, #lines
end

--- StreamDeckMedia.draw.clock(seconds) -> string
--- Function
--- Seconds as m:ss, or "--:--" for nil — a stream reports no duration.
function M.clock(seconds)
    if not seconds then return "--:--" end
    local whole = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

return M
