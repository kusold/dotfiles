--- === Shortcuts.streamdeck ===
---
--- Two surfaces on one deck: the key that opens the page, and the page of actions it
--- opens across the whole deck.
---
--- Split between painters the way SystemState.streamdeck is, and for the same reasons:
--- the page is handed to the broker as images, because it covers keys other modules own
--- and only the broker can hold those still; the key that opens it is painted here
--- directly, because one key is not exclusive the way the button callback is.

return function(cfg)

local M = {}

local device = nil  -- the handle we were given, if a deck is connected

local BG     = {red = 0.09, green = 0.09, blue = 0.11, alpha = 1}
local LABEL  = {red = 0.80, green = 0.80, blue = 0.83, alpha = 1}
local DIM    = {red = 0.42, green = 0.42, blue = 0.45, alpha = 1}
local QUIET  = {red = 0.30, green = 0.32, blue = 0.36, alpha = 1}
local ACCENT = {red = 0.95, green = 0.75, blue = 0.25, alpha = 1}

local SIZE = 120
local STRIPE = 7

-- Whether the "actions do not fit" warning has already been given, so that entries(),
-- called on every repaint and every press, says it once rather than as a stream.
local warnedTruncated = false

-- ---------------------------------------------------------------------------
-- What the page offers
-- ---------------------------------------------------------------------------

--- Shortcuts.streamdeck.entries() -> table
--- Function
--- What the page shows, in key order: the actions, then Back on the last key.
---
--- Back is appended here rather than configured, because a page with no way back is a
--- deck that has to be unplugged to escape, and padded to the last key so that an action
--- added or removed never moves it.
function M.entries()
    local room = cfg.pageKeys - 1
    local list = {}

    if #cfg.actions <= room then warnedTruncated = false end

    for index, action in ipairs(cfg.actions) do
        if index > room then
            if not warnedTruncated then
                warnedTruncated = true
                hs.printf("[Shortcuts] more actions than the page has room for; %q and any after it are not shown",
                          tostring(action.label))
            end
            break
        end
        table.insert(list, {kind = "action", action = action})
    end

    while #list < room do
        table.insert(list, {kind = "empty"})
    end

    table.insert(list, {kind = "back", label = cfg.backLabel, glyph = cfg.backGlyph})
    return list
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

-- No textColor, so an emoji glyph keeps its own colour; see SystemState.streamdeck.
local function glyphElement(text)
    return {
        type = "text",
        text = text or "",
        frame = {x = 0, y = STRIPE + 12, w = SIZE, h = 60},
        textSize = 44,
        textAlignment = "center",
    }
end

local function wordElement(text, color)
    return {
        type = "text",
        text = text or "",
        frame = {x = 4, y = SIZE - 34, w = SIZE - 8, h = 30},
        textColor = color,
        textSize = 16,
        textAlignment = "center",
        textFont = "Helvetica-Bold",
    }
end

local function drawEntry(entry)
    if entry.kind == "empty" then return canvasFor(chrome(BG)) end

    local isBack = entry.kind == "back"
    local elements = chrome(isBack and DIM or QUIET)
    local source = isBack and entry or entry.action
    table.insert(elements, glyphElement(source.glyph))
    table.insert(elements, wordElement(source.label, LABEL))
    return canvasFor(elements)
end

--- Shortcuts.streamdeck.page() -> table
--- Function
--- The page as images keyed by key number, in the shape StreamDeck:holdKeys() wants.
function M.page()
    local images = {}
    for index, entry in ipairs(M.entries()) do
        images[index] = drawEntry(entry)
    end
    return images
end

-- ---------------------------------------------------------------------------
-- The key that opens the page
-- ---------------------------------------------------------------------------

local function drawButton()
    local elements = chrome(ACCENT)
    table.insert(elements, glyphElement(cfg.buttonGlyph))
    table.insert(elements, wordElement(cfg.buttonLabel, LABEL))
    return canvasFor(elements)
end

--- Shortcuts.streamdeck.paint()
--- Function
--- Draw the key that opens the page. It carries no state, so this is called on connect
--- and not again.
function M.paint()
    if not device then return end

    -- A write to a deck unplugged since it was handed over throws; dropping the handle
    -- leaves discovery to hand us the next.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawButton())
    end)
    if not ok then
        hs.printf("[Shortcuts] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

--- Shortcuts.streamdeck.setDevice(dev)
--- Function
--- Use an already-discovered device. Pass nil to detach.
function M.setDevice(dev)
    device = dev
    if dev then M.paint() end
end

--- Shortcuts.streamdeck.stop()
--- Function
--- Stop drawing and blank the key.
function M.stop()
    if device then
        -- buttonCallback is deliberately not cleared: this surface never installed one,
        -- and clearing it would strip the broker's dispatcher off the device.
        pcall(function()
            device:setButtonColor(cfg.streamDeckButton, {red = 0, green = 0, blue = 0, alpha = 1})
        end)
        device = nil
    end
end

return M

end
