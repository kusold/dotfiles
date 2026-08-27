--- === NextEvent ===
---
--- The next thing on your calendar, on a Stream Deck key.
---
--- Reading the calendar is the whole difficulty here, and none of the obvious ways
--- work from inside Hammerspoon:
---
---  * hs.sqlite3 against the Calendar store is refused by TCC with SQLITE_AUTH,
---    since Hammerspoon has no Full Disk Access.
---  * EventKit refuses Hammerspoon without prompting, because Hammerspoon's
---    Info.plist carries no NSCalendarsUsageDescription and macOS will not offer a
---    grant to an app that never declared it wants one.
---  * Calendar.app over Apple Events, which Hammerspoon *can* be granted, does not
---    finish: a `whose start date ≥ …` query over a store of this size runs for
---    minutes.
---
--- So the calendar is read by NextEvent.app, a small signed bundle beside this file
--- that declares the usage description and therefore holds a grant of its own. It is
--- launched through LaunchServices rather than exec'd, which is what makes it
--- answerable for its own TCC request instead of Hammerspoon; see refresh() in
--- monitor.lua. It uses EventKit, so recurrence expansion, exceptions and declined
--- invitations are the framework's problem rather than ours.
---
--- The spoon is assembled from three files, wired together at the bottom of this one:
---
---  * `helper/nextevent.swift` - the EventKit query, built into NextEvent.app
---  * `monitor.lua`            - the poll loop and state snapshots
---  * `streamdeck.lua`         - the Stream Deck key
---
--- Rebuild the helper with `helper/build.sh` after editing the Swift. Re-signing
--- gives the bundle a new identity, so the first run afterwards waits on a fresh
--- permission prompt.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NextEvent"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- NextEvent.refreshInterval
--- Variable
--- How often (in seconds) to re-read the calendar. Default 300.
---
--- Each read is a process launch, and a calendar changes on the order of hours. The
--- countdown does not wait for this — tickInterval redraws it from the reading
--- already in hand — so this only governs how quickly a newly accepted invitation
--- appears.
obj.refreshInterval = 300

--- NextEvent.tickInterval
--- Variable
--- How often (in seconds) to republish state so the countdown moves. Default 30.
---
--- Costs nothing but a redraw: the same payload is re-derived against the current
--- time, which is also what rolls the key over to the following meeting the moment
--- one starts.
obj.tickInterval = 30

--- NextEvent.pollInterval
--- Variable
--- How often (in seconds) to check for the helper's output while a read is in
--- flight. Default 0.25.
obj.pollInterval = 0.25

--- NextEvent.fetchTimeout
--- Variable
--- How long (in seconds) to wait for the helper before calling the read failed.
--- Default 30.
---
--- Sized for the slow first run, not the steady state: a healthy read lands in well
--- under a second, but the run after a rebuild waits on both a permission prompt and
--- Gatekeeper re-evaluating the new signature.
obj.fetchTimeout = 30

--- NextEvent.nowThreshold
--- Variable
--- Seconds before an event's start at which it reads as happening now. Default 120.
obj.nowThreshold = 120

--- NextEvent.soonThreshold
--- Variable
--- Seconds before an event's start at which it reads as imminent. Default 900.
obj.soonThreshold = 900

--- NextEvent.activeGrace
--- Variable
--- How long (in seconds) after an event starts it still outranks whatever is next.
--- Default 600.
---
--- This is the window in which you are still joining something rather than sitting in
--- it. Set it to 0 for a key that only ever points forward.
obj.activeGrace = 600

--- NextEvent.calendarBundleID
--- Variable
--- Bundle identifier of the calendar app the key toggles. Default "com.apple.iCal",
--- which is Calendar.app.
---
--- A bundle identifier rather than a name because hs.application.get() and
--- hs.application.launchOrFocus() do not reliably resolve one name to one app: a Chrome
--- web app called "Google Calendar" is enough to make "Calendar" mean different things
--- to each, and a toggle keyed on a name can then test one app's frontmost state and
--- raise a different app. Bundle identifiers are unique, so both halves of the toggle
--- are guaranteed to be talking about the same thing.
---
--- Point it at whatever you use — "com.flexibits.fantastical2.mac", or the
--- "com.google.Chrome.app.*" identifier of a calendar web app.
obj.calendarBundleID = "com.apple.iCal"

--- NextEvent.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) shows the next event. Default 2.
---
--- Only the drawing of the key is meant here. Painting is not brokered, so two surfaces
--- given the same number will paint over each other in whatever order they happen to
--- publish; it is StreamDeck:addKey() that reports a collision, and only for presses.
obj.streamDeckButton = 2

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so the dependency
-- graph is visible in one place and no module can be used before it has its config.
-- The config passed is this table itself, read live, so assigning to
-- `spoon.NextEvent.streamDeckButton` keeps working after start().
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which
-- has no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local monitor = submodule("monitor.lua")(obj)
local streamdeck = submodule("streamdeck.lua")(obj, monitor)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- NextEvent:state() -> table
--- Method
--- Snapshot of what is next.
---
--- Returns a table with: showing (the event a surface should display, or nil), event
--- (the next event not yet started, or nil), current (an event under way, or nil),
--- events (everything left today, or nil before the first read), inProgress (whether
--- `showing` is the one under way), startsIn (seconds until `showing` starts,
--- negative once it has), timeText ("NOW", "12m" or a clock time), urgency ("now",
--- "soon", "later", "idle" or "error"), hasData, fetchedAt and error.
---
--- Each event is a table of: title, startsAt, endsAt (unix times), calendar,
--- inProgress, and location and url where the event has them.
function obj:state()
    return monitor.state()
end

--- NextEvent:subscribe(fn) -> token
--- Method
--- Call fn with a state snapshot on every change, for a surface of your own. Returns
--- a token for unsubscribe().
function obj:subscribe(fn)
    return monitor.subscribe(fn)
end

--- NextEvent:unsubscribe(token)
--- Method
--- Remove a subscriber registered with subscribe().
function obj:unsubscribe(token)
    monitor.unsubscribe(token)
    return self
end

--- NextEvent:refresh()
--- Method
--- Re-read the calendar now, rather than waiting for the next tick.
function obj:refresh()
    monitor.refresh()
    return self
end

-- ---------------------------------------------------------------------------
-- Stream Deck surface
-- ---------------------------------------------------------------------------

--- NextEvent:toggleCalendar()
--- Method
--- Bring the calendar app to the front, or hide it if it is already there.
---
--- Toggling on frontmost rather than on running: the key is pressed to see the calendar
--- and pressed again to get it out of the way, and a calendar sitting behind the window
--- you are working in has not yet been seen.
---
--- The spoon exposes the action and claims no key for it: which key presses this is a
--- decision about the whole deck, so it belongs to whatever brokers the deck. See
--- StreamDeck:addKey().
function obj:toggleCalendar()
    local running = hs.application.applicationsForBundleID(self.calendarBundleID)[1]
    if running and running:isFrontmost() then
        running:hide()
    else
        -- Covers both "running but behind something" and "not running at all", so a
        -- first press of the day launches rather than doing nothing.
        hs.application.launchOrFocusByBundleID(self.calendarBundleID)
    end
    return self
end

--- NextEvent:setStreamDeckDevice(dev)
--- Method
--- Mirror the next event onto a key of an already-discovered deck. Pass nil to
--- detach.
---
--- There is deliberately no discovery here: hs.streamdeck.init() installs a single
--- process-wide callback, so a spoon that called it would silently displace whatever
--- called it before. Hand the device in from StreamDeck.spoon instead.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- NextEvent:stopStreamDeck()
--- Method
--- Stop mirroring to the Stream Deck and blank the key.
function obj:stopStreamDeck()
    streamdeck.stop()
    return self
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- NextEvent:start()
--- Method
--- Begin reading the calendar.
---
--- This starts no display surface of its own, so that a surface and the poller can be
--- torn down independently; the Stream Deck key is claimed by
--- setStreamDeckDevice().
function obj:start()
    monitor.start()
    return self
end

--- NextEvent:stop()
--- Method
--- Stop reading the calendar.
---
--- Surfaces left up keep showing the last reading and stay refreshable by hand, since
--- refresh() does not need the timer.
function obj:stop()
    monitor.stop()
    return self
end

return obj
