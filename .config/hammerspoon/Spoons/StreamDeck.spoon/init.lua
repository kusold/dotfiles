--- === StreamDeck ===
---
--- Stream Deck discovery and arbitration: the one place in a config that owns the
--- device, and the broker every surface claims through.
---
--- hs.streamdeck.init() installs a single process-wide discovery callback, so a
--- second caller does not add a listener, it replaces the first — which is why
--- ClaudeUsage documents setStreamDeckDevice() as the way in for configs that run
--- their own discovery. Discovery happens here; every surface is handed the device
--- it finds and hands nothing back.
---
--- hs.streamdeck:buttonCallback(), hs.streamdeck:encoderCallback() and
--- hs.streamdeck:screenCallback() have the same shape one level down: a deck carries
--- one of each, covering every key, every knob and the whole touch strip, so none of
--- them can be bound a module at a time. This owns all three and dispatches by key, by
--- knob and by strip segment, which is what lets each of those be a module of its own.
---
--- Strip painting is owned here too, for a different reason: the strip is one
--- surface that several modules draw on, and a full-width view has to be able to
--- stop them drawing for as long as it is up. Modules hand over a painter and never
--- write to the device themselves, so holdStrip() can suspend the lot of them.
---
--- Key painting needs the same suspending for holdKeys(), but could not be moved the
--- same way: every surface here already paints its own key straight at the device, and
--- rewriting all of them to hand over a painter instead would be a change to each one
--- for a feature none of them use. So what addSurface() hands out is not the device but
--- a stand-in for it, forwarding every method untouched except the two that paint a
--- key. A surface still calls dev:setButtonImage() and cannot tell the difference; the
--- stand-in is what lets a page hold the deck without their cooperation.
---
--- This spoon knows nothing about what is drawn on the deck. It is deliberately
--- empty of policy so that unrelated surfaces — a media readout, a usage meter —
--- can share one device without either having to know the other exists.
---
--- The deck's backlight is the one exception, because it is not a fact about what is
--- drawn: sleep, the screensaver and the display going idle are not something any one
--- surface would know to react to, and every surface would otherwise have to. This
--- watches hs.caffeinate.watcher itself and turns the backlight off and back on with
--- StreamDeck:blank() / StreamDeck:unblank(), leaving every key, knob and strip claim
--- exactly as it was so nothing has to repaint when the lights come back on.
---
--- Hammerspoon claims the deck exclusively over USB, so Elgato's own Stream Deck
--- app must not be running for any of this to attach.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StreamDeck"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- StreamDeck.SEGMENTS
--- Constant
--- Touch strip segments on a Stream Deck Plus, one above each knob.
obj.SEGMENTS = 4

--- StreamDeck.SEGMENT_W
--- Constant
--- Width in pixels of one strip segment. The strip is SEGMENTS * this wide.
obj.SEGMENT_W = 200

--- StreamDeck.SEGMENT_H
--- Constant
--- Height in pixels of the touch strip.
obj.SEGMENT_H = 100

--- StreamDeck.touchDebug
--- Variable
--- Log every strip touch with its raw coordinates. Default false.
---
--- The coordinates hs.streamdeck reports are undocumented as to origin, and
--- segmentAt() reads them as pixels across the whole strip. This is how you check
--- that on a given deck without guessing.
obj.touchDebug = false

--- StreamDeck.brightness
--- Variable
--- Backlight percentage (0-100) the deck is restored to on unblank(). Default 100.
---
--- Read live, so assigning to it changes what the next unblank() restores to; it does
--- not by itself change the brightness of a deck that is currently lit.
obj.brightness = 100

local device = nil
local proxy = nil      -- the stand-in surfaces are handed in place of the device
local surfaces = {}
local keys = {}
local encoders = {}
local strips = {}      -- segment -> {paint = fn, touch = fn}
local hold = nil       -- {paint = fn, touch = fn} while a full-width view is up
local keyHold = nil    -- {paint = fn, key = fn} while a full-deck page is up
local lastPaint = {}   -- key -> {kind = "image"|"color", value = ...}, last painted
local heldPainted = {} -- key -> true, for every key the page has drawn on
local writeFailed = false
local discovering = false
local blanked = false
local sleepWatcher = nil

--- StreamDeck:addSurface(fn)
--- Method
--- Register a function called with the device on connect and nil on disconnect.
---
--- Registering after a device is already connected calls fn immediately, so
--- start() and addSurface() can be called in either order.
function obj:addSurface(fn)
    table.insert(surfaces, fn)
    if proxy then fn(proxy) end
    return self
end

--- StreamDeck:addEncoder(index, fn)
--- Method
--- Claim one knob, numbered from 1 at the left, and give up any earlier claim on
--- it. Pass nil for fn to release it.
---
--- fn is called as fn(pressed, left, right) for that knob only: a turn reports one
--- direction true and `pressed` false, and a press reports neither direction. See
--- hs.streamdeck:encoderCallback() for the callback this is dispatched from.
---
--- Dispatch is a lookup at event time, so claiming a knob before or after a deck
--- connects works the same and a claim survives a reconnect.
function obj:addEncoder(index, fn)
    if fn and encoders[index] then
        -- Benign when a module is re-claiming its own knob across a restart, and
        -- worth printing anyway: the other cause is two modules defaulting to the
        -- same knob, whose only other symptom is one of them never firing.
        hs.printf("[StreamDeck] knob %d claim replaced", index)
    end
    encoders[index] = fn
    return self
end

--- StreamDeck:addKey(index, fn)
--- Method
--- Claim one key, numbered from 1 at the top left, and give up any earlier claim on
--- it. Pass nil for fn to release it.
---
--- fn is called as fn(pressed) for that key only, with `pressed` true going down and
--- false coming back up; a handler that acts on both fires twice per tap. See
--- hs.streamdeck:buttonCallback() for the callback this is dispatched from.
---
--- Claiming a key does not claim the drawing of it. A surface paints its own key
--- through the handle it was given by addSurface(), because painting one key is not
--- exclusive the way the press callback is: two surfaces given the same key number
--- still paint over each other, and only the presses are reported as a collision.
---
--- What that handle does arbitrate is holdKeys(). Writes through it are recorded and
--- withheld while a page has the deck, and replayed when the page comes down.
---
--- Dispatch is a lookup at event time, so claiming a key before or after a deck
--- connects works the same and a claim survives a reconnect.
function obj:addKey(index, fn)
    if fn and keys[index] then
        -- Benign when a module is re-claiming its own key across a restart, and worth
        -- printing anyway: the other cause is two modules defaulting to the same key,
        -- whose only other symptom is one of them never firing.
        hs.printf("[StreamDeck] key %d claim replaced", index)
    end
    keys[index] = fn
    return self
end

--- StreamDeck:device() -> hs.streamdeck or nil
--- Method
--- The currently connected deck, for one-off pokes from the console.
function obj:device()
    return device
end

-- ---------------------------------------------------------------------------
-- Power state
-- ---------------------------------------------------------------------------

-- Applied on every write to the device's brightness, whether that write comes from
-- blank()/unblank() or from a reconnect that needs to be brought into line with
-- whichever of those the deck was last told to do.
local function applyBrightness()
    if not device then return end
    local ok, err = pcall(function() device:setBrightness(blanked and 0 or obj.brightness) end)
    if not ok then
        hs.printf("[StreamDeck] setBrightness failed: %s", tostring(err))
    end
end

--- StreamDeck:blank()
--- Method
--- Turn the deck's backlight off. Every key, knob and strip claim is left exactly as
--- it is underneath, so unblank() needs nothing from a surface to bring it back.
function obj:blank()
    if blanked then return self end
    blanked = true
    applyBrightness()
    return self
end

--- StreamDeck:unblank()
--- Method
--- Restore the deck's backlight to StreamDeck.brightness.
function obj:unblank()
    if not blanked then return self end
    blanked = false
    applyBrightness()
    return self
end

--- StreamDeck:blanked() -> boolean
--- Method
--- Whether the backlight is currently off.
function obj:blanked()
    return blanked
end

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------

-- Replay one recorded write at the device. Used to put a key back the way its surface
-- last had it once a page stops covering it.
local function replay(index, paint)
    if not (device and paint) then return end
    if paint.kind == "image" then
        device:setButtonImage(index, paint.value)
    else
        device:setButtonColor(index, paint.value)
    end
end

-- The stand-in handed to surfaces. Recording every key write is what lets releaseKeys()
-- restore the deck without a repaint hook on every surface: a page comes down and each
-- key under it is rewritten from what it last showed, whether or not the module that
-- drew it is still running or even still loaded.
local function makeProxy(dev)
    local p = {}

    function p:setButtonImage(index, image)
        lastPaint[index] = {kind = "image", value = image}
        -- Errors are deliberately not caught here. A surface that wraps its own write
        -- and drops its device handle when it throws is relying on an unplugged deck to
        -- report itself that way, and swallowing it would leave that surface holding a
        -- stale handle for good.
        if not keyHold then dev:setButtonImage(index, image) end
        return self
    end

    function p:setButtonColor(index, color)
        lastPaint[index] = {kind = "color", value = color}
        if not keyHold then dev:setButtonColor(index, color) end
        return self
    end

    -- Everything else is the device's own, bound to the device rather than to the
    -- stand-in: a surface calling dev:buttonCallback() has to reach hs.streamdeck with
    -- the arguments it expects, not with this table in front of them.
    return setmetatable(p, {
        __index = function(_, name)
            local value = dev[name]
            if type(value) ~= "function" then return value end
            return function(_self, ...) return value(dev, ...) end
        end,
        __tostring = function() return "StreamDeck stand-in for " .. tostring(dev) end,
    })
end

--- StreamDeck:holdKeys(surface)
--- Method
--- Take every key for a full-deck page, suspending the surfaces painting them.
---
--- surface.paint() returns a table of hs.image keyed by key number, so a page lays out
--- as many keys as it wants and leaves the rest alone. surface.key(index, pressed)
--- receives every key press anywhere on the deck while the page is up, ahead of the
--- addKey() claims, so a page can put something else on a key another module owns
--- without both of them answering for the press.
---
--- Taking a page while one is already up replaces it, which is what makes re-opening a
--- page idempotent rather than stacking a second one behind the first.
function obj:holdKeys(surface)
    keyHold = surface
    self:refreshKeys()
    return self
end

--- StreamDeck:refreshKeys()
--- Method
--- Repaint the page, for one whose keys change while it is up.
function obj:refreshKeys()
    if not (keyHold and keyHold.paint) then return self end
    local ok, images = pcall(keyHold.paint)
    if not ok then
        hs.printf("[StreamDeck] key page paint failed: %s", tostring(images))
        return self
    end
    for index, image in pairs(images or {}) do
        -- Recorded before the write rather than after it, so a key the page drew on is
        -- still restored on the way out when the write itself failed.
        heldPainted[index] = true
        if device then
            local wrote, err = pcall(function() device:setButtonImage(index, image) end)
            if not wrote then
                hs.printf("[StreamDeck] key %d page write failed: %s", index, tostring(err))
            end
        end
    end
    return self
end

--- StreamDeck:releaseKeys()
--- Method
--- Give the deck back to the surfaces and put every key the page covered back.
function obj:releaseKeys()
    if not keyHold then return self end
    keyHold = nil

    for index in pairs(heldPainted) do
        if lastPaint[index] then
            local ok, err = pcall(replay, index, lastPaint[index])
            if not ok then
                hs.printf("[StreamDeck] key %d restore failed: %s", index, tostring(err))
            end
        elseif device then
            -- A key no surface has ever painted has nothing to go back to, so it goes
            -- back to black rather than keeping the page's icon after the page is gone.
            pcall(function()
                device:setButtonColor(index, {red = 0, green = 0, blue = 0, alpha = 1})
            end)
        end
    end
    heldPainted = {}
    return self
end

--- StreamDeck:keysHeld() -> boolean
--- Method
--- Whether a full-deck page currently has the keys.
function obj:keysHeld()
    return keyHold ~= nil
end

-- ---------------------------------------------------------------------------
-- Touch strip
-- ---------------------------------------------------------------------------

local function write(segment, image)
    if not (device and image) then return end

    -- A write to a deck that has been unplugged throws. Discovery is the authority
    -- on the device going away and will say so in a moment; all this has to do is
    -- not throw in the meantime, and not log the same thing sixty times while a
    -- repainting view waits for that.
    local ok, err = pcall(function() device:setScreenImage(segment, image) end)
    if ok then
        writeFailed = false
    elseif not writeFailed then
        writeFailed = true
        hs.printf("[StreamDeck] strip write failed: %s", tostring(err))
    end
end

--- StreamDeck:segmentAt(x) -> number
--- Method
--- Which strip segment a touch at x belongs to, clamped into range.
function obj:segmentAt(x)
    local segment = math.floor((x or 0) / self.SEGMENT_W) + 1
    return math.max(1, math.min(self.SEGMENTS, segment))
end

--- StreamDeck:addStrip(segment, surface)
--- Method
--- Claim one strip segment. Pass nil for surface to release it.
---
--- surface.paint() returns the hs.image for the segment and is called whenever it
--- needs redrawing — on connect, on request, and after a full-width view releases
--- the strip. surface.touch(kind, x, y, endX, endY) is optional and receives touches
--- landing in this segment, with x made relative to the segment's left edge; kind is
--- "shortPress", "longPress" or "swipe" per hs.streamdeck:screenCallback().
function obj:addStrip(segment, surface)
    strips[segment] = surface
    if surface then self:paintStrip(segment) end
    return self
end

--- StreamDeck:paintStrip([segment])
--- Method
--- Repaint one segment, or every claimed segment. A no-op while the strip is held.
---
--- Silently doing nothing under a full-width view is the point: it means a module
--- can repaint on its own schedule without knowing whether something else has the
--- strip, and the view cannot be scribbled over by a volume change.
function obj:paintStrip(segment)
    if hold then return self end
    for index, surface in pairs(strips) do
        if (segment == nil or index == segment) and surface.paint then
            local ok, image = pcall(surface.paint)
            if ok then
                write(index, image)
            else
                hs.printf("[StreamDeck] strip %d paint failed: %s", index, tostring(image))
            end
        end
    end
    return self
end

--- StreamDeck:blankStrip(segment)
--- Method
--- Paint one segment black, for a module releasing it.
function obj:blankStrip(segment)
    local c = hs.canvas.new({x = 0, y = 0, w = self.SEGMENT_W, h = self.SEGMENT_H})
    c:appendElements({{
        type = "rectangle",
        frame = {x = 0, y = 0, w = self.SEGMENT_W, h = self.SEGMENT_H},
        fillColor = {red = 0, green = 0, blue = 0, alpha = 1},
        action = "fill",
    }})
    write(segment, c:imageFromCanvas())
    c:delete()
    return self
end

--- StreamDeck:holdStrip(surface)
--- Method
--- Take the whole strip for a full-width view, suspending every segment claim.
---
--- surface.paint() returns a table of images keyed by segment number, so a view can
--- lay itself out across the whole strip and hand back the slices. surface.touch
--- receives every touch anywhere on the strip while the hold lasts, with x left
--- absolute — a view spanning the strip wants to know where on it you touched.
---
--- Taking a hold that is already held replaces it, which is what makes a re-tap
--- while a view is up idempotent rather than a second view fighting the first.
function obj:holdStrip(surface)
    hold = surface
    self:refreshHold()
    return self
end

--- StreamDeck:refreshHold()
--- Method
--- Repaint the full-width view, for a view animating something like a progress bar.
function obj:refreshHold()
    if not hold or not hold.paint then return self end
    local ok, images = pcall(hold.paint)
    if not ok then
        hs.printf("[StreamDeck] held strip paint failed: %s", tostring(images))
        return self
    end
    for segment, image in pairs(images or {}) do
        write(segment, image)
    end
    return self
end

--- StreamDeck:releaseStrip()
--- Method
--- Give the strip back to the segment claims and repaint them.
function obj:releaseStrip()
    if not hold then return self end
    hold = nil
    self:paintStrip()
    return self
end

--- StreamDeck:stripHeld() -> boolean
--- Method
--- Whether a full-width view currently has the strip.
function obj:stripHeld()
    return hold ~= nil
end

local function dispatchTouch(_dev, kind, x, y, endX, endY)
    if obj.touchDebug then
        hs.printf("[StreamDeck] touch %s x=%s y=%s endX=%s endY=%s -> segment %d",
                  tostring(kind), tostring(x), tostring(y),
                  tostring(endX), tostring(endY), obj:segmentAt(x))
    end

    -- A held view gets everything, and gets it before any segment does: that is what
    -- makes "tap anywhere to dismiss" possible without every segment cooperating.
    if hold then
        if hold.touch then
            local ok, err = pcall(hold.touch, kind, x, y, endX, endY)
            if not ok then hs.printf("[StreamDeck] held strip touch failed: %s", tostring(err)) end
        end
        return
    end

    local segment = obj:segmentAt(x)
    local surface = strips[segment]
    if not (surface and surface.touch) then return end

    local ok, err = pcall(surface.touch, kind, x - (segment - 1) * obj.SEGMENT_W, y, endX, endY)
    if not ok then
        hs.printf("[StreamDeck] strip %d touch failed: %s", segment, tostring(err))
    end
end

local function dispatchKeys(_dev, index, pressed)
    -- A page gets every key and gets it instead of the claim underneath, the way a held
    -- strip gets every touch. Both halves matter: the page hears keys nothing has
    -- claimed, and the module whose key the page is borrowing does not hear it.
    if keyHold then
        if keyHold.key then
            local ok, err = pcall(keyHold.key, index, pressed)
            if not ok then
                hs.printf("[StreamDeck] key %d page press failed: %s", index, tostring(err))
            end
        end
        return
    end

    local fn = keys[index]
    if not fn then return end

    -- A key handler throwing must not take the callback down with it: there is only
    -- one, and every other key on the deck is behind it.
    local ok, err = pcall(fn, pressed)
    if not ok then
        hs.printf("[StreamDeck] key %d failed: %s", index, tostring(err))
    end
end

local function dispatchEncoders(_dev, index, pressed, left, right)
    local fn = encoders[index]
    if not fn then return end

    -- A knob handler throwing must not take the callback down with it: there is
    -- only one, and the other knobs are behind it.
    local ok, err = pcall(fn, pressed, left, right)
    if not ok then
        hs.printf("[StreamDeck] knob %d failed: %s", index, tostring(err))
    end
end

local function publish(dev)
    device = dev
    writeFailed = false
    proxy = dev and makeProxy(dev) or nil

    -- A page cannot outlive the deck it was drawn on, and neither can the record of what
    -- was under it: every surface repaints itself on the way back in, so the record
    -- refills from the reconnect rather than from anything kept across it.
    if not dev then
        keyHold = nil
        heldPainted = {}
        lastPaint = {}
    end

    if dev then
        -- Claims live in `keys`, `encoders` and `strips`, not in these callbacks, so
        -- they are installed once per connect and never rewritten as claims come and go.
        dev:buttonCallback(dispatchKeys)
        dev:encoderCallback(dispatchEncoders)
        dev:screenCallback(dispatchTouch)

        -- A deck that (re)connects while blanked has to come up dark, not at whatever
        -- brightness it powered on with — the sleep it is still inside of did not end
        -- just because the USB link did.
        applyBrightness()
    end
    for _, fn in ipairs(surfaces) do
        -- One surface throwing must not cost the others their notification, and
        -- least of all on the disconnect pass, where the cost is a stale handle.
        local ok, err = pcall(fn, proxy)
        if not ok then
            hs.printf("[StreamDeck] surface failed: %s", tostring(err))
        end
    end

    -- Strip claims are painted after the surfaces, so a module that both holds a
    -- claim and does its own setup on connect is set up before it is asked to draw.
    if dev then
        if hold then obj:refreshHold() else obj:paintStrip() end
    end
end

--- StreamDeck:start()
--- Method
--- Begin discovery and bind whatever deck is or becomes connected. Calling it again
--- does nothing.
---
--- Idempotent because the alternative is a segfault, not a wasted call:
--- hs.streamdeck.init() re-runs IOKit's initial device enumeration, and doing that
--- with a deck already attached takes Hammerspoon down inside libstreamdeck's
--- HIDconnect — a crash of the whole app, from Lua, with no error to catch. A second
--- call has nothing to add anyway, since discovery already reports every deck.
---
--- The guard is per Lua state, which is the right scope: hs.reload() builds a new
--- one and tears the extension down with the old, so the call after a reload is both
--- necessary and safe.
function obj:start()
    if discovering then return self end
    discovering = true

    hs.streamdeck.init(function(connected, dev)
        if connected then
            publish(dev)
        elseif device and dev == device then
            publish(nil)
        end
    end)

    -- Three independent ways the screen can go dark, each with its own pair of
    -- events: the display idling out (screensDidSleep/Wake) while the system stays
    -- up, the screensaver (screensaverDidStart/Stop) over an unlocked session, and
    -- the system itself sleeping (systemWillSleep/DidWake). blank()/unblank() are
    -- idempotent, so it does not matter that a real sleep fires more than one of
    -- these in either direction.
    local W = hs.caffeinate.watcher
    sleepWatcher = W.new(function(event)
        if event == W.screensDidSleep or event == W.screensaverDidStart or event == W.systemWillSleep then
            obj:blank()
        elseif event == W.screensDidWake or event == W.screensaverDidStop or event == W.systemDidWake then
            obj:unblank()
        end
    end)
    sleepWatcher:start()

    return self
end

return obj
