--- === ClaudeUsage.clawd ===
---
--- The Clawd mascot as a pixel map, plus the canvas plumbing that draws it.
---
--- Kept out of the display surfaces so that the 22x16 menubar icon and the
--- 120x120 Stream Deck key remain the same artwork rather than two drifting
--- copies of it.

local M = {}

-- Colors matched from the Clawd mascot
local BODY  = {red=0.76, green=0.48, blue=0.35, alpha=1}  -- warm terracotta
local DARK  = {red=0.36, green=0.22, blue=0.16, alpha=1}  -- dark brown (eyes/nose)
local CREAM = {red=0.95, green=0.90, blue=0.85, alpha=1}  -- eye whites (dizzy/panic)
local SWEAT = {red=0.55, green=0.78, blue=0.98, alpha=1}  -- sweat drop blue
local RED   = {red=0.85, green=0.18, blue=0.18, alpha=1}  -- panic red eyes

-- Pixel size of the icon drawn by M.icon (each game-pixel = 2 canvas points)
local PX = 2

-- Body pixel map: 11 cols x 8 rows
-- 0=empty, 1=body
-- Clawd is a flat rectangle block with arms poking out the sides
local BODY_MAP = {
    {0,1,1,1,1,1,1,1,1,1,0},  -- row 0: flat top (9 wide)
    {1,1,1,1,1,1,1,1,1,1,1},  -- row 1: arms extend (11 wide), eye row top
    {1,1,1,1,1,1,1,1,1,1,1},  -- row 2: arms extend (11 wide), eye row mid
    {1,1,1,1,1,1,1,1,1,1,1},  -- row 3: arms extend (11 wide), eye row bottom
    {0,1,1,1,1,1,1,1,1,1,0},  -- row 4: body (9 wide)
    {0,1,1,1,1,1,1,1,1,1,0},  -- row 5: flat bottom (9 wide)
    {0,0,1,0,1,0,1,0,1,0,0},  -- row 6: four little legs
    {0,0,1,0,1,0,1,0,1,0,0},  -- row 7: four little legs
}

--- ClaudeUsage.clawd.COLS
--- ClaudeUsage.clawd.ROWS
--- Constant
--- Dimensions of the pixel map, so a surface can size itself around the artwork.
M.COLS, M.ROWS = 11, 8

-- Eye positions (top-left corner of each 2x3 eye)
local LEFT_EYE  = {3, 1}   -- cols 3-4, rows 1-3
local RIGHT_EYE = {6, 1}   -- cols 6-7, rows 1-3

-- Eye expression overlays for each level
-- Each entry: {col, row, color_table}
-- Drawn ON TOP of body pixels
local function getEyeOverlay(level)
    local le, re = LEFT_EYE, RIGHT_EYE  -- shortcuts

    -- Eyes are 2 wide x 3 tall. Rows: top=le[2], mid=le[2]+1, bot=le[2]+2
    local overlays = {
        -- Level 1 (0-40%): Normal - full 2x3 dark eyes
        {
            {le[1],le[2],DARK}, {le[1]+1,le[2],DARK},
            {le[1],le[2]+1,DARK}, {le[1]+1,le[2]+1,DARK},
            {le[1],le[2]+2,DARK}, {le[1]+1,le[2]+2,DARK},
            {re[1],re[2],DARK}, {re[1]+1,re[2],DARK},
            {re[1],re[2]+1,DARK}, {re[1]+1,re[2]+1,DARK},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,DARK},
        },
        -- Level 2 (40-65%): Normal eyes + sweat drop
        {
            {le[1],le[2],DARK}, {le[1]+1,le[2],DARK},
            {le[1],le[2]+1,DARK}, {le[1]+1,le[2]+1,DARK},
            {le[1],le[2]+2,DARK}, {le[1]+1,le[2]+2,DARK},
            {re[1],re[2],DARK}, {re[1]+1,re[2],DARK},
            {re[1],re[2]+1,DARK}, {re[1]+1,re[2]+1,DARK},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,DARK},
            {9, 0, SWEAT},  -- sweat drop
        },
        -- Level 3 (65-85%): Half-lidded (bottom 2 rows only) + sweat
        {
            {le[1],le[2]+1,DARK}, {le[1]+1,le[2]+1,DARK},
            {le[1],le[2]+2,DARK}, {le[1]+1,le[2]+2,DARK},
            {re[1],re[2]+1,DARK}, {re[1]+1,re[2]+1,DARK},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,DARK},
            {9, 0, SWEAT},
        },
        -- Level 4 (85-95%): X eyes (3 tall gives proper X) + big sweat
        {
            {le[1],le[2],DARK},   {le[1]+1,le[2],CREAM},   -- left X
            {le[1],le[2]+1,CREAM},{le[1]+1,le[2]+1,CREAM},
            {le[1],le[2]+2,CREAM},{le[1]+1,le[2]+2,DARK},
            {re[1],re[2],CREAM},  {re[1]+1,re[2],DARK},    -- right X (mirrored)
            {re[1],re[2]+1,CREAM},{re[1]+1,re[2]+1,CREAM},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,CREAM},
            {9, 0, SWEAT}, {9, 1, SWEAT},
        },
        -- Level 5 (95-100%): Red panic eyes
        {
            {le[1],le[2],RED}, {le[1]+1,le[2],RED},
            {le[1],le[2]+1,RED}, {le[1]+1,le[2]+1,RED},
            {le[1],le[2]+2,RED}, {le[1]+1,le[2]+2,RED},
            {re[1],re[2],RED}, {re[1]+1,re[2],RED},
            {re[1],re[2]+1,RED}, {re[1]+1,re[2]+1,RED},
            {re[1],re[2]+2,RED}, {re[1]+1,re[2]+2,RED},
        },
    }
    return overlays[level]
end

--- ClaudeUsage.clawd.levelFor(utilization) -> number
--- Function
--- Map a utilization percentage (or nil) onto one of the five eye expressions.
function M.levelFor(utilization)
    if not utilization then return 1 end
    if utilization < 40 then return 1 end
    if utilization < 65 then return 2 end
    if utilization < 85 then return 3 end
    if utilization < 95 then return 4 end
    return 5
end

--- ClaudeUsage.clawd.levelForVelocity(dayPct) -> number
--- Function
--- Map today's spend-vs-ration velocity (dayPct: 100 = exactly on pace, spending
--- the day's ration and no more) onto one of the five eye expressions.
---
--- Unlike levelFor(), 100 here is unremarkable rather than alarming, so the
--- bands sit higher than levelFor()'s plain-percentage scale: this is "how far
--- over pace am I today", not "how close to the limit am I".
function M.levelForVelocity(dayPct)
    if not dayPct then return 1 end
    if dayPct < 50 then return 1 end
    if dayPct < 75 then return 2 end
    if dayPct < 150 then return 3 end
    if dayPct < 200 then return 4 end
    return 5
end

--- ClaudeUsage.clawd.elements(level, px, ox, oy) -> table
--- Function
--- Emit Clawd as canvas rectangles at an arbitrary pixel scale and offset, so the
--- 22x16 menubar icon and the 120x120 Stream Deck key are the same artwork rather
--- than two drifting copies of it.
function M.elements(level, px, ox, oy)
    ox, oy = ox or 0, oy or 0
    local elements = {}

    for row = 0, M.ROWS - 1 do
        for col = 0, M.COLS - 1 do
            local val = BODY_MAP[row + 1][col + 1]
            if val > 0 then
                table.insert(elements, {
                    type = "rectangle",
                    frame = {x = ox + col * px, y = oy + row * px, w = px, h = px},
                    fillColor = val == 1 and BODY or DARK,
                    action = "fill",
                })
            end
        end
    end

    for _, p in ipairs(getEyeOverlay(level)) do
        table.insert(elements, {
            type = "rectangle",
            frame = {x = ox + p[1] * px, y = oy + p[2] * px, w = px, h = px},
            fillColor = p[3],
            action = "fill",
        })
    end

    return elements
end

--- ClaudeUsage.clawd.render(w, h, elements) -> hs.image
--- Function
--- Flatten canvas elements into an image. The canvas is discarded immediately;
--- only the image outlives the call.
function M.render(w, h, elements)
    local c = hs.canvas.new({x = 0, y = 0, w = w, h = h})
    c:appendElements(elements)
    local img = c:imageFromCanvas()
    c:delete()
    return img
end

-- There are only five distinct icons and the menubar repaints on every poll, so
-- they are drawn once and kept.
local iconCache = {}

--- ClaudeUsage.clawd.icon(level) -> hs.image
--- Function
--- Menubar-sized icon for an eye level, memoized.
function M.icon(level)
    if not iconCache[level] then
        iconCache[level] = M.render(M.COLS * PX, M.ROWS * PX, M.elements(level, PX))
    end
    return iconCache[level]
end

return M
