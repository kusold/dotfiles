--- === SystemState ===
---
--- System power on a Stream Deck key: press it and the deck turns into Lock, Sleep,
--- Restart and Shutdown; press one of those to do it.
---
--- Lock and Sleep act on one press, the same as everything else on this deck — they are
--- not destructive, so the page opening is already the deliberate act. Restart and
--- Shutdown are, so pressing one arms it instead: the key turns orange and says
--- "Confirm?", and only a second press on that same key carries it out. Pressing
--- anything else — Back, the other action, a second tap on the key that opened the
--- page — cancels the arm rather than acting on it, and it also cancels itself after
--- armTimeout seconds of being left alone.
---
--- The spoon is assembled from two files, wired together below:
---
---  * `streamdeck.lua` - the key that opens the page, the page, and the armed state
---
--- There is no start(): nothing here polls and nothing here holds state between
--- presses except which key is armed, which lives in streamdeck.lua for the same reason
--- WindowGrid.streamdeck keeps which page of layouts is showing — see that file. Give it
--- a device with setStreamDeckDevice(), the broker with setBroker(), and a key of its
--- own to be opened from.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "SystemState"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- SystemState.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) opens the page. Default 6.
---
--- Only the drawing of the key is meant here. Painting one key is not brokered, so two
--- surfaces given the same number paint over each other in whatever order they publish;
--- it is StreamDeck:addKey() that reports a collision, and only for presses.
obj.streamDeckButton = 6

--- SystemState.buttonLabel / SystemState.buttonGlyph
--- Variable
--- The word and symbol on the key that opens the page. Default "Power" and "⏻".
obj.buttonLabel = "Power"
obj.buttonGlyph = "⏻"

--- SystemState.pageKeys
--- Variable
--- How many keys the page covers. Default 8, a Stream Deck Plus.
---
--- The last is always Back; what is left over is room for actions.
obj.pageKeys = 8

--- SystemState.pageTimeout
--- Variable
--- Seconds the page stays up with nothing pressed before closing itself. Default 15.
---
--- Restarted on every press, so it measures the page being abandoned rather than the
--- time since it opened. Worth having because the page covers keys belonging to other
--- modules, and one left open takes them with it. Set to 0 to leave it up until Back is
--- pressed.
obj.pageTimeout = 15

--- SystemState.armTimeout
--- Variable
--- Seconds a Restart or Shutdown key stays armed, waiting for its confirming press,
--- before reverting on its own. Default 4.
obj.armTimeout = 4

--- SystemState.backLabel / SystemState.backGlyph
--- Variable
--- The key that closes the page without doing anything, last on it. Worded and drawn
--- as SlackStatus's and WindowGrid's own Back key are, so that one page idiom covers
--- all three.
obj.backLabel = "Back"
obj.backGlyph = "←"

--- SystemState.actions
--- Variable
--- The actions the page offers, in key order.
---
--- Each is {kind, label, glyph, confirm}: `kind` picks which of SystemState's methods a
--- press calls, `label` and `glyph` are what the key shows, and `confirm` is whether a
--- press arms the key instead of acting immediately — see the note at the top of this
--- file. `kind` has to be one this spoon knows about; see pageKey() below for the list.
obj.actions = {
    {kind = "lock",     label = "Lock",     glyph = "🔒", confirm = false},
    {kind = "sleep",    label = "Sleep",    glyph = "🌙", confirm = false},
    {kind = "restart",  label = "Restart",  glyph = "🔁", confirm = true},
    {kind = "shutdown", label = "Shutdown", glyph = "⏻",  confirm = true},
}

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- The config passed is this table itself, read live, so assigning to
-- `spoon.SystemState.actions` keeps working after the spoon is loaded.
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which
-- has no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local streamdeck = submodule("streamdeck.lua")(obj)

local broker = nil
local pageTimer = nil
local armTimer = nil

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

--- SystemState:lockScreen()
--- Method
--- Lock the displays.
function obj:lockScreen()
    hs.caffeinate.lockScreen()
    return self
end

--- SystemState:sleep()
--- Method
--- Put the system to sleep immediately.
function obj:sleep()
    hs.caffeinate.systemSleep()
    return self
end

--- SystemState:restart()
--- Method
--- Request the system reboot, the same as choosing Restart from the Apple menu.
function obj:restart()
    hs.caffeinate.restartSystem()
    return self
end

--- SystemState:shutdown()
--- Method
--- Request the system log out and power down, the same as choosing Shut Down from the
--- Apple menu.
function obj:shutdown()
    hs.caffeinate.shutdownSystem()
    return self
end

local function fire(action)
    if action.kind == "lock" then obj:lockScreen()
    elseif action.kind == "sleep" then obj:sleep()
    elseif action.kind == "restart" then obj:restart()
    elseif action.kind == "shutdown" then obj:shutdown()
    else hs.printf("[SystemState] unknown action kind %q", tostring(action.kind))
    end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function cancelPageTimer()
    if pageTimer then pageTimer:stop(); pageTimer = nil end
end

local function armPageTimer()
    cancelPageTimer()
    if obj.pageTimeout > 0 then
        pageTimer = hs.timer.doAfter(obj.pageTimeout, function()
            pageTimer = nil
            obj:closePage()
        end)
    end
end

local function cancelArmTimer()
    if armTimer then armTimer:stop(); armTimer = nil end
end

-- Disarms whatever is currently armed, whether that is the key just pressed confirming
-- itself or a different key cancelling it — the caller tells the two apart, this just
-- clears the state either way.
local function disarm()
    cancelArmTimer()
    streamdeck.disarm()
end

local function armIndex(index)
    streamdeck.arm(index)
    if broker then broker:refreshKeys() end
    cancelArmTimer()
    armTimer = hs.timer.doAfter(obj.armTimeout, function()
        armTimer = nil
        streamdeck.disarm()
        if broker then broker:refreshKeys() end
    end)
end

--- Dispatch for a press while the page is up. Every key on the deck arrives here, which
--- is what lets the page borrow keys other modules own.
---
--- Presses only. Acting on the release as well would run each action twice, and the
--- tap that opens the page is still down when it opens, so its release is the first
--- event the page ever sees.
local function pageKey(index, pressed)
    if not pressed then return end

    local entry = streamdeck.entries()[index]
    if not entry or entry.kind == "empty" then return end

    if entry.kind == "back" then
        obj:closePage()
        return
    end

    -- The key that is armed confirming itself is the one case that acts; every other
    -- press below this either cancels an arm or does its own thing outright.
    if streamdeck.armed() == index then
        disarm()
        fire(entry.action)
        obj:closePage()
        return
    end

    if streamdeck.armed() then disarm() end

    if entry.action.confirm then
        armIndex(index)
        armPageTimer()
    else
        fire(entry.action)
        obj:closePage()
    end
end

--- SystemState:openPage()
--- Method
--- Put the actions up across the deck. Needs setBroker().
---
--- Opened with nothing armed each time rather than however it was left, so that the
--- same press always reaches the same thing and a Restart left mid-confirm from last
--- time can never be confirmed by a press that was not aimed at it.
function obj:openPage()
    if not broker then
        hs.printf("[SystemState] no broker set; see SystemState:setBroker()")
        return self
    end

    cancelArmTimer()
    streamdeck.rewind()
    broker:holdKeys({paint = streamdeck.page, key = pageKey})
    armPageTimer()
    return self
end

--- SystemState:closePage()
--- Method
--- Take the page down and give the keys back to the modules underneath.
function obj:closePage()
    cancelPageTimer()
    cancelArmTimer()
    streamdeck.disarm()
    if broker then broker:releaseKeys() end
    return self
end

--- SystemState:pageOpen() -> boolean
--- Method
--- Whether the page currently has the deck.
function obj:pageOpen()
    return broker ~= nil and broker:keysHeld()
end

-- ---------------------------------------------------------------------------
-- Stream Deck surfaces
-- ---------------------------------------------------------------------------

--- SystemState:setBroker(streamDeckSpoon)
--- Method
--- Give the spoon the thing that arbitrates the deck's keys, so it can open the page.
---
--- Separate from setStreamDeckDevice() because the two are different claims. Drawing
--- the key needs a device and nothing more. A page is a claim on every key at once,
--- including keys other modules own and paint, and only the broker can hold those
--- still while it is up.
function obj:setBroker(streamDeckSpoon)
    broker = streamDeckSpoon
    return self
end

--- SystemState:setStreamDeckDevice(dev)
--- Method
--- Draw the key that opens the page on an already-discovered deck. Pass nil to detach.
---
--- There is deliberately no discovery here: hs.streamdeck.init() installs a single
--- process-wide callback, so a spoon that called it would silently displace whatever
--- called it before. Hand the device in from StreamDeck.spoon instead.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- SystemState:stopStreamDeck()
--- Method
--- Stop drawing on the Stream Deck, close the page and blank the key.
function obj:stopStreamDeck()
    self:closePage()
    streamdeck.stop()
    return self
end

return obj
