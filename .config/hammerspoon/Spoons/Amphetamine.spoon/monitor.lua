--- === Amphetamine.monitor ===
---
--- The poll loop: reads Amphetamine on a timer and publishes a state snapshot to every
--- subscriber. Nothing here draws anything, and nothing here sends an Apple Event of
--- its own; the bridge does that.
---
--- Two timers, for the reason NextEvent.monitor has two. What the session *is* changes
--- only when something changes it, and costs a process launch to read, so it is read on
--- refreshInterval — slowly, and only so that a session started or ended from
--- Amphetamine's own menu bar item shows up here. What a surface *displays* is a
--- countdown, which moves on its own; the ticker recomputes that from the reading
--- already in hand and launches nothing.
---
--- The countdown is derived from an end time rather than by decrementing a remaining
--- count, so it cannot drift with the ticker and stays right across a sleep: the
--- session ends at a wall-clock moment, and os.time() is the same clock on the other
--- side of a lid.
---
--- `cfg` is the spoon table, read live, so assigning to
--- `spoon.Amphetamine.refreshInterval` keeps working after start().

return function(cfg, amphetamine)

local M = {}

local fetchTimer = nil
local tickTimer = nil
local waker = nil
local subscribers = {}
local nextToken = 1

local kind = nil        -- a kind from the bridge; nil means nothing has been read yet
local endsAt = nil      -- unix time a "timed" session ends
local fetchedAt = nil
local lastError = nil   -- the bridge's error table, or nil
local fetching = false
local refetch = false   -- a read was asked for while one was already in flight

-- ---------------------------------------------------------------------------
-- Deriving what to show
-- ---------------------------------------------------------------------------

--- A countdown reads as a countdown under the hour and as an hours-and-minutes figure
--- above it, where the minutes alone have stopped meaning anything at a glance.
---
--- The last minute is "<1m" rather than a second count: seconds would be the one part
--- of this display the ticker could not keep up with, and nothing about a session that
--- has all but ended is worth a redraw every second to say.
local function countdownText(seconds)
    if seconds >= 3600 then
        return string.format("%dh%02d", math.floor(seconds / 3600),
                             math.floor((seconds % 3600) / 60))
    end
    if seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    end
    return "<1m"
end

--- Amphetamine.monitor.state() -> table
--- Function
--- Snapshot of the current session. See Amphetamine:state() for the fields.
function M.state()
    local now = os.time()

    local remaining = nil
    if kind == "timed" and endsAt then
        -- Clamped, because the ticker can reach here in the moment between a session
        -- expiring and the read that notices; a negative countdown would be a display
        -- of something that has already happened.
        remaining = math.max(0, endsAt - now)
    end

    local timeText = ""
    if kind == "off" then
        timeText = "OFF"
    elseif remaining then
        timeText = countdownText(remaining)
    elseif kind then
        timeText = "ON"
    end

    local urgency
    if kind == nil then
        -- An error only becomes the headline while there is nothing to show instead: a
        -- stale reading beats no reading on a glanceable key.
        urgency = lastError and "error" or "idle"
    elseif kind == "off" then
        urgency = "off"
    elseif remaining and remaining <= cfg.endingThreshold then
        urgency = "ending"
    else
        urgency = "on"
    end

    return {
        active = kind ~= nil and kind ~= "off",
        kind = kind,
        remaining = remaining,
        endsAt = (kind == "timed") and endsAt or nil,
        timeText = timeText,
        urgency = urgency,
        hasData = kind ~= nil,
        fetchedAt = fetchedAt,
        error = lastError and lastError.message or nil,
        hint = lastError and lastError.hint or nil,
    }
end

local function publish()
    local snapshot = M.state()
    for _, fn in pairs(subscribers) do
        -- One surface throwing must not cost the others their update.
        local ok, err = pcall(fn, snapshot)
        if not ok then
            hs.printf("[Amphetamine] subscriber failed: %s", tostring(err))
        end
    end
end

--- Amphetamine.monitor.subscribe(fn) -> token
--- Function
--- Call fn with a state snapshot on every change. Returns a token for unsubscribe().
function M.subscribe(fn)
    local token = nextToken
    nextToken = nextToken + 1
    subscribers[token] = fn
    return token
end

--- Amphetamine.monitor.unsubscribe(token)
--- Function
--- Remove a subscriber registered with subscribe().
function M.unsubscribe(token)
    if token then subscribers[token] = nil end
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- Amphetamine.monitor.expect(newKind, newEndsAt)
--- Function
--- Adopt the session an action has just been told was started, and publish it.
---
--- Called only once the bridge has reported the command succeeded, so this is not a
--- guess about whether it worked — it is the exact end time the command asked for,
--- which no reply carries and a read would cost another process launch to learn. That
--- read is still made, because Amphetamine can end up somewhere else: the sdef warns a
--- Trigger session "may immediately restart" after being ended.
---
--- fetchedAt is deliberately left alone. Nothing here is a reading, and it must not be
--- able to make a failing read look like a fresh one.
function M.expect(newKind, newEndsAt)
    kind = newKind
    endsAt = newEndsAt
    publish()
end

--- Amphetamine.monitor.refresh()
--- Function
--- Read the session now, rather than waiting for the next scheduled read.
function M.refresh()
    if fetching then
        -- The read an action asks for must not be dropped because a scheduled one was
        -- already in flight: that one was sent before the action happened and cannot
        -- answer for it.
        refetch = true
        return
    end
    fetching = true

    amphetamine.read(function(reading, err)
        fetching = false

        if reading then
            kind = reading.kind
            endsAt = reading.remaining and (os.time() + reading.remaining) or nil
            fetchedAt = os.time()
            lastError = nil
        else
            -- Kept, rather than blanking the last reading: an unreachable Amphetamine
            -- does not mean the Mac stopped being awake. hint is what a key can show;
            -- the whole message only ever goes to the console.
            lastError = err
            hs.printf("[Amphetamine] read failed: %s", tostring(err and err.message))
        end

        publish()

        if refetch then
            refetch = false
            M.refresh()
        end
    end)
end

local function tick()
    -- The end of a timed session is the one moment the reading in hand is knowably
    -- wrong: Amphetamine ends the session itself and sends nothing to say so. Reading
    -- here is what rolls a key over to OFF at the end of its countdown instead of at
    -- the next scheduled read.
    if kind == "timed" and endsAt and os.time() >= endsAt then
        M.refresh()
    end
    publish()
end

--- Amphetamine.monitor.start()
--- Function
--- Begin reading, and begin ticking the countdown between reads.
function M.start()
    if fetchTimer then return end

    M.refresh()
    fetchTimer = hs.timer.doEvery(cfg.refreshInterval, M.refresh)
    tickTimer = hs.timer.doEvery(cfg.tickInterval, tick)

    -- A Mac that slept is one whose session may have expired unwatched, and it is
    -- exactly the machine this spoon is about: waking is the moment before the key gets
    -- looked at.
    waker = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake then M.refresh() end
    end)
    waker:start()
end

--- Amphetamine.monitor.stop()
--- Function
--- Stop reading and ticking. The last reading is kept, and refresh() still works.
function M.stop()
    if fetchTimer then fetchTimer:stop(); fetchTimer = nil end
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if waker then waker:stop(); waker = nil end
end

return M

end
