--- === SlackStatus ===
---
--- Slack's unread count on a Stream Deck key: tap to go to Slack, hold to open a page of
--- status presets across the whole deck.
---
--- The key is the Slack mark carrying the same badge the Dock draws, because that badge
--- is where the count comes from. Slack ships no AppleScript dictionary and no local API,
--- so the number it puts on its own dock tile is the only one available without a
--- workspace token — and being the number already on screen makes it the right one to
--- show. See dock.lua for how it is read and what it counts.
---
--- Setting a status is the other half, and has no token either: the presets are typed in
--- as Slack's own /status command, into a conversation chosen for being harmless if the
--- command is not recognised. status.lua is where that trade-off is argued out, and it is
--- worth reading before adding a preset.
---
--- The spoon is assembled from five files, wired together below:
---
---  * `dock.lua`       - the Dock accessibility read, and the only file that knows where
---                       the count lives
---  * `monitor.lua`    - the poll loop and state snapshots
---  * `mark.lua`       - the Slack mark, as canvas elements
---  * `status.lua`     - setting a status, by driving Slack's own /status command
---  * `streamdeck.lua` - the count key and the preset page
---
--- Needs Accessibility, which Hammerspoon already holds for its hotkeys: reading the
--- badge and sending the keystrokes both go through it. Needs Slack kept in the Dock,
--- which is what has a badge on it to read.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "SlackStatus"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- SlackStatus.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) shows the unread count. Default 4.
---
--- Only the drawing of the key is meant here. Painting one key is not brokered, so two
--- surfaces given the same number paint over each other in whatever order they publish;
--- it is StreamDeck:addKey() that reports a collision, and only for presses.
obj.streamDeckButton = 4

--- SlackStatus.refreshInterval
--- Variable
--- How often (in seconds) to read the Dock badge. Default 5.
---
--- Cheap enough to be this frequent: the read is an accessibility call against a running
--- process, not a launch or a network round trip. Five seconds is the lag between a
--- message arriving and the key saying so.
obj.refreshInterval = 5

--- SlackStatus.axTimeout
--- Variable
--- How long (in seconds) to let one accessibility read block. Default 0.5.
---
--- Not a tuning knob so much as a guard. Left at the system default, reads against dock
--- items intermittently blocked for tens of seconds during development; the next poll is
--- only seconds away, so there is nothing to gain by waiting past this.
obj.axTimeout = 0.5

--- SlackStatus.dockItemTitle
--- Variable
--- The Dock item to read the badge from. Default "Slack".
obj.dockItemTitle = "Slack"

--- SlackStatus.badgeMax
--- Variable
--- Largest count drawn in full; past it the badge reads "N+". Default 99.
obj.badgeMax = 99

--- SlackStatus.markerText
--- Variable
--- What to draw for a badge that is not a number. Default "•".
---
--- Slack badges unread channels with a dot rather than a count, so this is the case where
--- there is something waiting and no number to say how much.
obj.markerText = "•"

--- SlackStatus.holdThreshold
--- Variable
--- Seconds the key must be held before it opens the page rather than counting as a tap.
--- Default 0.5.
obj.holdThreshold = 0.5

--- SlackStatus.pageTimeout
--- Variable
--- Seconds the page stays up with nothing pressed before closing itself. Default 15.
---
--- A page covers keys belonging to other modules, so one left open by a hold that was not
--- followed through takes the countdown, the calendar and the usage meter with it. Set to
--- 0 to leave it up until something is pressed.
obj.pageTimeout = 15

--- SlackStatus.pageKeys
--- Variable
--- How many keys the page covers. Default 8, a Stream Deck Plus.
---
--- The last two are Clear and Back, so this many minus two is the room for presets.
obj.pageKeys = 8

--- SlackStatus.presets
--- Variable
--- The statuses the page offers, in key order.
---
--- Each is {label, glyph, emoji, text}: `label` and `glyph` are what the key shows,
--- `emoji` and `text` are what Slack is told. `emoji` is a Slack emoji name in its
--- `:name:` form and has to be one Slack knows — an unknown name is typed through as
--- literal text and ends up in the status message.
obj.presets = {
    {label = "Meeting", glyph = "📅", emoji = ":spiral_calendar_pad:",  text = "In a meeting"},
    {label = "Focus",   glyph = "🎧", emoji = ":headphones:",           text = "Heads down"},
    {label = "Lunch",   glyph = "🍽", emoji = ":knife_fork_plate:",     text = "Out for lunch"},
    {label = "BRB",     glyph = "🏃", emoji = ":runner:",               text = "Back shortly"},
    {label = "Sick",    glyph = "🤒", emoji = ":face_with_thermometer:", text = "Out sick"},
    {label = "PTO",     glyph = "✈️", emoji = ":airplane:",             text = "On PTO"},
}

--- SlackStatus.clearLabel / SlackStatus.clearGlyph
--- Variable
--- The key that clears the status, second from last on the page.
obj.clearLabel = "Clear"
obj.clearGlyph = "✕"

--- SlackStatus.backLabel / SlackStatus.backGlyph
--- Variable
--- The key that closes the page without changing anything, last on the page.
obj.backLabel = "Back"
obj.backGlyph = "←"

--- SlackStatus.bundleID
--- Variable
--- Slack's bundle identifier, for finding the app. Default "com.tinyspeck.slackmacgap".
obj.bundleID = "com.tinyspeck.slackmacgap"

--- SlackStatus.command
--- Variable
--- The Slack command a preset is sent as. Default "/status".
obj.command = "/status"

--- SlackStatus.conversation
--- Variable
--- The conversation to type the command into. Default "Slackbot".
---
--- This is the safety catch, not a preference. The command is typed as keystrokes, so a
--- command Slack does not recognise is not a failed command but a message sent to whoever
--- is on the other end — and Slackbot's is the conversation where that costs nothing and
--- nobody else sees it. Set to nil to type into whatever Slack has open instead, which
--- is faster and puts a public channel back within reach of a mistake.
obj.conversation = "Slackbot"

--- SlackStatus.returnToConversation
--- Variable
--- Whether to go back to the conversation that was open before. Default true.
---
--- Without this, setting a status also silently moves Slack to `conversation` and leaves
--- it there, so the next thing typed into Slack goes somewhere unexpected.
obj.returnToConversation = true

--- SlackStatus.restoreFocus
--- Variable
--- Whether to give focus back to the app that had it. Default true.
obj.restoreFocus = true

--- SlackStatus.activateTimeout
--- Variable
--- Seconds to wait for Slack to come to the front before giving up. Default 2.
---
--- Nothing is typed until it is actually frontmost, so this expiring means no keystrokes
--- are sent at all — which is the outcome to want, since the alternative is sending them
--- to whatever the user was in the middle of.
obj.activateTimeout = 2

--- SlackStatus.stepDelay / SlackStatus.typeDelay / SlackStatus.settleDelay
--- Variable
--- How long (in seconds) to pause between the keystrokes that set a status.
---
--- `stepDelay` follows a single keypress, `typeDelay` follows typed text that Slack has
--- to search on, and `settleDelay` is the pause before the Return that sends the command
--- — the one that lets Slack's emoji autocomplete close, so that Return sends the line
--- instead of picking from a list still open over it. Raise them if statuses come out
--- garbled or half-typed; that is what a machine under load looks like here.
obj.stepDelay = 0.25
obj.typeDelay = 0.5
obj.settleDelay = 0.6

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so the dependency graph is
-- visible in one place and no module can be used before it has its config. The config
-- passed is this table itself, read live, so assigning to `spoon.SlackStatus.presets`
-- keeps working after start().
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which has
-- no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local dock = submodule("dock.lua")(obj)
local monitor = submodule("monitor.lua")(obj, dock)
local mark = submodule("mark.lua")
local status = submodule("status.lua")(obj)
local streamdeck = submodule("streamdeck.lua")(obj, monitor, mark)

local broker = nil
local pageTimer = nil

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- SlackStatus:state() -> table
--- Method
--- Snapshot of the unread count.
---
--- Returns a table with: count (a number, or nil when the badge carries something that is
--- not one), marker (that something, or nil), unread, badgeText (what a key should draw,
--- or nil for none), running (whether Slack is running), urgency ("unread", "quiet",
--- "closed", "idle" or "error"), hasData, fetchedAt and error.
function obj:state()
    return monitor.state()
end

--- SlackStatus:subscribe(fn) -> token
--- Method
--- Call fn with a state snapshot on every read, for a surface of your own. Returns a
--- token for unsubscribe().
function obj:subscribe(fn)
    return monitor.subscribe(fn)
end

--- SlackStatus:unsubscribe(token)
--- Method
--- Remove a subscriber registered with subscribe().
function obj:unsubscribe(token)
    monitor.unsubscribe(token)
    return self
end

--- SlackStatus:refresh()
--- Method
--- Read the badge now, rather than waiting for the next scheduled read.
function obj:refresh()
    monitor.refresh()
    return self
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

--- SlackStatus:activateSlack()
--- Method
--- Bring Slack to the front.
function obj:activateSlack()
    local app = hs.application.get(self.bundleID) or hs.application.find("Slack")
    if app then
        app:activate()
    else
        hs.printf("[SlackStatus] Slack is not running")
    end
    return self
end

--- SlackStatus:setStatus(preset)
--- Method
--- Set the Slack status from a preset table, or clear it with {clear = true}.
---
--- The badge is re-read afterwards for the same reason every action in Amphetamine ends
--- in a read: nothing about the reply says what Slack settled on, and a status change is
--- also the moment a notification is most likely to have been dealt with.
function obj:setStatus(preset)
    status.set(preset, function(ok, err)
        if not ok then
            hs.printf("[SlackStatus] could not set status: %s", tostring(err))
        end
        monitor.refresh()
    end)
    return self
end

-- ---------------------------------------------------------------------------
-- The preset page
-- ---------------------------------------------------------------------------

local function cancelPageTimer()
    if pageTimer then pageTimer:stop(); pageTimer = nil end
end

--- Dispatch for a press while the page is up. Every key on the deck arrives here, which
--- is what lets the page borrow keys other modules own.
---
--- Presses only. The hold that opens the page is still down when it opens, so its release
--- is the first event the page ever sees; acting on releases would close the page on the
--- way in, before a finger could reach anything.
local function pageKey(index, pressed)
    if not pressed then return end

    local entry = streamdeck.entries()[index]
    if not entry or entry.kind == "empty" then return end

    if entry.kind ~= "back" then obj:setStatus(entry.preset) end
    obj:closePage()
end

--- SlackStatus:openPage()
--- Method
--- Put the preset page up across the deck. Needs setBroker().
function obj:openPage()
    if not broker then
        hs.printf("[SlackStatus] no broker set; see SlackStatus:setBroker()")
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

--- SlackStatus:closePage()
--- Method
--- Take the page down and give the keys back to the modules underneath.
function obj:closePage()
    cancelPageTimer()
    if broker then broker:releaseKeys() end
    return self
end

--- SlackStatus:pageOpen() -> boolean
--- Method
--- Whether the preset page is currently up.
function obj:pageOpen()
    return broker ~= nil and broker:keysHeld()
end

-- ---------------------------------------------------------------------------
-- Presses
-- ---------------------------------------------------------------------------

local holdTimer = nil
local held = false

--- SlackStatus:handlePress(pressed)
--- Method
--- Drive the key: a tap goes to Slack, a hold opens the preset page.
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

    if not held then self:activateSlack() end
    held = false
    return self
end

-- ---------------------------------------------------------------------------
-- Stream Deck surfaces
-- ---------------------------------------------------------------------------

--- SlackStatus:setBroker(streamDeckSpoon)
--- Method
--- Give the spoon the thing that arbitrates the deck's keys, so it can open the page.
---
--- Separate from setStreamDeckDevice() because the two are different claims. Drawing the
--- count key needs a device and nothing more, and every other surface here gets by with
--- exactly that. A page is a claim on every key at once, including keys other modules own
--- and paint, and only the broker can hold those still while it is up.
function obj:setBroker(streamDeckSpoon)
    broker = streamDeckSpoon
    return self
end

--- SlackStatus:setStreamDeckDevice(dev)
--- Method
--- Mirror the count onto a key of an already-discovered deck. Pass nil to detach.
---
--- There is deliberately no discovery here: hs.streamdeck.init() installs a single
--- process-wide callback, so a spoon that called it would silently displace whatever
--- called it before. Hand the device in from StreamDeck.spoon instead.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- SlackStatus:stopStreamDeck()
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

--- SlackStatus:start()
--- Method
--- Begin reading the badge.
---
--- This starts no display surface, so that a surface and the poller can be torn down
--- independently; the Stream Deck key is claimed by setStreamDeckDevice().
function obj:start()
    monitor.start()
    return self
end

--- SlackStatus:stop()
--- Method
--- Stop reading the badge. Any status already set is left alone.
---
--- Surfaces left up keep showing the last reading and stay refreshable by hand, since
--- refresh() does not need the timer.
function obj:stop()
    monitor.stop()
    return self
end

return obj
