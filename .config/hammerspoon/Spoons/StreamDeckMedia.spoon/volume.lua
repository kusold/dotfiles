--- === StreamDeckMedia.volume ===
---
--- Output volume on a Stream Deck Plus knob: turn it to change the level, press
--- it to toggle mute, and read the level back off the touch strip above it.
---
--- A deliberate turn moves in the system's quarter-sized increment and a spin in
--- its full one, so the same knob covers a nudge and a sweep without a modifier.
---
--- The knob posts the same media-key events the keyboard's volume keys post
--- rather than writing a level through CoreAudio. That is what earns the standard
--- macOS volume HUD and its feedback click: the system draws those for changes it
--- performs, and has no public interface for drawing them on request. Handing the
--- change over means the knob is the volume keys, so it follows the default output
--- device, the Sound settings, and the per-app routing without knowing about any
--- of them.

return function(cfg, deck, draw)

local M = {}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local watched = nil      -- the hs.audiodevice whose watcher we currently hold
local lastDetent = nil   -- secondsSinceEpoch of the previous turn
local lastUp = nil       -- direction of the previous turn
local run = 0            -- detents so far in the current unbroken run
local started = false

-- ---------------------------------------------------------------------------
-- Volume
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.volume.level() -> number, boolean, hs.audiodevice
--- Function
--- The default output device's level, mutedness and identity.
---
--- Level is nil for a device CoreAudio exposes no volume control on, which is
--- ordinary for HDMI and for outboard DACs that keep their own; mutedness is nil
--- on the same grounds and independently of the level.
function M.level()
    local d = hs.audiodevice.defaultOutputDevice()
    if not d then return nil, nil, nil end
    return d:outputVolume(), d:outputMuted(), d
end

-- The modifier macOS itself puts on the quarter-sized increment; not a setting,
-- because changing it does not make a different increment, it makes none.
local FINE_FLAGS = {shift = true, alt = true}

local function press(key, fine)
    -- A system key needs the pair: a down with no up leaves the key held, and the
    -- flags have to ride on both halves or the system reads a modifier release
    -- mid-press and falls back to the full increment.
    for _, isDown in ipairs({true, false}) do
        local e = hs.eventtap.event.newSystemKeyEvent(key, isDown)
        if fine then e:setFlags(FINE_FLAGS) end
        e:post()
    end
end

-- A spin is sustained motion, not one quick pair. Counting a run of close-spaced
-- detents rather than trusting a single gap is what lets spinGap be wide enough
-- to catch a real spin without stealing the fine increment from a hand turning
-- slowly, and what keeps one jittery pair from lurching to coarse. Reversing
-- starts the count over: a change of direction is a new gesture, and the detent
-- that changes your mind is exactly the one that should be small.
local function spinning(up)
    local now = hs.timer.secondsSinceEpoch()
    local gap = lastDetent and (now - lastDetent) or nil

    if up == lastUp and gap and gap <= cfg.volumeSpinGap then
        run = run + 1
    else
        run = 1
    end
    lastDetent, lastUp = now, up

    local coarse = run >= cfg.volumeSpinDetents
    if cfg.volumeDebug then
        hs.printf("[StreamDeckMedia] volume %-4s gap=%-7s run=%d -> %s",
                  up and "up" or "down",
                  gap and string.format("%.0fms", gap * 1000) or "first",
                  run, coarse and "coarse" or "fine")
    end
    return coarse
end

--- StreamDeckMedia.volume.nudge(up)
--- Function
--- Move the output level one detent in the given direction.
---
--- The increment is chosen from how fast the detents are arriving, not from a
--- setting: a deliberate turn gets the system's quarter-sized increment, and a
--- spin gets its full one. Nothing here decides what either is worth or where the
--- range ends — the system owns that, as it does unmuting on the way up. The strip
--- is deliberately not repainted here; the level has not changed yet when this
--- returns, and the device watcher repaints on the change itself.
function M.nudge(up)
    local coarse = spinning(up)
    for _ = 1, cfg.volumeStep do
        press(up and "SOUND_UP" or "SOUND_DOWN", not coarse)
    end
end

--- StreamDeckMedia.volume.toggleMute()
--- Function
--- Toggle mute, by the same key the keyboard's mute key sends.
---
--- Mute has its own HUD, and a device with no mute control of its own still gets
--- whatever macOS does for that key, which is more than this could work out.
function M.toggleMute()
    press("MUTE")
end

-- ---------------------------------------------------------------------------
-- Touch strip
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.volume.screenImage([level, muted]) -> hs.image
--- Function
--- The strip artwork for a level, defaulting to the current one.
---
--- Public so the readout can be previewed with no deck connected: hs.canvas has no
--- way to show what it drew other than handing back the image.
function M.screenImage(level, muted)
    local W, H = deck().SEGMENT_W, deck().SEGMENT_H
    if level == nil and muted == nil then
        level, muted = M.level()
    end
    local silent = muted or level == 0
    local shown = level and string.format("%d", math.floor(level + 0.5)) or "--"
    local fill = math.max(0, math.min(1, (level or 0) / 100))

    local elements = {
        draw.background(W, H),
        {
            type = "text",
            text = silent and "MUTED" or "VOLUME",
            frame = {x=0, y=8, w=W, h=18},
            textColor = silent and draw.OFF or draw.DIM,
            textSize = 14,
            textAlignment = "center",
            textFont = draw.TITLE_FONT,
        },
        {
            type = "text",
            text = shown,
            frame = {x=0, y=24, w=W, h=48},
            textColor = silent and draw.DIM or draw.FG,
            textSize = 42,
            textAlignment = "center",
            textFont = draw.TITLE_FONT,
        },
        {
            type = "rectangle",
            frame = {x=24, y=78, w=W-48, h=8},
            fillColor = draw.TRACK,
            action = "fill",
            roundedRectRadii = {xRadius=4, yRadius=4},
        },
    }

    if fill > 0 then
        table.insert(elements, {
            type = "rectangle",
            frame = {x=24, y=78, w=(W-48) * fill, h=8},
            fillColor = silent and draw.DIM or draw.BAR,
            action = "fill",
            roundedRectRadii = {xRadius=4, yRadius=4},
        })
    end

    return draw.render(W, H, elements)
end

--- StreamDeckMedia.volume.publish()
--- Function
--- Ask for a repaint of the strip from the current level.
---
--- Which may draw nothing: the StreamDeck broker owns the strip, and ignores this
--- while a full-width view holds it. That is deliberate — the level is read at paint
--- time, so whatever the view is covering is correct again the moment it lets go.
function M.publish()
    deck():paintStrip(cfg.volumeEncoder)
end

-- ---------------------------------------------------------------------------
-- Watchers
-- ---------------------------------------------------------------------------

-- Anything else on the machine can move the volume — the media keys, System
-- Settings, an app's own slider — and a readout that only tracked this knob would
-- sit there being confidently wrong. Watching the device closes that gap.
local function watch(d)
    if watched then
        pcall(function() watched:watcherStop() end)
        pcall(function() watched:watcherCallback(nil) end)
    end
    watched = d
    if not d then return end

    d:watcherCallback(function(_uid, event)
        if event == "vmvc" or event == "mute" then
            M.publish()
        end
    end)
    d:watcherStart()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.volume.start()
--- Function
--- Claim the knob and begin tracking the default output device.
---
--- The knob is claimed through the StreamDeck broker rather than by installing an
--- encoder callback here, because a deck carries one such callback covering every
--- knob: installing one here would be taking the other knobs' events hostage.
---
--- hs.audiodevice.watcher holds one process-wide callback, so this claims it for
--- the whole config; other code wanting default-device events has to hook in here.
function M.start()
    if started then return M end
    started = true
    local sd = deck()

    if cfg.volumeShowStrip then
        sd:addStrip(cfg.volumeEncoder, {paint = function() return M.screenImage() end})
    end

    sd:addEncoder(cfg.volumeEncoder, function(pressed, left, right)
        if left or right then
            -- Turns report `pressed` false and one direction true; presses report
            -- neither direction. See hs.streamdeck:encoderCallback().
            M.nudge(right)
        elseif pressed then
            M.toggleMute()
        end
    end)

    watch(hs.audiodevice.defaultOutputDevice())

    hs.audiodevice.watcher.setCallback(function(event)
        if event == "dOut" then
            watch(hs.audiodevice.defaultOutputDevice())
            M.publish()
        end
    end)
    hs.audiodevice.watcher.start()

    M.publish()
    return M
end

--- StreamDeckMedia.volume.stop()
--- Function
--- Release the knob and the watchers, and blank the strip segment.
function M.stop()
    if not started then return M end
    started = false
    local sd = deck()
    sd:addEncoder(cfg.volumeEncoder, nil)
    sd:addStrip(cfg.volumeEncoder, nil)
    sd:blankStrip(cfg.volumeEncoder)

    watch(nil)
    hs.audiodevice.watcher.stop()
    hs.audiodevice.watcher.setCallback(nil)
    return M
end

return M

end
