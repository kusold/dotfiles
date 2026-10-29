--- === Shortcuts ===
---
--- A Stream Deck key that opens a page of one-press actions across the deck; press one
--- to run it.
---
--- Unlike SystemState, this spoon knows none of its actions. Each is a function handed in
--- through Shortcuts.actions, so what goes on the page is decided in the config next to
--- whatever spoon does the work, and adding one never means editing this spoon.
---
--- Nothing here asks for confirmation: an action that needs a second press belongs on a
--- page that arms, the way SystemState's Restart does, not here.
---
--- The spoon is assembled from two files, wired together below:
---
---  * `streamdeck.lua` - the key that opens the page, and the page
---
--- There is no start(): nothing here polls or keeps state between presses. Give it a
--- device with setStreamDeckDevice(), the broker with setBroker(), and a key of its own
--- to be opened from.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Shortcuts"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- Shortcuts.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) opens the page. Default 7.
---
--- Only the drawing of the key is meant here; the press is claimed separately through
--- StreamDeck:addKey().
obj.streamDeckButton = 7

--- Shortcuts.buttonLabel / Shortcuts.buttonGlyph
--- Variable
--- The word and symbol on the key that opens the page. Default "Shortcuts" and "⚡".
obj.buttonLabel = "Shortcuts"
obj.buttonGlyph = "⚡"

--- Shortcuts.pageKeys
--- Variable
--- How many keys the page covers. Default 8, a Stream Deck Plus.
---
--- The last is always Back; what is left over is room for actions.
obj.pageKeys = 8

--- Shortcuts.pageTimeout
--- Variable
--- Seconds the page stays up with nothing pressed before closing itself. Default 15.
---
--- Worth having for the reason SystemState.pageTimeout gives: the page covers keys
--- belonging to other modules, and one left open takes them with it. Set to 0 to leave
--- it up until Back is pressed.
obj.pageTimeout = 15

--- Shortcuts.backLabel / Shortcuts.backGlyph
--- Variable
--- The key that closes the page without doing anything, last on it. Worded and drawn as
--- the other pages' Back keys are, so one page idiom covers them all.
obj.backLabel = "Back"
obj.backGlyph = "←"

--- Shortcuts.actions
--- Variable
--- The actions the page offers, in key order. Empty by default.
---
--- Each is {label, glyph, fn}: `label` and `glyph` are what the key shows, and `fn` is
--- called with no arguments when it is pressed. The page closes before `fn` runs, so an
--- action that raises an alert or a window is not drawn over by the page.
obj.actions = {}

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- The config passed is this table itself, read live, so assigning to
-- `spoon.Shortcuts.actions` keeps working after the spoon is loaded.
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which
-- has no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local streamdeck = submodule("streamdeck.lua")(obj)

local broker = nil
local pageTimer = nil

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

-- An action is someone else's code, so a failure in one is reported rather than allowed
-- to unwind through the broker's button dispatch, which every other key's press also
-- goes through.
local function fire(action)
    local ok, err = pcall(action.fn)
    if not ok then
        hs.printf("[Shortcuts] %q failed: %s", tostring(action.label), tostring(err))
    end
end

--- Dispatch for a press while the page is up. Every key on the deck arrives here, which
--- is what lets the page borrow keys other modules own.
---
--- Presses only, for the reason SystemState's pageKey() gives: the tap that opens the
--- page is still down when it opens, so its release is the first event the page sees.
local function pageKey(index, pressed)
    if not pressed then return end

    local entry = streamdeck.entries()[index]
    if not entry or entry.kind == "empty" then return end

    obj:closePage()
    if entry.kind == "action" then fire(entry.action) end
end

--- Shortcuts:openPage()
--- Method
--- Put the actions up across the deck. Needs setBroker().
function obj:openPage()
    if not broker then
        hs.printf("[Shortcuts] no broker set; see Shortcuts:setBroker()")
        return self
    end

    broker:holdKeys({paint = streamdeck.page, key = pageKey})
    armPageTimer()
    return self
end

--- Shortcuts:closePage()
--- Method
--- Take the page down and give the keys back to the modules underneath.
function obj:closePage()
    cancelPageTimer()
    if broker then broker:releaseKeys() end
    return self
end

--- Shortcuts:pageOpen() -> boolean
--- Method
--- Whether the page currently has the deck.
function obj:pageOpen()
    return broker ~= nil and broker:keysHeld()
end

-- ---------------------------------------------------------------------------
-- Stream Deck surfaces
-- ---------------------------------------------------------------------------

--- Shortcuts:setBroker(streamDeckSpoon)
--- Method
--- Give the spoon the thing that arbitrates the deck's keys, so it can open the page.
---
--- Separate from setStreamDeckDevice() for the reason SystemState:setBroker() gives:
--- drawing the key needs only a device, a page is a claim on every key at once.
function obj:setBroker(streamDeckSpoon)
    broker = streamDeckSpoon
    return self
end

--- Shortcuts:setStreamDeckDevice(dev)
--- Method
--- Draw the key that opens the page on an already-discovered deck. Pass nil to detach.
---
--- There is deliberately no discovery here, for the reason StreamDeck.spoon gives:
--- hs.streamdeck.init() installs a single process-wide callback.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- Shortcuts:stopStreamDeck()
--- Method
--- Stop drawing on the Stream Deck, close the page and blank the key.
function obj:stopStreamDeck()
    self:closePage()
    streamdeck.stop()
    return self
end

return obj
