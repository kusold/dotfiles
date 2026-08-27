--- === Amphetamine.cup ===
---
--- A coffee cup as canvas elements: full while something is keeping this Mac awake,
--- empty while nothing is.
---
--- Drawn from above and to one side, the way Amphetamine's own menu bar item draws it, so
--- that the key and the menu bar item say the same thing in the same shape. The angle is
--- also what makes the two states one glance apart: seen from the side a cup can only
--- report its level by how far up the wall the ink reaches, while from here the whole
--- surface of the coffee faces the viewer and either is there or is not.
---
--- The shape is defined once in its own units and scaled into whatever frame it is
--- handed, for the reason ClaudeUsage.clawd keeps its pixel map out of the surfaces: the
--- key draws the cup at more than one size, depending on whether a countdown is sharing
--- the space with it, and those need to stay one drawing rather than two that drift.

local M = {}

-- The cup in its own units: a rim ellipse with a deeper one hanging under it for the
-- bowl. Both are centred on the rim's centre and share RIM_A as their horizontal
-- semi-axis, which is what closes the silhouette. At that shared widest point each is
-- vertical, so the rim's upper arc and the bowl's lower one meet as one curve rather
-- than crossing, and the pair needs no seam drawn over the join.
local RIM_A  = 40   -- half the rim's width
local RIM_B  = 23   -- half its depth, foreshortened by the angle it is seen at
local BOWL_D = 43   -- how far the bowl's bottom falls below the rim's centre
local STROKE = 8

-- The handle as two points on the wall and how far past it the loop swings. Both ends sit
-- on the wall's own centre line rather than beside it, so each is buried under half the
-- wall's stroke and the loop reads as growing out of the cup; an end placed off that line
-- surfaces as a nub on whichever side of the wall it missed by.
--
-- Which wall an end lands on follows from where it is: above the rim's centre the
-- silhouette is the rim ellipse, below it the bowl.
local HANDLE_TOP    = -7   -- upper end, this far above the rim's centre
local HANDLE_BOTTOM = 24   -- lower end, this far below it
local HANDLE_REACH  = 60   -- the loop's outermost point, from the rim's centre

-- How far each tangent runs before the curve turns, as a fraction of the distance that
-- corner has to cover. Around 0.55 draws the quarter circles; more than that pulls the
-- curve towards the corners of the box it turns in and away from the wall, which is what
-- holds the hole open along its whole length. Rounder than this and the curve settles
-- towards the straight line from wall to outermost point instead, and the hole narrows to
-- a teardrop at the size the key is actually painted at.
local HANDLE_TENSION = 0.75

-- Room for the stroke to sit inside the art box, and two units past it for the
-- antialiasing, which is otherwise shaved off wherever a frame is an exact fit for the
-- drawing.
local PAD = STROKE / 2 + 2

local ART_W = RIM_A + HANDLE_REACH + 2 * PAD
local ART_H = RIM_B + BOWL_D + 2 * PAD

-- The rim's centre, which every other measurement here is taken from.
local CX = RIM_A + PAD
local CY = RIM_B + PAD

-- Where the wall is, dy above or below the rim's centre. The rim ellipse and the bowl
-- differ only in their vertical semi-axis, so one function answers for both: pass RIM_B
-- for a point on the rim, BOWL_D for one on the bowl.
local function wallX(dy, semi)
    return CX + RIM_A * math.sqrt(1 - (dy / semi) ^ 2)
end

--- Amphetamine.cup.elements(opts) -> table
--- Function
--- Canvas elements drawing a cup to fit inside a frame.
---
--- opts is {frame = {x, y, w, h}, color = <canvas colour>, filled = boolean, coffee =
--- <canvas colour or nil>}. The cup keeps its own proportions inside the frame and is
--- centred in whatever room is left over, so the frame is a box to fit rather than a
--- shape to fill. coffee paints the liquid alone and defaults to color.
function M.elements(opts)
    local frame = opts.frame
    local color = opts.color
    local scale = math.min(frame.w / ART_W, frame.h / ART_H)
    local ox = frame.x + (frame.w - ART_W * scale) / 2
    local oy = frame.y + (frame.h - ART_H * scale) / 2

    local function at(x, y)
        return {x = ox + x * scale, y = oy + y * scale}
    end

    -- The box an ellipse of these semi-axes about the rim's centre is inscribed in, which
    -- is how canvas takes both of the ellipses drawn here.
    local function box(hw, hh)
        return {
            x = ox + (CX - hw) * scale,
            y = oy + (CY - hh) * scale,
            w = 2 * hw * scale,
            h = 2 * hh * scale,
        }
    end

    local stroke = STROKE * scale
    local elements = {}

    -- The coffee, drawn before the outline so the outline closes over its edge rather
    -- than the fill spilling across it.
    --
    -- Inset by half the stroke, which is exactly the part of the rim lying inside the
    -- cup: the surface meets the wall and no further. Insetting past that leaves a dark
    -- ring inside the rim, which reads as a cup filled short of its own edge rather than
    -- as a full one.
    if opts.filled then
        table.insert(elements, {
            type = "oval",
            frame = box(RIM_A - STROKE / 2, RIM_B - STROKE / 2),
            fillColor = opts.coffee or color,
            action = "fill",
        })
    end

    -- The bowl: the lower half of the deeper ellipse, from the rim's widest point round to
    -- the other one. Zero degrees is straight up and angles run clockwise, so ninety to
    -- two hundred and seventy is the half below the centre.
    --
    -- Half rather than all of it, because the upper half of an ellipse this deep would cut
    -- straight across the cup's mouth; above the centre the silhouette is the rim's own
    -- arc, drawn last.
    table.insert(elements, {
        type = "ellipticalArc",
        frame = box(RIM_A, BOWL_D),
        startAngle = 90,
        endAngle = 270,
        arcRadii = false,
        strokeColor = color,
        strokeWidth = stroke,
        action = "stroke",
    })

    -- The handle: out of the wall level, round a vertical tangent at its outermost point,
    -- and back into the wall level again. Level rather than along the wall, because two
    -- curves that leave a shared point in the same direction separate slower than a
    -- stroke is wide, and their strokes would merge into one thickened edge over that
    -- stretch rather than parting into a loop with a hole in it.
    local ax, ay = wallX(HANDLE_TOP, RIM_B), CY + HANDLE_TOP
    local bx, by = wallX(HANDLE_BOTTOM, BOWL_D), CY + HANDLE_BOTTOM
    local px, py = CX + HANDLE_REACH, CY + (HANDLE_TOP + HANDLE_BOTTOM) / 2

    local outward = at(ax + HANDLE_TENSION * (px - ax), ay)
    local upward = at(px, py - HANDLE_TENSION * (py - ay))
    local downward = at(px, py + HANDLE_TENSION * (by - py))
    local inward = at(bx + HANDLE_TENSION * (px - bx), by)
    local far, back = at(px, py), at(bx, by)

    table.insert(elements, {
        type = "segments",
        coordinates = {
            at(ax, ay),
            {x = far.x,  y = far.y,  c1x = outward.x,  c1y = outward.y,
                                     c2x = upward.x,   c2y = upward.y},
            {x = back.x, y = back.y, c1x = downward.x, c1y = downward.y,
                                     c2x = inward.x,   c2y = inward.y},
        },
        strokeColor = color,
        strokeWidth = stroke,
        -- Butt rather than round: a round cap is a half-disc centred on the path's end, so
        -- it reaches half a stroke past it, and an end sitting on the wall's centre line
        -- has only half a stroke of wall to hide under. Butt stops on the end itself.
        strokeCapStyle = "butt",
        action = "stroke",
    })

    -- The rim last, so its outline is the edge every other part is trimmed by: the
    -- handle's upper end and the coffee's edge both finish underneath it.
    table.insert(elements, {
        type = "oval",
        frame = box(RIM_A, RIM_B),
        strokeColor = color,
        strokeWidth = stroke,
        action = "stroke",
    })

    return elements
end

return M
