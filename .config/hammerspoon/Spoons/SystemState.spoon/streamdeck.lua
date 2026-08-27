--- === SystemState.streamdeck ===
---
--- Two surfaces on one deck: the key that opens the page, and the page of power
--- actions it opens across the whole deck.
---
--- The page is drawn here and painted by the broker rather than by this file, because
--- it covers keys belonging to other modules and only the broker can hold those
--- modules still underneath it — see StreamDeck:holdKeys(). This hands over the images
--- and the broker decides when they reach the deck.
---
--- The key that opens it is painted here and directly, for the reason every other key
--- surface in this config paints its own: one key is not exclusive the way the button
--- callback is.
---
--- Which action is "armed" — pressed once and waiting for the confirming second press
--- — is state kept here rather than in init.lua, the way WindowGrid.streamdeck keeps
--- which page of layouts is showing: it is part of what the page looks like, and
--- entries()/page() are called from both the paint path and the press path, so the two
--- agree on it for free rather than by being kept in step by hand.

return function(cfg)

local M = {}

local device = nil  -- the handle we were given, if a deck is connected
local armed = nil   -- key index of the action waiting for its confirming press, or nil

local BG     = {red = 0.09, green = 0.09, blue = 0.11, alpha = 1}
local LABEL  = {red = 0.80, green = 0.80, blue = 0.83, alpha = 1}
local DIM    = {red = 0.42, green = 0.42, blue = 0.45, alpha = 1}
local QUIET  = {red = 0.30, green = 0.32, blue = 0.36, alpha = 1}
local ACCENT = {red = 0.36, green = 0.62, blue = 0.94, alpha = 1}
local WARN   = {red = 0.90, green = 0.55, blue = 0.20, alpha = 1}

local SIZE = 120
local STRIPE = 7

-- Whether the "actions do not fit" warning has already been given. entries() is called
-- on every repaint and on every press, so without this the warning would not be a
-- warning but a stream, and would bury the console it is trying to say something in.
local warnedTruncated = false

-- ---------------------------------------------------------------------------
-- Confirm state
-- ---------------------------------------------------------------------------

--- SystemState.streamdeck.armed() -> number or nil
--- Function
--- The key index currently waiting for its confirming press, if any.
function M.armed()
    return armed
end

--- SystemState.streamdeck.arm(index)
--- Function
--- Mark a key as waiting for its confirming press.
function M.arm(index)
    armed = index
end

--- SystemState.streamdeck.disarm()
--- Function
--- Clear whatever key was waiting for its confirming press.
function M.disarm()
    armed = nil
end

--- SystemState.streamdeck.rewind()
--- Function
--- Clear armed state, for a page that is being (re)opened.
function M.rewind()
    armed = nil
end

-- ---------------------------------------------------------------------------
-- What the page offers
-- ---------------------------------------------------------------------------

--- SystemState.streamdeck.entries() -> table
--- Function
--- What the page shows, in key order: the actions, then Back.
---
--- Back is appended here rather than configured, because a page with no way back is a
--- deck that has to be unplugged to escape. It takes the last key, so an action added
--- or removed never moves it.
function M.entries()
    local room = cfg.pageKeys - 1
    local list = {}

    if #cfg.actions <= room then warnedTruncated = false end

    for index, action in ipairs(cfg.actions) do
        if index > room then
            -- Said out loud rather than quietly dropped: an action that is configured
            -- and simply never appears is indistinguishable from one that is not
            -- working.
            if not warnedTruncated then
                warnedTruncated = true
                hs.printf("[SystemState] more actions than the page has room for; %q and any after it are not shown",
                          tostring(action.label))
            end
            break
        end
        table.insert(list, {kind = "action", action = action})
    end

    -- Padded out so Back lands on the last key whatever the action count, rather than
    -- sliding up the deck as actions are added or removed.
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

-- No textColor here: left at the canvas default, which is legible on every fill this
-- page uses and lets an emoji glyph keep its own colour instead of being flattened to
-- one.
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

local function drawEntry(index, entry)
    if entry.kind == "empty" then return canvasFor(chrome(BG)) end

    if entry.kind == "back" then
        local elements = chrome(DIM)
        table.insert(elements, glyphElement(entry.glyph))
        table.insert(elements, wordElement(entry.label, LABEL))
        return canvasFor(elements)
    end

    -- An armed action gets the warning colour and says so under the glyph, in place of
    -- its own name, so the deck itself is what says "press again" rather than something
    -- printed to a console nobody at the deck is looking at.
    local action = entry.action
    local isArmed = (armed == index)
    local elements = chrome(isArmed and WARN or QUIET)
    table.insert(elements, glyphElement(action.glyph))
    table.insert(elements, wordElement(isArmed and "Confirm?" or action.label,
                                        isArmed and WARN or LABEL))
    return canvasFor(elements)
end

--- SystemState.streamdeck.page() -> table
--- Function
--- The page as images keyed by key number, in the shape StreamDeck:holdKeys() wants.
function M.page()
    local images = {}
    for index, entry in ipairs(M.entries()) do
        images[index] = drawEntry(index, entry)
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

--- SystemState.streamdeck.paint()
--- Function
--- Draw the key that opens the page.
---
--- It carries no state, so this is called on connect and not again. What the page
--- offers is drawn on the page itself, once it is open, rather than mirrored onto a key
--- nobody is reading.
function M.paint()
    if not device then return end

    -- The deck can go between being handed to us and this call, and a write to one that
    -- has been unplugged throws. Dropping the handle leaves discovery to hand us the
    -- next.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawButton())
    end)
    if not ok then
        hs.printf("[SystemState] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

--- SystemState.streamdeck.setDevice(dev)
--- Function
--- Use an already-discovered device. Pass nil to detach.
function M.setDevice(dev)
    device = dev
    if dev then M.paint() end
end

--- SystemState.streamdeck.stop()
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
