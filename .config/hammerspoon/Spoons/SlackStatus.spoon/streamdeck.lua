--- === SlackStatus.streamdeck ===
---
--- Two surfaces on one deck: the key that carries the unread count, and the page of
--- status presets that a hold on it opens.
---
--- The key is the Slack mark with the Dock's own badge drawn on it, in the corner macOS
--- puts a badge in. Nothing is spelled out on it, because nothing needs to be: the mark
--- says which app and the badge says how many, and both are shapes the eye already reads
--- without stopping. The mark drops to one grey when Slack is not running, which is the
--- one state a missing badge would otherwise be indistinguishable from being caught up.
---
--- The page is the other half. It is drawn here and painted by the broker rather than by
--- this file, because a page covers keys belonging to other modules and only the broker
--- can stop those modules painting over it — see StreamDeck:holdKeys(). This hands over
--- the images and the broker decides when they reach the deck.
---
--- Painting the count key, on the other hand, happens here and directly, for the reason
--- NextEvent.streamdeck and Amphetamine.streamdeck paint theirs directly: one key is not
--- exclusive the way the button callback is. Presses are claimed a key at a time from the
--- broker and wired to SlackStatus:handlePress().

return function(cfg, monitor, mark)

local M = {}

local device = nil    -- the handle we were given, if a deck is connected
local token = nil     -- our monitor.subscribe() token
local lastState = nil -- last state, to repaint on reconnect

local BG      = {red = 0.09, green = 0.09, blue = 0.11, alpha = 1}
local WHITE   = {red = 1.00, green = 1.00, blue = 1.00, alpha = 1}
local DIM     = {red = 0.42, green = 0.42, blue = 0.45, alpha = 1}
local LABEL   = {red = 0.80, green = 0.80, blue = 0.83, alpha = 1}
local UNREAD  = {red = 0.878, green = 0.118, blue = 0.353, alpha = 1}  -- Slack's own red
local QUIET   = {red = 0.30, green = 0.32, blue = 0.36, alpha = 1}
local ALERT   = {red = 0.90, green = 0.55, blue = 0.20, alpha = 1}

-- The stripe along the top of the count key, which is the part that answers "anything
-- waiting?" from further away than a two-digit badge can be read at.
local ACCENT = {
    unread = UNREAD,
    quiet  = QUIET,
    closed = DIM,
    idle   = DIM,
    error  = ALERT,
}

local SIZE = 120
local STRIPE = 7

-- The badge disc, and how much it grows per character past the first. A one-character
-- badge is a circle; longer ones stretch sideways into a lozenge the way macOS's own do.
local BADGE_H = 36
local BADGE_PER_CHAR = 13
local BADGE_INSET = 5

-- Whether the "presets do not fit" warning has already been given. entries() is called
-- on every repaint and on every press, so without this the warning would not be a warning
-- but a stream, and would bury the console it is trying to say something in.
local warnedTruncated = false

local function glyphCount(text)
    return (utf8 and utf8.len and utf8.len(text)) or #text
end

-- ---------------------------------------------------------------------------
-- The count key
-- ---------------------------------------------------------------------------

local function badgeElements(text)
    local width = math.max(BADGE_H, 16 + BADGE_PER_CHAR * glyphCount(text))
    local x = SIZE - width - BADGE_INSET
    local y = STRIPE + BADGE_INSET

    return {
        -- A ring of background between the disc and the mark under it, so the badge reads
        -- as sitting on top rather than as a fifth coloured piece of the logo.
        {
            type = "rectangle",
            frame = {x = x - 3, y = y - 3, w = width + 6, h = BADGE_H + 6},
            roundedRectRadii = {xRadius = (BADGE_H + 6) / 2, yRadius = (BADGE_H + 6) / 2},
            fillColor = BG,
            action = "fill",
        },
        {
            type = "rectangle",
            frame = {x = x, y = y, w = width, h = BADGE_H},
            roundedRectRadii = {xRadius = BADGE_H / 2, yRadius = BADGE_H / 2},
            fillColor = UNREAD,
            action = "fill",
        },
        {
            type = "text",
            text = text,
            -- Nudged up from the box's own top edge: canvas lays text out from the
            -- ascender, which leaves it sitting low in a box this round.
            frame = {x = x, y = y + 6, w = width, h = BADGE_H},
            textColor = WHITE,
            textSize = 21,
            textAlignment = "center",
            textFont = "Helvetica-Bold",
        },
    }
end

local function drawKey(state)
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
            fillColor = ACCENT[state.urgency] or DIM,
            action = "fill",
        },
    }

    -- Slack's colours mean the app is there to be used. A Slack that is not running, or
    -- that has not been read yet, gets one grey instead, so the mark is never brand-bright
    -- while saying nothing.
    local mono = nil
    if not state.hasData or not state.running then mono = DIM end

    for _, element in ipairs(mark.elements({
        frame = {x = 14, y = STRIPE + 12, w = SIZE - 28, h = SIZE - STRIPE - 26},
        mono = mono,
    })) do
        table.insert(elements, element)
    end

    if state.badgeText and state.running then
        for _, element in ipairs(badgeElements(state.badgeText)) do
            table.insert(elements, element)
        end
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

    -- The deck can go between the state change and this call, and a write to one that has
    -- been unplugged throws. Dropping the handle leaves discovery to hand us the next.
    local ok, err = pcall(function()
        device:setButtonImage(cfg.streamDeckButton, drawKey(state))
    end)
    if not ok then
        hs.printf("[SlackStatus] Stream Deck write failed: %s", tostring(err))
        device = nil
    end
end

-- ---------------------------------------------------------------------------
-- The preset page
-- ---------------------------------------------------------------------------

--- SlackStatus.streamdeck.entries() -> table
--- Function
--- What the page shows, in key order: the presets, then Clear, then Back.
---
--- Clear and Back are appended here rather than configured, because a page with no way
--- back is a deck that has to be unplugged to escape, and a set of statuses with no way
--- to end one is half a feature. They take the last two keys, so a preset added or
--- removed never moves them.
function M.entries()
    local room = cfg.pageKeys - 2
    local list = {}

    if #cfg.presets <= room then warnedTruncated = false end

    for index, preset in ipairs(cfg.presets) do
        if index > room then
            -- Said out loud rather than quietly dropped: a preset that is configured and
            -- simply never appears is indistinguishable from one that is not working.
            if not warnedTruncated then
                warnedTruncated = true
                hs.printf("[SlackStatus] more presets than the page has room for; %q and any after it are not shown",
                          tostring(preset.label))
            end
            break
        end
        table.insert(list, {kind = "preset", preset = preset,
                            label = preset.label, glyph = preset.glyph})
    end

    -- Padded out so Clear and Back land on the last two keys whatever the preset count,
    -- rather than sliding up the deck as presets are removed.
    while #list < room do
        table.insert(list, {kind = "empty"})
    end

    table.insert(list, {kind = "clear", label = cfg.clearLabel, glyph = cfg.clearGlyph,
                        preset = {clear = true}})
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

    -- An empty slot is painted rather than left out, because a key the page does not paint
    -- keeps whatever the module underneath had on it, and half a page over half a deck
    -- reads as the page having failed.
    if entry.kind ~= "empty" then
        local accent = entry.kind == "clear" and UNREAD
                    or entry.kind == "back" and DIM
                    or QUIET
        table.insert(elements, {
            type = "rectangle",
            frame = {x = 0, y = 0, w = SIZE, h = STRIPE},
            fillColor = accent,
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
            textColor = LABEL,
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

--- SlackStatus.streamdeck.page() -> table
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
-- Lifecycle
-- ---------------------------------------------------------------------------

--- SlackStatus.streamdeck.setDevice(dev)
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

--- SlackStatus.streamdeck.stop()
--- Function
--- Stop mirroring and blank the key.
function M.stop()
    if token then
        monitor.unsubscribe(token)
        token = nil
    end
    if device then
        -- buttonCallback is deliberately not cleared: this surface never installed one,
        -- and clearing it would strip the broker's dispatcher off the device and take
        -- every other key's claim with it.
        pcall(function()
            device:setButtonColor(cfg.streamDeckButton, {red = 0, green = 0, blue = 0, alpha = 1})
        end)
        device = nil
    end
    lastState = nil
end

return M

end
