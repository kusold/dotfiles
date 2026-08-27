--- === WindowGrid.streamdeck ===
---
--- Two surfaces on one deck: the key that opens the layouts, and the page of them it
--- opens across the whole deck.
---
--- The page is drawn here and painted by the broker rather than by this file, because it
--- covers keys belonging to other modules and only the broker can hold those modules
--- still underneath it — see StreamDeck:holdKeys(). This hands over the images and the
--- broker decides when they reach the deck.
---
--- The key that opens it is painted here and directly, for the reason every other key
--- surface in this config paints its own: one key is not exclusive the way the button
--- callback is. The press on it is claimed a key at a time from the broker and wired to
--- WindowGrid:openPage().
---
--- More layouts than a deck has keys is the normal case rather than an overflow, so they
--- are paged rather than truncated. The last key always closes the page and the one
--- before it turns to the next page when there is one; both are appended here rather
--- than configured, since a page with no way back is a deck that has to be unplugged to
--- escape, and a set of layouts with no way to the rest of them is half a feature.

return function(cfg, layout, diagram)

local M = {}

local device = nil   -- the handle we were given, if a deck is connected
local current = 1    -- which page of layouts is showing

local BG      = {red = 0.09, green = 0.09, blue = 0.11, alpha = 1}
local LABEL   = {red = 0.80, green = 0.80, blue = 0.83, alpha = 1}
local DIM     = {red = 0.42, green = 0.42, blue = 0.45, alpha = 1}
local FRAME   = {red = 0.55, green = 0.57, blue = 0.62, alpha = 1}
local QUIET   = {red = 0.30, green = 0.32, blue = 0.36, alpha = 1}
local ACCENT  = {red = 0.36, green = 0.62, blue = 0.94, alpha = 1}

local SIZE = 120
local STRIPE = 7

-- Where a diagram goes on a key and where the word under it goes. The label sits at the
-- foot of every key on this page whatever is above it, so that a column of keys reads as
-- a column of names rather than as names at whatever height their picture left them.
local ART = {x = 10, y = STRIPE + 12, w = SIZE - 20, h = 52}
local WORD = {x = 4, y = SIZE - 34, w = SIZE - 8, h = 30}

-- ---------------------------------------------------------------------------
-- What the page offers
-- ---------------------------------------------------------------------------

-- Everything a press can do, in order and before it is cut into pages: the move between
-- screens first, then the layouts as configured. It leads because it is the one entry
-- that is not a shape — you reach for it having decided which monitor, not which half.
local function actions()
    local list = {{kind = "screen", label = cfg.screenLabel}}
    for _, entry in ipairs(cfg.layouts) do
        table.insert(list, {kind = "layout", label = entry.label, unit = entry.unit})
    end
    return list
end

-- How many keys are left for layouts once the reserved ones are taken. Back always takes
-- the last key; More only takes the one before it when there is a second page to reach,
-- so a set of layouts that fits a single page is not made to give up a key to a button
-- that would do nothing.
local function slotsFor(count)
    local slots = cfg.pageKeys - 1
    if count > slots then slots = slots - 1 end
    return slots
end

--- WindowGrid.streamdeck.keys() -> table
--- Function
--- What the page currently shows, keyed by key number.
---
--- Called on every repaint and on every press, so that the page a finger lands on and the
--- page that decides what the press meant are computed the same way from the same state
--- rather than kept in step by hand.
function M.keys()
    local all = actions()
    local slots = slotsFor(#all)
    local pages = math.max(1, math.ceil(#all / slots))

    -- Layouts can be reassigned while the page is up, and a page number left past the end
    -- by that would otherwise paint an empty deck with no way to page off it.
    if current > pages then current = 1 end

    local list = {}
    for slot = 1, slots do
        -- Slots past the end of the last page are filled rather than left out: a key the
        -- page does not paint keeps whatever the module underneath had on it, and half a
        -- page over half a deck reads as the page having failed.
        list[slot] = all[(current - 1) * slots + slot] or {kind = "empty"}
    end

    if pages > 1 then
        list[cfg.pageKeys - 1] = {kind = "more", label = cfg.moreLabel,
                                  page = current, pages = pages}
    end
    list[cfg.pageKeys] = {kind = "back", label = cfg.backLabel}
    return list
end

--- WindowGrid.streamdeck.nextPage()
--- Function
--- Show the next page of layouts, wrapping round at the end.
---
--- Wrapping rather than stopping, because the key it is on is the only way through the
--- pages and a page that is the last one would otherwise be a dead end with no way back
--- to the first except closing the page and opening it again.
function M.nextPage()
    local all = actions()
    local pages = math.max(1, math.ceil(#all / slotsFor(#all)))
    current = current % pages + 1
end

--- WindowGrid.streamdeck.rewind()
--- Function
--- Go back to the first page, for a page that is being opened.
function M.rewind()
    current = 1
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local function canvasFor(elements)
    local canvas = hs.canvas.new({x = 0, y = 0, w = SIZE, h = SIZE})
    canvas:appendElements(elements)
    local image = canvas:imageFromCanvas()
    canvas:delete()
    return image
end

local function chrome(accent)
    return {
        {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = SIZE},
            fillColor = BG,
            action = "fill",
        },
        {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = STRIPE},
            fillColor = accent,
            action = "fill",
        },
    }
end

local function wordElement(text, color)
    return {
        type = "text",
        text = text or "",
        frame = WORD,
        textColor = color,
        textSize = 16,
        textAlignment = "center",
        textFont = "Helvetica-Bold",
    }
end

local function glyphElement(text, color)
    return {
        type = "text",
        text = text,
        frame = {x = 0, y = STRIPE + 10, w = SIZE, h = 56},
        textColor = color,
        textSize = 40,
        textAlignment = "center",
    }
end

-- Which page of how many, as a row of dots under the arrow. The count is the only thing
-- on the page that says there is more than one press between here and a layout you can
-- see is missing.
local function pageDots(page, pages)
    local spacing = 14
    local elements = {}
    for index = 1, pages do
        table.insert(elements, {
            type = "circle",
            center = {x = SIZE / 2 + (index - (pages + 1) / 2) * spacing, y = 76},
            radius = 4,
            fillColor = index == page and ACCENT or QUIET,
            action = "fill",
        })
    end
    return elements
end

local function append(elements, more)
    for _, element in ipairs(more) do table.insert(elements, element) end
    return elements
end

local function drawEntry(entry)
    if entry.kind == "empty" then return canvasFor(chrome(BG)) end

    if entry.kind == "back" then
        local elements = chrome(DIM)
        table.insert(elements, glyphElement(cfg.backGlyph, DIM))
        table.insert(elements, wordElement(entry.label, LABEL))
        return canvasFor(elements)
    end

    if entry.kind == "more" then
        local elements = chrome(QUIET)
        table.insert(elements, glyphElement(cfg.moreGlyph, ACCENT))
        append(elements, pageDots(entry.page, entry.pages))
        table.insert(elements, wordElement(entry.label, LABEL))
        return canvasFor(elements)
    end

    if entry.kind == "screen" then
        -- One display is the one state this key cannot do anything about, and it is drawn
        -- greyed rather than left out: a key that vanishes when a monitor is unplugged
        -- moves every layout after it onto a different key.
        local lit = layout.screenCount() > 1
        local elements = chrome(lit and ACCENT or QUIET)
        append(elements, diagram.transfer({
            frame = ART,
            outline = lit and FRAME or DIM,
            color = lit and ACCENT or DIM,
            arrow = lit and FRAME or DIM,
        }))
        table.insert(elements, wordElement(entry.label, lit and LABEL or DIM))
        return canvasFor(elements)
    end

    local elements = chrome(QUIET)
    append(elements, diagram.display({
        frame = ART,
        outline = FRAME,
        unit = entry.unit,
        color = ACCENT,
    }))
    table.insert(elements, wordElement(entry.label, LABEL))
    return canvasFor(elements)
end

--- WindowGrid.streamdeck.page() -> table
--- Function
--- The page as images keyed by key number, in the shape StreamDeck:holdKeys() wants.
function M.page()
    local images = {}
    for index, entry in pairs(M.keys()) do
        images[index] = drawEntry(entry)
    end
    return images
end

-- ---------------------------------------------------------------------------
-- The key that opens the page
-- ---------------------------------------------------------------------------

local function drawButton()
    local elements = chrome(ACCENT)
    append(elements, diagram.grid({frame = ART, outline = FRAME, color = ACCENT}))
    table.insert(elements, wordElement(cfg.buttonLabel, LABEL))
    return canvasFor(elements)
end

--- WindowGrid.streamdeck.paint()
--- Function
--- Draw the key that opens the page.
---
--- It carries no state, so this is called on connect and not again. Nothing this spoon
--- knows about changes what the key says: which layouts exist and how many screens are
--- attached are both answered on the page, once it is open and while it is being looked
--- at, rather than mirrored onto a key nobody is reading.
function M.paint()
    if not device then return end

    -- The deck can go between being handed to us and this call, and a write to one that
    -- has been unplugged throws. Dropping the handle leaves discovery to hand us the next.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawButton())
    end)
    if not ok then
        hs.printf("[WindowGrid] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

--- WindowGrid.streamdeck.setDevice(dev)
--- Function
--- Use an already-discovered device. Pass nil to detach.
function M.setDevice(dev)
    device = dev
    if dev then M.paint() end
end

--- WindowGrid.streamdeck.stop()
--- Function
--- Stop drawing and blank the key.
function M.stop()
    if device then
        -- buttonCallback is deliberately not cleared: this surface never installed one,
        -- and clearing it would strip the broker's dispatcher off the device and take
        -- every other key's claim with it.
        pcall(function()
            device:setButtonColor(cfg.streamDeckButton, {red = 0, green = 0, blue = 0, alpha = 1})
        end)
        device = nil
    end
end

return M

end
