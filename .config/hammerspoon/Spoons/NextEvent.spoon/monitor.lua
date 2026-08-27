--- === NextEvent.monitor ===
---
--- The poll loop: runs the EventKit helper, decodes what it leaves behind, and
--- publishes a state snapshot to every subscriber.
---
--- Two timers, because the two things that change do so at very different rates. The
--- calendar itself changes rarely and costs a process launch to read, so it is
--- fetched on refreshInterval. What a surface *displays* changes every minute, since
--- it is a countdown, and rolls over to the following meeting the moment one starts —
--- both of which the ticker recomputes from the payload already in hand, launching
--- nothing.

return function(cfg)

local M = {}

local fetchTimer = nil
local tickTimer = nil
local collector = nil     -- polls the helper's output file while a fetch is in flight
local waker = nil
local subscribers = {}
local nextToken = 1

local events = nil        -- last decoded list; nil means never yet fetched
local fetchedAt = nil
local lastError = nil
local fetching = false

-- The helper is launched through LaunchServices and so inherits no stdout of ours; a
-- file is how the answer comes back. TMPDIR is per-user and mode 700, which a fixed
-- name under /tmp would not be.
local OUT = (function()
    local dir = os.getenv("TMPDIR")
    if not dir then return os.tmpname() end
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end
    return dir .. "NextEvent.json"
end)()

-- ---------------------------------------------------------------------------
-- Deriving what to show
-- ---------------------------------------------------------------------------

local function clockText(t)
    local d = os.date("*t", t)
    local hour = d.hour % 12
    if hour == 0 then hour = 12 end
    return string.format("%d:%02d", hour, d.min)
end

-- Under an hour a countdown is what you want; past that the number stops meaning
-- anything at a glance and the wall-clock time is what you would convert it to
-- anyway.
local function timeText(startsIn, startsAt)
    if startsIn <= cfg.nowThreshold then return "NOW" end
    local mins = math.floor(startsIn / 60)
    if mins < 60 then return mins .. "m" end
    return clockText(startsAt)
end

--- Pick the event the surfaces should show, and describe it.
---
--- An event that started within activeGrace outranks everything: those minutes are
--- when you are still joining the thing, and the key is the last place you look before
--- you do. Once that window closes the key goes back to pointing at what is next,
--- because a meeting you are well into is one you know you are in.
---
--- A merely in-progress event is the last resort rather than the headline, for the case
--- where it is all that is left of the day.
local function derive(now)
    local upcoming, current, active = nil, nil, nil
    for _, e in ipairs(events or {}) do
        if e.startsAt > now then
            if not upcoming or e.startsAt < upcoming.startsAt then upcoming = e end
        elseif e.endsAt > now then
            if not current or e.endsAt < current.endsAt then current = e end

            -- Latest start wins among these, not earliest end: two events inside the
            -- grace window means the one that just began is the one being joined.
            if e.startsAt >= now - cfg.activeGrace
               and (not active or e.startsAt > active.startsAt) then
                active = e
            end
        end
    end

    local showing = active or upcoming or current
    if not showing then return nil, nil, nil, nil, nil end

    local startsIn = showing.startsAt - now
    local urgency = "later"
    if startsIn <= cfg.nowThreshold then
        urgency = "now"
    elseif startsIn <= cfg.soonThreshold then
        urgency = "soon"
    end

    return showing, upcoming, current, timeText(startsIn, showing.startsAt), urgency
end

--- NextEvent.monitor.state() -> table
--- Function
--- Snapshot of what is next. See NextEvent:state() for the fields.
function M.state()
    local now = os.time()
    local showing, upcoming, current, text, urgency = derive(now)

    return {
        showing = showing,
        event = upcoming,
        current = current,
        events = events,
        -- Derived from the clock rather than from which local it came out of: `showing`
        -- can be the event inside the grace window, which is under way without being
        -- the one `current` picked.
        inProgress = showing ~= nil and showing.startsAt <= now,
        startsIn = showing and (showing.startsAt - now) or nil,
        timeText = text,
        -- An error only takes over the urgency once there is nothing left to show
        -- from a previous fetch: a stale reading beats no reading on a glanceable key.
        urgency = (lastError and not showing) and "error" or (urgency or "idle"),
        hasData = events ~= nil,
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
            hs.printf("[NextEvent] subscriber failed: %s", tostring(err))
        end
    end
end

--- NextEvent.monitor.subscribe(fn) -> token
--- Function
--- Call fn with a state snapshot on every change. Returns a token for unsubscribe().
function M.subscribe(fn)
    local token = nextToken
    nextToken = nextToken + 1
    subscribers[token] = fn
    return token
end

--- NextEvent.monitor.unsubscribe(token)
--- Function
--- Remove a subscriber registered with subscribe().
function M.unsubscribe(token)
    if token then subscribers[token] = nil end
end

-- ---------------------------------------------------------------------------
-- Fetching
-- ---------------------------------------------------------------------------

local function stopCollector()
    if collector then
        collector:stop()
        collector = nil
    end
end

local function fail(message)
    stopCollector()
    fetching = false
    lastError = message
    publish()
end

local function accept(raw)
    stopCollector()
    fetching = false

    local ok, parsed = pcall(hs.json.decode, raw)
    if not ok or type(parsed) ~= "table" then
        lastError = "could not decode helper output"
        publish()
        return
    end

    if parsed.error then
        -- "no-access" is the one worth translating: it means the grant the helper
        -- bundle holds was refused or has been revoked, which retrying cannot fix.
        -- See the header of helper/nextevent.swift for why the grant lives there and
        -- not on Hammerspoon.
        lastError = parsed.error == "no-access"
            and "calendar access denied to NextEvent.app"
            or ("helper error: " .. tostring(parsed.error))
        publish()
        return
    end

    events = parsed.events or {}
    fetchedAt = os.time()
    lastError = nil
    publish()
end

--- NextEvent.monitor.refresh()
--- Function
--- Read the calendar now. A no-op while a read is already in flight.
function M.refresh()
    if fetching then return end
    fetching = true

    -- Removed first so that the file existing again is itself the signal that this
    -- run has finished. The helper renames its output into place, so existence also
    -- means complete, and there is no partial read to distinguish from a bad one.
    os.remove(OUT)

    local app = hs.spoons.resourcePath("NextEvent.app")
    local elapsed = 0

    -- open(1) returns as soon as LaunchServices has taken the request, long before
    -- the helper has answered, so a zero exit says only "launched". A non-zero one is
    -- worth reporting immediately rather than waiting out the timeout for it.
    local launcher = hs.task.new("/usr/bin/open", function(rc, _stdOut, stdErr)
        if rc ~= 0 and fetching then
            fail(string.format("helper would not launch (open rc=%s) %s",
                               tostring(rc), (stdErr or ""):gsub("%s+$", "")))
        end
    end, {"-n", "-g", "-a", app, "--args", OUT})

    -- Going through LaunchServices is not a detail to be tidied away: exec'ing the
    -- binary directly leaves Hammerspoon as the responsible process for the TCC
    -- request, and Hammerspoon carries no NSCalendarsUsageDescription, so the request
    -- is refused without even prompting. Launching the bundle makes it answerable for
    -- itself.
    if not launcher then
        fail("could not build the helper launch task")
        return
    end
    launcher:start()

    collector = hs.timer.doEvery(cfg.pollInterval, function()
        local f = io.open(OUT, "r")
        if f then
            local raw = f:read("a")
            f:close()
            accept(raw)
            return
        end

        elapsed = elapsed + cfg.pollInterval
        if elapsed >= cfg.fetchTimeout then
            -- A first run, or the first after a rebuild re-signs the bundle, waits on
            -- a TCC prompt and on Gatekeeper re-evaluating the signature; that is
            -- what fetchTimeout is sized for, not for a healthy read.
            fail("helper did not answer within " .. cfg.fetchTimeout .. "s")
        end
    end)
end

--- NextEvent.monitor.start()
--- Function
--- Begin fetching, and begin ticking the countdown between fetches.
function M.start()
    if fetchTimer then return end

    M.refresh()
    fetchTimer = hs.timer.doEvery(cfg.refreshInterval, M.refresh)
    tickTimer = hs.timer.doEvery(cfg.tickInterval, publish)

    -- The helper is asked for "the rest of today", so a payload does not survive
    -- midnight, and a lid closed overnight is the ordinary way this thing goes stale
    -- while nobody is watching it tick. Waking is the moment before it gets looked at.
    waker = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake then M.refresh() end
    end)
    waker:start()
end

--- NextEvent.monitor.stop()
--- Function
--- Stop fetching and ticking. The last reading is kept, and refresh() still works.
function M.stop()
    if fetchTimer then fetchTimer:stop(); fetchTimer = nil end
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if waker then waker:stop(); waker = nil end
    stopCollector()
    fetching = false
end

return M

end
