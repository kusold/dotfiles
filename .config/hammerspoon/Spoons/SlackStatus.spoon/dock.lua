--- === SlackStatus.dock ===
---
--- The unread count, read off the Dock rather than out of Slack.
---
--- Slack publishes no count anything here can ask for: the app ships no AppleScript
--- dictionary, and its Web API wants a workspace token this spoon deliberately does
--- without. What it does publish is the badge on its own dock tile, and the Dock hands
--- that back as AXStatusLabel on the app's dock item. So the number already on screen is
--- the number read here, which also makes it the right one — a key that disagreed with
--- the Dock would be worse than no key.
---
--- The permission this needs is Accessibility, which Hammerspoon holds already for its
--- hotkeys. Nothing here wants Full Disk Access, an Automation grant, or a token.
---
--- What the count *means* is Slack's decision and not this file's. It is the badge, so
--- it counts direct messages and mentions; unread channels with neither are shown by
--- Slack as a dot with no number in it. parse() therefore reports "a badge that is not a
--- number" as its own case rather than reading a dot as zero, because those two are the
--- opposite of each other to anyone glancing at the key.
---
--- Requires Slack to be kept in the Dock. An app that is not there has no dock item and
--- so no badge to read, which read() reports rather than passing off as silence.

return function(cfg)

local M = {}

-- The dock item, kept between reads. Finding it means walking every item in the Dock and
-- asking each its title, and that is the expensive half by a wide margin: measured during
-- development at ~17ms for the walk against ~0.06ms to read the label off an item already
-- in hand, which is the difference between a poll that is free and one that is not.
local item = nil

local function dockItems()
    local dock = hs.application.find("Dock")
    if not dock then return nil, "no Dock process" end
    local ax = hs.axuielement.applicationElement(dock)
    if not ax then return nil, "the Dock is not accessible" end

    -- Not optional. Without a timeout set, reads against dock items intermittently
    -- blocked for tens of seconds during development — long enough that the call never
    -- came back rather than came back late, and long enough to hang whatever asked. The
    -- AX default is far longer than a key repaint can wait, and there is nothing here
    -- worth waiting for anyway: the next poll is seconds away and asks again.
    ax:setTimeout(cfg.axTimeout)

    local top = ax:attributeValue("AXChildren")
    local list = top and top[1]
    if not list then return nil, "the Dock reported no item list" end
    return list:attributeValue("AXChildren")
end

--- Whether the cached element is still the dock item it was found as. The Dock builds
--- and discards items as apps are pinned, unpinned, launched and quit, and a discarded
--- one answers for something else or stops answering at all — neither of which is
--- distinguishable from a badge that changed, which is why this is checked and not
--- assumed.
local function stillSlack(element)
    if not element then return false end
    local ok, title = pcall(function() return element:attributeValue("AXTitle") end)
    return ok and title == cfg.dockItemTitle
end

local function findItem()
    local items, err = dockItems()
    if not items then return nil, err end
    for _, candidate in ipairs(items) do
        if candidate:attributeValue("AXTitle") == cfg.dockItemTitle then
            return candidate
        end
    end
    return nil, cfg.dockItemTitle .. " is not in the Dock"
end

--- SlackStatus.dock.parse(label) -> count, marker
--- Function
--- Read a badge label as a count, or as a marker for a badge that is not a count.
---
--- Returns 0 and nil for no badge, a number and nil for a counted one, and nil and the
--- label itself for a badge carrying something a number cannot hold. Folding that last
--- case into zero would be the one wrong answer available: it is the case where there is
--- something unread, and zero is how the key says there is not.
function M.parse(label)
    if label == nil then return 0, nil end
    local text = tostring(label)
    local digits = text:match("^%s*(%d+)")
    if digits then return tonumber(digits), nil end
    return nil, text
end

--- SlackStatus.dock.read() -> table
--- Function
--- Read the badge now.
---
--- Returns {ok = true, count, marker, running} on success, where count and marker are as
--- parse() returns them and running is whether Slack is running at all, or {ok = false,
--- error = <string>} when there was nothing to read.
function M.read()
    if not stillSlack(item) then
        local found, err = findItem()
        item = found
        if not item then return {ok = false, error = err} end
    end

    local ok, label = pcall(function() return item:attributeValue("AXStatusLabel") end)
    if not ok then
        -- The item went stale between the check above and this read. Dropping it is the
        -- whole recovery: the next read walks the Dock again and finds its replacement.
        item = nil
        return {ok = false, error = "badge read failed: " .. tostring(label)}
    end

    local count, marker = M.parse(label)
    return {
        ok = true,
        count = count,
        marker = marker,
        -- A quit Slack keeps its dock item and loses its badge, so without this the key
        -- would report a closed Slack and a caught-up one in exactly the same way.
        running = item:attributeValue("AXIsApplicationRunning") and true or false,
    }
end

return M

end
