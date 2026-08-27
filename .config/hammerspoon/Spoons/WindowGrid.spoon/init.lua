--- === WindowGrid ===
---
--- Window arranging on a Stream Deck key: press it and the deck turns into the layouts,
--- press one of those and the focused window goes there.
---
--- The window acted on is whichever one had focus when the key was pressed, and a deck
--- press does not take focus away from it — see WindowGrid.layout. So the page is used
--- while looking at the window it is about, which is what the whole shape here follows
--- from: the page stays up after a press rather than closing on one, because arranging a
--- window is a thing done in two or three goes — onto this screen, then a half of it,
--- then a third when the half turns out to be wrong — and a page that closed each time
--- would have to be reopened between them.
---
--- One key on the page moves the window to the display the pointer is on. The rest are
--- shapes: halves, thirds and quarters of the screen it is already on. They are paged
--- rather than fitted to the deck, so the list can be as long as it is useful.
---
--- The spoon is assembled from three files, wired together below:
---
---  * `layout.lua`     - moving the window, and the only file that knows hs.window
---  * `diagram.lua`    - a display with a window on it, as canvas elements
---  * `streamdeck.lua` - the key that opens the page, and the page
---
--- There is no start(): nothing here polls and nothing here holds state between presses.
--- The page is drawn at the moment it is opened, so it is never stale, and the key that
--- opens it says the same thing forever. Give it a device with setStreamDeckDevice(), the
--- broker with setBroker(), and a key of its own to be opened from.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WindowGrid"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- WindowGrid.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) opens the page. Default 5.
---
--- Only the drawing of the key is meant here. Painting one key is not brokered, so two
--- surfaces given the same number paint over each other in whatever order they publish;
--- it is StreamDeck:addKey() that reports a collision, and only for presses.
obj.streamDeckButton = 5

--- WindowGrid.buttonLabel
--- Variable
--- The word on the key that opens the page. Default "Arrange".
obj.buttonLabel = "Arrange"

--- WindowGrid.pageKeys
--- Variable
--- How many keys the page covers. Default 8, a Stream Deck Plus.
---
--- The last is Back and, when the layouts do not fit on one page, the one before it is
--- More. What is left over is how many layouts a page holds.
obj.pageKeys = 8

--- WindowGrid.pageTimeout
--- Variable
--- Seconds the page stays up with nothing pressed before closing itself. Default 20.
---
--- The countdown restarts on every press, so it measures being walked away from rather
--- than being used. It is worth having because the page covers keys belonging to other
--- modules, and one left open takes the countdown, the calendar and the usage meter with
--- it. Set to 0 to leave it up until Back is pressed.
obj.pageTimeout = 20

--- WindowGrid.animationDuration
--- Variable
--- Seconds a window takes to travel to where it was sent. Default 0.
---
--- Zero, rather than hs.window.animationDuration's own default, because these moves are
--- made in threes and fours: an animation that reads as considered on a single move is a
--- queue to watch through when the next press comes before it has landed.
obj.animationDuration = 0

--- WindowGrid.fullScreenDelay
--- Variable
--- Seconds to let a window leave macOS's full screen before placing it. Default 1.
---
--- Long enough for the space animation, which cannot be waited on properly: a frame set
--- while it is still running is discarded silently. Raise it if placing a full-screen
--- window leaves it full-screen-sized instead of where it was sent.
obj.fullScreenDelay = 1

--- WindowGrid.alerts
--- Variable
--- Whether a press that could not be carried out says so on screen. Default true.
---
--- The console line is printed either way. This is about the difference being visible
--- from where the deck is, since every failure looks the same from there: a key that
--- lights and a window that does not move.
obj.alerts = true

--- WindowGrid.alertDuration
--- Variable
--- Seconds such an alert stays up. Default 1.2.
obj.alertDuration = 1.2

--- WindowGrid.screenLabel
--- Variable
--- The word on the key that moves the window to the pointer's display. Default "Screen".
obj.screenLabel = "Screen"

--- WindowGrid.moreLabel / WindowGrid.moreGlyph
--- Variable
--- The key that turns to the next page of layouts, second from last when there is one.
obj.moreLabel = "More"
obj.moreGlyph = "→"

--- WindowGrid.backLabel / WindowGrid.backGlyph
--- Variable
--- The key that closes the page, last on it. Worded and drawn as SlackStatus's own Back
--- key is, so that one page idiom covers both.
obj.backLabel = "Back"
obj.backGlyph = "←"

--- WindowGrid.layouts
--- Variable
--- The shapes the page offers, in key order.
---
--- Each is {label, unit}: `unit` is the part of the screen the window is to fill, as
--- {x, y, w, h} in fractions of hs.screen:frame(), and `label` is the name under the
--- picture of it. Any rectangle is expressible, so a grid finer than this one is a matter
--- of adding entries rather than of code.
---
--- The order is what decides which key each lands on, and it is chosen for where they
--- land rather than for how they group: the pointer key takes the first slot, so the L/R
--- splits fill out the rest of the first page, and the four quarters are separated by the
--- T/B halves so that they come out as a square of four keys on the second rather than as
--- a row of four. See WindowGrid.streamdeck.keys() for how the slots are cut.
obj.layouts = {
    {label = "Full",   unit = {x = 0,     y = 0,   w = 1,     h = 1}},
    {label = "L 1/2",  unit = {x = 0,     y = 0,   w = 1 / 2, h = 1}},
    {label = "R 1/2",  unit = {x = 1 / 2, y = 0,   w = 1 / 2, h = 1}},
    {label = "L 2/3",  unit = {x = 0,     y = 0,   w = 2 / 3, h = 1}},
    {label = "R 1/3",  unit = {x = 2 / 3, y = 0,   w = 1 / 3, h = 1}},

    {label = "TL 1/4", unit = {x = 0,     y = 0,   w = 1 / 2, h = 1 / 2}},
    {label = "TR 1/4", unit = {x = 1 / 2, y = 0,   w = 1 / 2, h = 1 / 2}},
    {label = "T 1/2",  unit = {x = 0,     y = 0,   w = 1,     h = 1 / 2}},
    {label = "B 1/2",  unit = {x = 0,     y = 1 / 2, w = 1,   h = 1 / 2}},
    {label = "BL 1/4", unit = {x = 0,     y = 1 / 2, w = 1 / 2, h = 1 / 2}},
    {label = "BR 1/4", unit = {x = 1 / 2, y = 1 / 2, w = 1 / 2, h = 1 / 2}},
}

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so the dependency graph is
-- visible in one place and no module can be used before it has its config. The config
-- passed is this table itself, read live, so assigning to `spoon.WindowGrid.layouts`
-- keeps working after the spoon is loaded.
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which has
-- no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local layout = submodule("layout.lua")(obj)
local diagram = submodule("diagram.lua")
local streamdeck = submodule("streamdeck.lua")(obj, layout, diagram)

local broker = nil
local pageTimer = nil

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

--- WindowGrid:moveToPointerScreen()
--- Method
--- Move the focused window to the display the pointer is on.
function obj:moveToPointerScreen()
    layout.toPointerScreen()
    return self
end

--- WindowGrid:moveToUnit(unit)
--- Method
--- Put the focused window on the fraction of its screen given by an {x, y, w, h} in
--- screen fractions, whether or not the page is open.
function obj:moveToUnit(unit)
    layout.toUnit(unit)
    return self
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function cancelPageTimer()
    if pageTimer then pageTimer:stop(); pageTimer = nil end
end

-- Restarted rather than left running on every press, so the timeout measures the page
-- being abandoned rather than the time since it opened. Without this a run of presses
-- would be cut off mid-way by a countdown that started before the first of them.
local function armPageTimer()
    cancelPageTimer()
    if obj.pageTimeout > 0 then
        pageTimer = hs.timer.doAfter(obj.pageTimeout, function()
            pageTimer = nil
            obj:closePage()
        end)
    end
end

--- Dispatch for a press while the page is up. Every key on the deck arrives here, which
--- is what lets the page borrow keys other modules own.
---
--- Presses only. Acting on the release as well would run each layout twice, and the tap
--- that opens the page is still down when it opens, so its release is the first event the
--- page ever sees.
local function pageKey(index, pressed)
    if not pressed then return end

    local entry = streamdeck.keys()[index]
    if not entry or entry.kind == "empty" then return end

    if entry.kind == "back" then
        obj:closePage()
        return
    end

    if entry.kind == "more" then
        streamdeck.nextPage()
        broker:refreshKeys()
    elseif entry.kind == "screen" then
        layout.toPointerScreen()
    else
        layout.toUnit(entry.unit)
    end

    -- The page is left up: see the note at the top of this file for why arranging a
    -- window is not one press.
    armPageTimer()
end

--- WindowGrid:openPage()
--- Method
--- Put the layouts up across the deck. Needs setBroker().
---
--- Opened at the first page each time rather than where it was left, so that the same
--- press always reaches the same layout and the deck is not remembering something the
--- person pressing it has forgotten.
function obj:openPage()
    if not broker then
        hs.printf("[WindowGrid] no broker set; see WindowGrid:setBroker()")
        return self
    end

    streamdeck.rewind()
    broker:holdKeys({paint = streamdeck.page, key = pageKey})
    armPageTimer()
    return self
end

--- WindowGrid:closePage()
--- Method
--- Take the page down and give the keys back to the modules underneath.
function obj:closePage()
    cancelPageTimer()
    if broker then broker:releaseKeys() end
    return self
end

--- WindowGrid:pageOpen() -> boolean
--- Method
--- Whether the layouts currently have the deck.
function obj:pageOpen()
    return broker ~= nil and broker:keysHeld()
end

-- ---------------------------------------------------------------------------
-- Stream Deck surfaces
-- ---------------------------------------------------------------------------

--- WindowGrid:setBroker(streamDeckSpoon)
--- Method
--- Give the spoon the thing that arbitrates the deck's keys, so it can open the page.
---
--- Separate from setStreamDeckDevice() because the two are different claims. Drawing the
--- key needs a device and nothing more. A page is a claim on every key at once, including
--- keys other modules own and paint, and only the broker can hold those still while it is
--- up.
function obj:setBroker(streamDeckSpoon)
    broker = streamDeckSpoon
    return self
end

--- WindowGrid:setStreamDeckDevice(dev)
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

--- WindowGrid:stopStreamDeck()
--- Method
--- Stop drawing on the Stream Deck, close the page and blank the key.
function obj:stopStreamDeck()
    self:closePage()
    streamdeck.stop()
    return self
end

return obj
