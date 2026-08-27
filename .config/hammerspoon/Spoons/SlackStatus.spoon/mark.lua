--- === SlackStatus.mark ===
---
--- The Slack mark as canvas elements: four coloured hooks in a pinwheel.
---
--- Kept out of the surface for the reason Amphetamine.cup is: the key draws it at more
--- than one size depending on what is sharing the space, and those need to stay one
--- drawing rather than two that drift apart.
---
--- The geometry is taken from Slack's own mark, on the 127-unit grid it is drawn on,
--- with one simplification. In the real mark each hook's outer end is a circle with its
--- inward quadrant squared off, which is what makes the four of them interlock. Here
--- that end is a plain circle. The squared quadrant is a few pixels across at the size a
--- Stream Deck key is painted at, and buying it back would cost four bezier-approximated
--- three-quarter arcs; the silhouette, the colours and the pinwheel are what make the
--- mark recognisable at this size, and those are exact.
---
--- Colours are Slack's published brand values.

local M = {}

local BLUE   = {red = 0.212, green = 0.773, blue = 0.941, alpha = 1}  -- #36C5F0
local GREEN  = {red = 0.180, green = 0.714, blue = 0.490, alpha = 1}  -- #2EB67D
local YELLOW = {red = 0.925, green = 0.698, blue = 0.180, alpha = 1}  -- #ECB22E
local RED    = {red = 0.878, green = 0.118, blue = 0.353, alpha = 1}  -- #E01E5A

-- Half the width of a bar, and so also the radius of the round end of one, on the grid
-- below. Every other measurement here is a multiple or offset of it.
local R = 13.2

-- The grid the mark is laid out on. The drawing runs from 0.8 to 126.2 — a bar's round
-- end reaches R past the centre line it is drawn on — so the box is one unit of padding
-- either side of that, which is where the antialiasing goes.
local ART = 127

-- The four hooks. Each is a bar drawn as a round-capped stroke between two points on the
-- grid, plus the free-standing end that sits off the bar's flank at a right angle.
--
-- The four are the same shape turned through 90 degrees each time, which is what closes
-- the square hole in the middle: every bar runs past the next one's line rather than
-- meeting it, and the four gaps that leaves are what makes it a pinwheel rather than a
-- box. Rotating one entry in code instead would hide that in a transform; written out,
-- the symmetry is checkable by eye.
local HOOKS = {
    {color = RED,    from = {47.0, 80.0},  to = {47.0, 113.0},  cap = {14.0, 80.0}},
    {color = BLUE,   from = {14.0, 47.0},  to = {47.0, 47.0},   cap = {47.0, 14.0}},
    {color = GREEN,  from = {80.1, 14.0},  to = {80.1, 47.0},   cap = {113.1, 47.0}},
    {color = YELLOW, from = {80.1, 80.1},  to = {113.1, 80.1},  cap = {80.1, 113.1}},
}

--- SlackStatus.mark.elements(opts) -> table
--- Function
--- Canvas elements drawing the Slack mark to fit inside a frame.
---
--- opts is {frame = {x, y, w, h}, mono = <canvas colour or nil>}. The mark keeps its own
--- proportions inside the frame and is centred in whatever room is left over, so the
--- frame is a box to fit rather than a shape to fill.
---
--- mono draws the whole mark in one colour instead of Slack's four, for the states where
--- the colours would be saying something untrue — a Slack that is not running is not a
--- Slack in brand colours doing nothing.
function M.elements(opts)
    local frame = opts.frame
    local scale = math.min(frame.w / ART, frame.h / ART)
    local ox = frame.x + (frame.w - ART * scale) / 2
    local oy = frame.y + (frame.h - ART * scale) / 2

    local function at(point)
        return {x = ox + point[1] * scale, y = oy + point[2] * scale}
    end

    local elements = {}
    for _, hook in ipairs(HOOKS) do
        local color = opts.mono or hook.color

        table.insert(elements, {
            type = "segments",
            coordinates = {at(hook.from), at(hook.to)},
            strokeColor = color,
            strokeWidth = 2 * R * scale,
            -- Round, because the cap is half the shape: a bar of this width with round
            -- ends is the lozenge the mark is built from, and a butt cap would square off
            -- all eight ends at once.
            strokeCapStyle = "round",
            action = "stroke",
        })

        local centre = at(hook.cap)
        table.insert(elements, {
            type = "circle",
            center = centre,
            radius = R * scale,
            fillColor = color,
            action = "fill",
        })
    end
    return elements
end

return M
