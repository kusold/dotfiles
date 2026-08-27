--- === Amphetamine.streamdeck ===
---
--- Two surfaces on one deck: the key whose cup is full while something is keeping this
--- Mac awake and empty while nothing is, with the countdown beneath it when the session
--- has an end to count down to; and the page of session lengths that a hold on it opens.
---
--- The cup carries the state and no word does, which is the point: awake and asleep are
--- the two things this key exists to tell apart, and neither needs reading. Text is kept
--- for the two states a cup cannot express — how long is left, and that something is
--- broken.
---
--- The page is the other half. It is drawn here and painted by the broker rather than by
--- this file, because a page covers keys belonging to other modules and only the broker
--- can stop those modules painting over it — see StreamDeck:holdKeys(). This hands over
--- the images and the broker decides when they reach the deck.
---
--- Painting the cup key, on the other hand, happens here and directly, for the reason
--- NextEvent.streamdeck and SlackStatus.streamdeck paint theirs directly: one key is not
--- exclusive the way the button callback is. Presses are claimed a key at a time from the
--- broker, and Amphetamine:handlePress() is what a claim on this key is wired to.

return function(cfg, monitor, cup)

local M = {}

local device = nil    -- the device we were handed, if connected
local token = nil     -- our monitor.subscribe() token
local lastState = nil -- last state, to repaint on reconnect

-- Whether the "options do not fit" warning has already been given. entries() is called
-- on every repaint and on every press, so without this the warning would not be a
-- warning but a stream, and would bury the console it is trying to say something in.
local warnedTruncated = false

local BG     = {red=0.09, green=0.09, blue=0.11, alpha=1}
local DIM    = {red=0.60, green=0.60, blue=0.62, alpha=1}
local AWAKE  = {red=0.40, green=0.82, blue=0.50, alpha=1}
local ENDING = {red=0.98, green=0.75, blue=0.35, alpha=1}
local ALERT  = {red=0.90, green=0.25, blue=0.22, alpha=1}

-- The accent colours the cup and the stripe together, so the key answers "is this Mac
-- staying awake" from across a desk, before the countdown resolves into digits.
local ACCENT = {
    on     = AWAKE,
    ending = ENDING,
    off    = DIM,
    idle   = DIM,
    error  = ALERT,
}

local SIZE = 120
local STRIPE = 7

-- The coffee is a dimmed shade of whatever the cup is drawn in rather than a brown of its
-- own, so a single accent still carries the state: a cup in its last quarter hour turns
-- amber and its coffee turns with it. Filled in the cup's exact colour instead, a full cup
-- closes into one solid shape and stops reading as a cup at all.
local COFFEE_DIM = 0.70

local function coffeeFor(color)
    return {
        red = color.red * COFFEE_DIM,
        green = color.green * COFFEE_DIM,
        blue = color.blue * COFFEE_DIM,
        alpha = 1,
    }
end

--- What goes under the cup, at what size and in what face — or nothing, for the states
--- the cup already says on its own.
---
--- Copy lives here rather than in the monitor so that a second surface can word the same
--- state differently. There is much less of it than there was before the cup: a countdown
--- is the one thing an icon cannot count, and an error is the one thing it cannot explain,
--- since no cup can say that Hammerspoon has not been allowed to talk to Amphetamine.
local function note(state)
    if state.kind == "timed" then
        return state.timeText, 28, "Menlo-Bold"
    end
    if not state.hasData and state.error then
        return state.hint or "error", 13, "Helvetica-Bold"
    end
    return nil
end

local function drawButton(state)
    local accent = ACCENT[state.urgency] or DIM
    local text, textSize, textFont = note(state)

    local elements = {
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

    -- The cup takes what is left of the key: nearly all of it when it has the key to
    -- itself, the upper half when a countdown is sharing it. One drawing at two sizes,
    -- rather than two layouts that would have to be kept looking like each other.
    local cupFrame = text
        and {x = 0, y = STRIPE + 6,  w = SIZE, h = 58}
        or  {x = 0, y = STRIPE + 8,  w = SIZE, h = SIZE - STRIPE - 18}

    for _, element in ipairs(cup.elements({
        frame = cupFrame,
        color = accent,
        filled = state.active,
        coffee = coffeeFor(accent),
    })) do
        table.insert(elements, element)
    end

    if text then
        table.insert(elements, {
            type = "text",
            text = text,
            frame = {x = 4, y = 74, w = SIZE - 8, h = SIZE - 78},
            textColor = accent,
            textSize = textSize,
            textAlignment = "center",
            textFont = textFont,
        })
    end

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
        hs.printf("[Amphetamine] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

-- ---------------------------------------------------------------------------
-- The session-length page
-- ---------------------------------------------------------------------------

--- Amphetamine.streamdeck.entries() -> table
--- Function
--- What the page shows, in key order: the session-length options, then Back.
---
--- Back is appended here rather than configured, because a page with no way back is a
--- key that has to be unplugged to escape. It takes the last key, so an option added or
--- removed never moves it.
function M.entries()
    local room = cfg.pageKeys - 1
    local list = {}

    if #cfg.options <= room then warnedTruncated = false end

    for index, option in ipairs(cfg.options) do
        if index > room then
            -- Said out loud rather than quietly dropped: an option that is configured
            -- and simply never appears is indistinguishable from one that is not working.
            if not warnedTruncated then
                warnedTruncated = true
                hs.printf("[Amphetamine] more options than the page has room for; %q and any after it are not shown",
                          tostring(option.label))
            end
            break
        end
        table.insert(list, {kind = "option", option = option,
                            label = option.label, glyph = option.glyph})
    end

    -- Padded out so Back lands on the last key whatever the option count, rather than
    -- sliding up the deck as options are removed.
    while #list < room do
        table.insert(list, {kind = "empty"})
    end

    table.insert(list, {kind = "back", label = cfg.backLabel, glyph = cfg.backGlyph})
    return list
end

local function drawEntry(entry)
    local canvas = hs.canvas.new({x = 0, y = 0, w = SIZE, h = SIZE})
    local elements = {{
        type = "rectangle",
        frame = {x = 0, y = 0, w = SIZE, h = SIZE},
        fillColor = BG,
        action = "fill",
    }}

    -- An empty slot is painted rather than left out, because a key the page does not
    -- paint keeps whatever the module underneath had on it, and half a page over half a
    -- deck reads as the page having failed.
    if entry.kind ~= "empty" then
        table.insert(elements, {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = STRIPE},
            fillColor = entry.kind == "back" and DIM or AWAKE,
            action = "fill",
        })
        table.insert(elements, {
            type = "text",
            text = entry.glyph or "",
            frame = {x = 0, y = STRIPE + 12, w = SIZE, h = 60},
            textSize = 44,
            textAlignment = "center",
        })
        table.insert(elements, {
            type = "text",
            text = entry.label or "",
            frame = {x = 4, y = SIZE - 34, w = SIZE - 8, h = 30},
            textColor = DIM,
            textSize = 16,
            textAlignment = "center",
            textFont = "Helvetica-Bold",
        })
    end

    canvas:appendElements(elements)
    local image = canvas:imageFromCanvas()
    canvas:delete()
    return image
end

--- Amphetamine.streamdeck.page() -> table
--- Function
--- The page as images keyed by key number, in the shape StreamDeck:holdKeys() wants.
function M.page()
    local images = {}
    for index, entry in ipairs(M.entries()) do
        images[index] = drawEntry(entry)
    end
    return images
end

--- Amphetamine.streamdeck.setDevice(dev)
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

--- Amphetamine.streamdeck.stop()
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
