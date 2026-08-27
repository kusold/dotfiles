--- === Amphetamine ===
---
--- Amphetamine's session on a Stream Deck key: tap to keep this Mac awake or let it
--- sleep again, hold to open a page of session lengths across the whole deck.
---
--- The key is a coffee cup, full while a session is running and empty while none is.
---
--- Amphetamine is driven entirely over AppleScript, so the first press of either kind
--- raises a TCC prompt to let Hammerspoon control Amphetamine, and does nothing until
--- it is granted. Declining leaves the key showing "allow access"; the grant lives in
--- System Settings under Privacy & Security -> Automation.
---
--- The spoon is assembled from four files, wired together below:
---
---  * `amphetamine.lua` - the Apple Events, and the only file that knows the dictionary
---  * `monitor.lua`      - the poll loop, the countdown, and state snapshots
---  * `cup.lua`          - the coffee cup, as canvas elements
---  * `streamdeck.lua`   - the Stream Deck key and the session-length page
---
--- start() and stop() are the poll loop, in the same sense as every other spoon here,
--- and not a session: toggle(), sessionUntil(), sessionFor() and endSession() are what
--- change whether the Mac stays awake.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Amphetamine"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- Amphetamine.pageKeys
--- Variable
--- How many keys the session-length page covers. Default 8, a Stream Deck Plus.
---
--- The last is Back, so this many minus one is the room for session-length options.
obj.pageKeys = 8

--- Amphetamine.pageTimeout
--- Variable
--- Seconds the page stays up with nothing pressed before closing itself. Default 15.
---
--- A page covers keys belonging to other modules, so one left open by a hold that was
--- not followed through takes the rest of the deck with it. Set to 0 to leave it up
--- until something is pressed.
obj.pageTimeout = 15

--- Amphetamine.backLabel / Amphetamine.backGlyph
--- Variable
--- The key that closes the page without starting anything, last on the page.
obj.backLabel = "Back"
obj.backGlyph = "←"

--- Amphetamine.options
--- Variable
--- The session lengths the page offers, in key order.
---
--- Each is {label, glyph, hour, minute} for a session lasting until the next
--- hour:minute (0-23, 0-59) of the day, or {label, glyph, minutes} for one lasting
--- that many minutes from now. Whichever pair is present is how the key press calls
--- sessionUntil() or sessionFor() — see pageKey() in the section below.
obj.options = {
    {label = "Until 6PM",      glyph = "🌇", hour = 18, minute = 0},
    {label = "Until 8PM",      glyph = "🌆", hour = 20, minute = 0},
    {label = "Until Midnight", glyph = "🌙", hour = 0,  minute = 0},
    {label = "2hr",  glyph = "⏱", minutes = 120},
    {label = "4hr",  glyph = "⏱", minutes = 240},
    {label = "8hr",  glyph = "⏱", minutes = 480},
    {label = "12hr", glyph = "⏱", minutes = 720},
}

--- Amphetamine.displaySleepAllowed
--- Variable
--- Whether the sessions this spoon starts let the display sleep. Default false.
---
--- False is the setting that makes a session mean what the key is usually pressed for:
--- the screen stays lit as well as the machine awake. Amphetamine's own preference is
--- not consulted, because a record passed to `start new session` replaces it, so this is
--- the only place the answer can come from.
obj.displaySleepAllowed = false

--- Amphetamine.holdThreshold
--- Variable
--- Seconds a key must be held before it counts as a hold rather than a tap. Default 0.5.
obj.holdThreshold = 0.5

--- Amphetamine.endingThreshold
--- Variable
--- Seconds left in a session at which it reads as about to end. Default 900.
obj.endingThreshold = 900

--- Amphetamine.refreshInterval
--- Variable
--- How often (in seconds) to read Amphetamine's session. Default 30.
---
--- The countdown does not wait for this — tickInterval redraws it from the reading
--- already in hand — so this only governs how quickly a session started or ended from
--- Amphetamine's own menu bar item shows up on the key.
obj.refreshInterval = 30

--- Amphetamine.tickInterval
--- Variable
--- How often (in seconds) to republish state so the countdown moves. Default 10.
---
--- Costs nothing but a redraw. Ten seconds against a display whose smallest step is a
--- minute is what keeps the number on the key from being visibly behind the clock.
obj.tickInterval = 10

--- Amphetamine.commandTimeout
--- Variable
--- How long (in seconds) to wait for Amphetamine to answer before giving up on a
--- command. Default 10.
obj.commandTimeout = 10

--- Amphetamine.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) shows the session. Default 3.
---
--- Only the drawing of the key is meant here. Painting is not brokered, so two surfaces
--- given the same number will paint over each other in whatever order they happen to
--- publish; it is StreamDeck:addKey() that reports a collision, and only for presses.
obj.streamDeckButton = 3

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so the dependency graph
-- is visible in one place and no module can be used before it has its config. The
-- config passed is this table itself, read live, so assigning to
-- `spoon.Amphetamine.options` keeps working after start().
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which has
-- no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local amphetamine = submodule("amphetamine.lua")(obj)
local monitor = submodule("monitor.lua")(obj, amphetamine)
local cup = submodule("cup.lua")
local streamdeck = submodule("streamdeck.lua")(obj, monitor, cup)

local broker = nil
local pageTimer = nil

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- Amphetamine:state() -> table
--- Method
--- Snapshot of the current session.
---
--- Returns a table with: active (whether anything is keeping the Mac awake), kind, remaining
--- (seconds left, for a timed session), endsAt (unix time it ends, for a timed session),
--- timeText ("OFF", "ON", "3h47", "47m" or "<1m"), urgency ("on", "ending", "off", "idle"
--- or "error"), hasData, fetchedAt, error and hint.
---
--- kind is "off", "infinite" for a session with no end, "timed" for one counting down,
--- "trigger" for one Amphetamine's own Triggers started, or "external" for the two kinds
--- Amphetamine will not report a remaining time for — a session lasting while an app runs,
--- and one lasting until a set time. It is nil before the first read.
function obj:state()
    return monitor.state()
end

--- Amphetamine:subscribe(fn) -> token
--- Method
--- Call fn with a state snapshot on every change, for a surface of your own. Returns a
--- token for unsubscribe().
function obj:subscribe(fn)
    return monitor.subscribe(fn)
end

--- Amphetamine:unsubscribe(token)
--- Method
--- Remove a subscriber registered with subscribe().
function obj:unsubscribe(token)
    monitor.unsubscribe(token)
    return self
end

--- Amphetamine:refresh()
--- Method
--- Read Amphetamine's session now, rather than waiting for the next scheduled read.
function obj:refresh()
    monitor.refresh()
    return self
end

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------

-- Every action reconciles the same way: adopt the session the command was told to make,
-- so the key lights on the reply rather than a process launch later, then read, because
-- the reply cannot say what Amphetamine settled on. A failure skips the adoption and
-- reads anyway, so the key ends up showing what is true rather than what was attempted.
--
-- `resolve` maps the bridge's reply to that session, as kind and end time, because only
-- toggle() learns which of the two it did from the reply itself.
local function reconcile(verb, resolve)
    return function(result, err)
        if not result then
            hs.printf("[Amphetamine] could not %s: %s", verb, tostring(err and err.message))
        else
            monitor.expect(resolve(result))
        end
        monitor.refresh()
    end
end

--- Amphetamine:toggle()
--- Method
--- End the session if one is running, start an endless one if not.
---
--- Endless rather than of some default length, because this is the half of the key that
--- means "not now" and "keep going": a length is what the held press is for.
function obj:toggle()
    amphetamine.toggle(reconcile("toggle session", function(result)
        return result == "on" and "infinite" or "off", nil
    end))
    return self
end

-- Minutes from now until the next hour:minute of the day, and the unix time that is.
--
-- The next one is rebuilt through os.time() with a day of one more rather than by adding
-- a day's worth of seconds, because the two differ by an hour across a daylight-saving
-- boundary: os.time() resolves a local date through mktime(), which normalises an
-- out-of-range day and then applies whatever offset is in force on the day it lands on.
local function nextTarget(hour, minute)
    local now = os.time()
    local today = os.date("*t", now)
    local function at(day)
        return os.time({year = today.year, month = today.month, day = day,
                        hour = hour, min = minute, sec = 0})
    end

    -- Past today's, "until 8pm" has only tomorrow's left to mean. A session that long is
    -- a surprising thing to ask for by accident, which is the other thing the countdown
    -- is for: "23h59" on the key is unmistakable, and a tap ends it.
    local target = at(today.day)
    if target <= now then target = at(today.day + 1) end

    -- Rounded up, so the session outlasts the target by under a minute rather than
    -- ending short of it: a minute is the smallest length Amphetamine can be asked for,
    -- and staying awake a moment past the hour is the harmless direction to be wrong in.
    --
    -- Never rounded to zero, because zero is not a short session but an endless one: a
    -- length is `duration` times the interval, so zero minutes is no length at all, and
    -- a zero duration is half of how the sdef says an endless session is asked for.
    return math.max(1, math.ceil((target - now) / 60)), target
end

--- Amphetamine:sessionUntil(hour, minute)
--- Method
--- Keep this Mac awake until the next hour:minute of the day, and count down to it.
---
--- The next one, so a press after the target has passed today means tomorrow's rather
--- than nothing at all.
function obj:sessionUntil(hour, minute)
    local minutes, target = nextTarget(hour, minute)
    amphetamine.sessionFor(minutes, reconcile("start session", function()
        return "timed", target
    end))
    return self
end

--- Amphetamine:sessionFor(minutes)
--- Method
--- Keep this Mac awake for that many minutes, replacing any session already running.
function obj:sessionFor(minutes)
    local target = os.time() + minutes * 60
    amphetamine.sessionFor(minutes, reconcile("start session", function()
        return "timed", target
    end))
    return self
end

--- Amphetamine:endSession()
--- Method
--- Let this Mac sleep again.
function obj:endSession()
    amphetamine.endSession(reconcile("end session", function()
        return "off", nil
    end))
    return self
end

-- ---------------------------------------------------------------------------
-- Presses
-- ---------------------------------------------------------------------------

local holdTimer = nil
local held = false

--- Amphetamine:handlePress(pressed)
--- Method
--- Drive the key: a tap toggles the session, a hold opens the session-length page.
---
--- The page opens the moment holdThreshold passes rather than on release, so the deck
--- changes under a finger that is still down — which is the only signal there is that a
--- hold was long enough, and the thing that says to let go.
---
--- The spoon exposes this and claims no key for it: which key presses this is a decision
--- about the whole deck, so it belongs to whatever brokers the deck. It needs both edges
--- of the press, so it is wired to a key directly rather than through a `pressed` test at
--- the call site. See StreamDeck:addKey().
function obj:handlePress(pressed)
    -- Cancelled first thing on either edge: a down that arrives without its up, which is
    -- what a deck unplugged mid-press leaves behind, must not still be holding a timer
    -- that opens a page later.
    if holdTimer then holdTimer:stop(); holdTimer = nil end

    if pressed then
        held = false
        holdTimer = hs.timer.doAfter(self.holdThreshold, function()
            holdTimer = nil
            held = true
            self:openPage()
        end)
        return self
    end

    if not held then self:toggle() end
    held = false
    return self
end

-- ---------------------------------------------------------------------------
-- The session-length page
-- ---------------------------------------------------------------------------

local function cancelPageTimer()
    if pageTimer then pageTimer:stop(); pageTimer = nil end
end

--- Dispatch for a press while the page is up. Every key on the deck arrives here, which
--- is what lets the page borrow keys other modules own.
---
--- Presses only. The hold that opens the page is still down when it opens, so its
--- release is the first event the page ever sees; acting on releases would close the
--- page on the way in, before a finger could reach anything.
local function pageKey(index, pressed)
    if not pressed then return end

    local entry = streamdeck.entries()[index]
    if not entry or entry.kind == "empty" then return end

    if entry.kind == "option" then
        local option = entry.option
        if option.minutes then
            obj:sessionFor(option.minutes)
        else
            obj:sessionUntil(option.hour, option.minute)
        end
    end
    obj:closePage()
end

--- Amphetamine:openPage()
--- Method
--- Put the session-length page up across the deck. Needs setBroker().
function obj:openPage()
    if not broker then
        hs.printf("[Amphetamine] no broker set; see Amphetamine:setBroker()")
        return self
    end

    broker:holdKeys({paint = streamdeck.page, key = pageKey})

    cancelPageTimer()
    if self.pageTimeout > 0 then
        pageTimer = hs.timer.doAfter(self.pageTimeout, function()
            pageTimer = nil
            obj:closePage()
        end)
    end
    return self
end

--- Amphetamine:closePage()
--- Method
--- Take the page down and give the keys back to the modules underneath.
function obj:closePage()
    cancelPageTimer()
    if broker then broker:releaseKeys() end
    return self
end

--- Amphetamine:pageOpen() -> boolean
--- Method
--- Whether the session-length page is currently up.
function obj:pageOpen()
    return broker ~= nil and broker:keysHeld()
end

-- ---------------------------------------------------------------------------
-- Stream Deck surfaces
-- ---------------------------------------------------------------------------

--- Amphetamine:setBroker(streamDeckSpoon)
--- Method
--- Give the spoon the thing that arbitrates the deck's keys, so it can open the page.
---
--- Separate from setStreamDeckDevice() because the two are different claims. Drawing the
--- key needs a device and nothing more, and painting it gets by with exactly that. A page
--- is a claim on every key at once, including keys other modules own and paint, and only
--- the broker can hold those still while it is up.
function obj:setBroker(streamDeckSpoon)
    broker = streamDeckSpoon
    return self
end

--- Amphetamine:setStreamDeckDevice(dev)
--- Method
--- Mirror the session onto a key of an already-discovered deck. Pass nil to detach.
---
--- There is deliberately no discovery here: hs.streamdeck.init() installs a single
--- process-wide callback, so a spoon that called it would silently displace whatever
--- called it before. Hand the device in from StreamDeck.spoon instead.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- Amphetamine:stopStreamDeck()
--- Method
--- Stop mirroring to the Stream Deck and blank the key.
function obj:stopStreamDeck()
    self:closePage()
    streamdeck.stop()
    return self
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- Amphetamine:start()
--- Method
--- Begin reading Amphetamine's session. Starts no session of its own.
---
--- This starts no display surface either, so that a surface and the poller can be torn
--- down independently; the Stream Deck key is claimed by setStreamDeckDevice().
function obj:start()
    monitor.start()
    return self
end

--- Amphetamine:stop()
--- Method
--- Stop reading Amphetamine's session. Leaves any running session alone.
---
--- Surfaces left up keep showing the last reading and stay refreshable by hand, since
--- refresh() does not need the timer.
function obj:stop()
    monitor.stop()
    return self
end

return obj
