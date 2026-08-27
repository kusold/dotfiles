--- === SlackStatus.monitor ===
---
--- The poll loop: reads the Dock badge on a timer and publishes a state snapshot to
--- every subscriber. Nothing here draws anything and nothing here reads the Dock; the
--- dock module does that.
---
--- One timer, unlike the two in Amphetamine.monitor and NextEvent.monitor. Those have a
--- second one because what they display moves on its own between reads — a countdown
--- counts down whether or not anything is asked. An unread count does not: it is
--- whatever it last was until Slack changes it, and there is nothing to recompute
--- between reads.
---
--- The read is synchronous, which the other monitors here cannot afford and this one can:
--- it is an accessibility read of a running process, measured at ~17ms at its worst and
--- ~0.06ms once the dock item is in hand, against the process launch or Apple Event
--- those others have to wait on.
---
--- `cfg` is the spoon table, read live, so assigning to
--- `spoon.SlackStatus.refreshInterval` keeps working after start().

return function(cfg, dock)

local M = {}

local pollTimer = nil
local waker = nil
local subscribers = {}
local nextToken = 1

local count = nil       -- last counted badge; nil while only a marker or nothing was read
local marker = nil      -- last uncounted badge, e.g. the dot Slack draws for channels
local running = nil     -- whether Slack itself is running
local hasData = false   -- whether anything has ever been read
local fetchedAt = nil
local lastError = nil

-- ---------------------------------------------------------------------------
-- Deriving what to show
-- ---------------------------------------------------------------------------

--- SlackStatus.monitor.state() -> table
--- Function
--- Snapshot of the unread count. See SlackStatus:state() for the fields.
function M.state()
    local unread = (count ~= nil and count > 0) or marker ~= nil

    -- What goes in the badge, or nil for a key that should not draw one. A count past
    -- badgeMax is shown as "N+" rather than in full, because the badge is a disc a couple
    -- of dozen pixels across and four digits in it are a smear, not a number.
    local badgeText = nil
    if count and count > 0 then
        badgeText = count > cfg.badgeMax and (cfg.badgeMax .. "+") or tostring(count)
    elseif marker then
        badgeText = cfg.markerText
    end

    local urgency
    if not hasData then
        -- An error is only the headline while there is nothing to show instead: a stale
        -- count beats no count on a key that gets glanced at.
        urgency = lastError and "error" or "idle"
    elseif not running then
        urgency = "closed"
    elseif unread then
        urgency = "unread"
    else
        urgency = "quiet"
    end

    return {
        count = count,
        marker = marker,
        unread = unread,
        badgeText = badgeText,
        running = running,
        urgency = urgency,
        hasData = hasData,
        fetchedAt = fetchedAt,
        error = lastError,
    }
end

local function publish()
    local snapshot = M.state()
    for _, fn in pairs(subscribers) do
        -- One surface throwing must not cost the others their update.
        local ok, err = pcall(fn, snapshot)
        if not ok then
            hs.printf("[SlackStatus] subscriber failed: %s", tostring(err))
        end
    end
end

--- SlackStatus.monitor.subscribe(fn) -> token
--- Function
--- Call fn with a state snapshot on every read. Returns a token for unsubscribe().
function M.subscribe(fn)
    local token = nextToken
    nextToken = nextToken + 1
    subscribers[token] = fn
    return token
end

--- SlackStatus.monitor.unsubscribe(token)
--- Function
--- Remove a subscriber registered with subscribe().
function M.unsubscribe(token)
    if token then subscribers[token] = nil end
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- SlackStatus.monitor.refresh()
--- Function
--- Read the badge now, rather than waiting for the next scheduled read.
function M.refresh()
    local reading = dock.read()

    if reading.ok then
        count, marker, running = reading.count, reading.marker, reading.running
        hasData = true
        fetchedAt = os.time()
        lastError = nil
    else
        -- The last reading is kept rather than blanked. A Dock that could not be read for
        -- a moment is not a Slack that went quiet, and the count from one poll ago is a
        -- better answer than no count — which is also why this does not clear hasData.
        if lastError ~= reading.error then
            -- Logged on the change only: a Slack taken out of the Dock fails every poll,
            -- and saying so every few seconds forever would bury everything else.
            hs.printf("[SlackStatus] %s", tostring(reading.error))
        end
        lastError = reading.error
    end

    publish()
end

--- SlackStatus.monitor.start()
--- Function
--- Begin reading the badge.
function M.start()
    if pollTimer then return end

    M.refresh()
    pollTimer = hs.timer.doEvery(cfg.refreshInterval, M.refresh)

    -- A Mac that slept is one whose Slack has been collecting messages unwatched, and
    -- waking is the moment before the key gets looked at.
    waker = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake then M.refresh() end
    end)
    waker:start()
end

--- SlackStatus.monitor.stop()
--- Function
--- Stop reading. The last reading is kept, and refresh() still works.
function M.stop()
    if pollTimer then pollTimer:stop(); pollTimer = nil end
    if waker then waker:stop(); waker = nil end
end

return M

end
