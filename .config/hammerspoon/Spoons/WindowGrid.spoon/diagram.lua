--- === WindowGrid.diagram ===
---
--- A display with a window on it, as canvas elements: the outline of a screen with the
--- part of it a layout would fill blocked in.
---
--- The diagram is what a page key is actually read by, and the word under it is only a
--- name. A layout is a shape and nothing else, so a picture of the shape is taken in
--- without being parsed, while "L 2/3" has to be turned back into one. The words stay
--- because two shapes differing only in proportion are hard to tell apart at the size a
--- key is, and the label is what settles which of them this is.
---
--- Everything here is drawn to fit a frame it is handed, for the reason Amphetamine.cup
--- scales into one: the same display outline is drawn on the page keys and on the key
--- that opens the page, and those should stay one drawing rather than two that drift.

local M = {}

--- WindowGrid.diagram.STROKE
--- Constant
--- Line width the display outline is drawn in.
M.STROKE = 3

--- WindowGrid.diagram.ASPECT
--- Constant
--- Width over height of the display in the diagram.
---
--- Deliberately a fixed shape rather than the connected screen's. A diagram that changed
--- proportion with whatever monitor was plugged in would move every fill drawn inside it
--- and buy nothing, since a layout is a fraction of the screen either way.
M.ASPECT = 16 / 10

-- Radii for the outline and for the fill inside it. The fill is rounded far less: it
-- follows the screen's corners where it reaches them, and everywhere else it is an edge
-- against another window and wants to read as straight.
local OUTLINE_RADIUS = 4
local FILL_RADIUS = 2

-- The largest display of ASPECT that fits the frame, centred in it, with room left for
-- the stroke — which canvas centres on the path, so half of it falls outside the box.
local function displayBox(frame)
    local pad = M.STROKE / 2
    local availableW, availableH = frame.w - 2 * pad, frame.h - 2 * pad

    local w, h = availableW, availableW / M.ASPECT
    if h > availableH then w, h = availableH * M.ASPECT, availableH end

    return {
        x = frame.x + (frame.w - w) / 2,
        y = frame.y + (frame.h - h) / 2,
        w = w,
        h = h,
    }
end

-- What a window can occupy: the display box less half the stroke on each side, so a
-- window filling the whole screen lands flush against the inside of the outline rather
-- than under it.
local function screenArea(box)
    local pad = M.STROKE / 2
    return {x = box.x + pad, y = box.y + pad, w = box.w - M.STROKE, h = box.h - M.STROKE}
end

local function outlineElement(box, color)
    return {
        type = "rectangle",
        frame = box,
        strokeColor = color,
        strokeWidth = M.STROKE,
        roundedRectRadii = {xRadius = OUTLINE_RADIUS, yRadius = OUTLINE_RADIUS},
        action = "stroke",
    }
end

local function fillElement(area, unit, color)
    return {
        type = "rectangle",
        frame = {
            x = area.x + unit.x * area.w,
            y = area.y + unit.y * area.h,
            w = unit.w * area.w,
            h = unit.h * area.h,
        },
        fillColor = color,
        roundedRectRadii = {xRadius = FILL_RADIUS, yRadius = FILL_RADIUS},
        action = "fill",
    }
end

--- WindowGrid.diagram.display(opts) -> table
--- Function
--- One display, with the fraction of it given by opts.unit filled in.
---
--- opts.frame is where to draw, opts.outline the colour of the screen, opts.unit the
--- window as an {x, y, w, h} in screen fractions and opts.color what to fill it with.
--- Omitting opts.unit draws the screen empty, which is how a display nothing is being
--- sent to is distinguished from one that is.
function M.display(opts)
    local box = displayBox(opts.frame)
    local elements = {outlineElement(box, opts.outline)}
    if opts.unit then
        table.insert(elements, fillElement(screenArea(box), opts.unit, opts.color))
    end
    return elements
end

--- WindowGrid.diagram.transfer(opts) -> table
--- Function
--- Two displays with an arrow between them, the far one filled.
---
--- What a window moving to another screen looks like, and the one diagram here that is
--- about the move rather than about the shape it lands in. opts.frame, opts.outline and
--- opts.color are as for display(); opts.arrow is the colour of the arrow between them.
function M.transfer(opts)
    -- The arrow is given a quarter of the width and each display splits the rest. Sized
    -- as a share rather than in pixels because the two displays are then whatever is
    -- left, and the group stays centred at any key size.
    local arrowW = opts.frame.w * 0.26
    local displayW = (opts.frame.w - arrowW) / 2

    local elements = M.display({
        frame = {x = opts.frame.x, y = opts.frame.y, w = displayW, h = opts.frame.h},
        outline = opts.outline,
    })

    for _, element in ipairs(M.display({
        frame = {x = opts.frame.x + displayW + arrowW, y = opts.frame.y,
                 w = displayW, h = opts.frame.h},
        outline = opts.color,
        unit = {x = 0, y = 0, w = 1, h = 1},
        color = opts.color,
    })) do
        table.insert(elements, element)
    end

    local arrowSize = math.min(arrowW, opts.frame.h) * 0.9
    table.insert(elements, {
        type = "text",
        text = "→",
        -- Pulled up by most of the type size, because canvas lays text out from the top
        -- of the ascender and the arrow would otherwise hang below the displays it sits
        -- between rather than on their centre line.
        frame = {x = opts.frame.x + displayW, y = opts.frame.y + opts.frame.h / 2 - arrowSize * 0.72,
                 w = arrowW, h = arrowSize * 1.4},
        textColor = opts.arrow or opts.outline,
        textSize = arrowSize,
        textAlignment = "center",
    })
    return elements
end

--- WindowGrid.diagram.grid(opts) -> table
--- Function
--- One display ruled into quarters with the first of them filled.
---
--- The key that opens the page, drawn from the same outline as the layouts behind it so
--- that pressing it lands somewhere that looks like where it came from. It shows a screen
--- being divided rather than any one of the divisions, since it stands for all of them.
--- opts.frame, opts.outline and opts.color are as for display().
function M.grid(opts)
    local elements = M.display({
        frame = opts.frame,
        outline = opts.outline,
        unit = {x = 0, y = 0, w = 0.5, h = 0.5},
        color = opts.color,
    })

    local area = screenArea(displayBox(opts.frame))
    local midX, midY = area.x + area.w / 2, area.y + area.h / 2

    for _, line in ipairs({
        {{x = midX, y = area.y}, {x = midX, y = area.y + area.h}},
        {{x = area.x, y = midY}, {x = area.x + area.w, y = midY}},
    }) do
        table.insert(elements, {
            type = "segments",
            coordinates = line,
            strokeColor = opts.outline,
            strokeWidth = M.STROKE - 1,
            action = "stroke",
        })
    end
    return elements
end

return M
