--- === InputLevel ===
---
--- Live microphone peak level and clipping on a Stream Deck Plus knob and the touch
--- strip segment above it. Turn the knob to change input gain; press it to mute.
---
--- hs.audiodevice exposes only the input *gain setting*, never the incoming signal,
--- so there is no way to see real clipping from Lua alone. The signal itself is read
--- by InputLevel.app, a small signed bundle beside this file that holds its own
--- microphone grant — Hammerspoon's Info.plist declares no
--- NSMicrophoneUsageDescription, so a request made as Hammerspoon itself would be
--- refused with no prompt. It taps AVAudioEngine's input node and writes the peak
--- dBFS of each ~100ms window to a file this spoon polls, but only while some other
--- process is actually using the input device — see helper/inputlevel.swift for the
--- gate that keeps this spoon from being the reason the mic shows as in use. See
--- NextEvent.spoon for the same signed-bundle constraint against the calendar
--- instead of the mic.
---
--- The spoon is assembled from two modules, wired together at the bottom of this file:
---
---  * `monitor.lua`    - the helper process, the poll loop, gain/mute, clip latching
---  * `streamdeck.lua` - the knob claim and the strip segment
---
--- Rebuild the helper with `helper/build.sh` after editing the Swift. Re-signing gives
--- the bundle a new identity, so the first run afterwards waits on a fresh permission
--- prompt.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "InputLevel"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- InputLevel.deck
--- Variable
--- The Stream Deck broker to claim the knob and strip segment from. Default nil,
--- meaning `spoon.StreamDeck`.
---
--- Set it before start() to use a different broker — anything answering addEncoder,
--- addStrip, paintStrip and blankStrip, and carrying SEGMENT_W and SEGMENT_H. Looked
--- up on use rather than captured at load time, so assigning it after hs.loadSpoon()
--- works.
obj.deck = nil

--- InputLevel.levelEncoder
--- Variable
--- Which knob shows the meter and adjusts gain, numbered from 1 at the left. Default
--- 2.
---
--- Knobs 1 and 3 (and the strip segments above them) belong to StreamDeckMedia's
--- volume and transport; this must not collide with either. Picks both the knob and
--- the strip segment directly above it, the same as StreamDeckMedia.volumeEncoder.
obj.levelEncoder = 2

--- InputLevel.pollInterval
--- Variable
--- Seconds between reads of the helper's output file. Default 0.1.
---
--- Runs the whole time the spoon is started, not just until a first reading arrives
--- — unlike NextEvent's poll, which stops once the calendar answer is in, this meter
--- has no "done".
obj.pollInterval = 0.1

--- InputLevel.staleAfter
--- Variable
--- Seconds since the helper's last reading before it is treated as not reporting —
--- still starting, waiting on the permission prompt, or dead. Default 1.0.
obj.staleAfter = 1.0

--- InputLevel.clipThresholdDb
--- Variable
--- Peak level in dBFS at or above which a window counts as clipping. Default -1.0,
--- the standard early-warning threshold — true digital clipping (0 dBFS) is later
--- than most people want to find out.
obj.clipThresholdDb = -1.0

--- InputLevel.clipHoldSeconds
--- Variable
--- How long the CLIP indicator stays lit after the last window that crossed
--- clipThresholdDb. Default 1.5.
---
--- A transient clip is exactly what a glance at the strip would otherwise miss: this
--- is the hold on a hardware peak meter's clip LED, done in Lua rather than in the
--- helper so the policy can change without a rebuild.
obj.clipHoldSeconds = 1.5

--- InputLevel.gainStep
--- Variable
--- Input gain percentage points per knob detent. Default 2.
obj.gainStep = 2

--- InputLevel.meterFloorDb
--- Variable
--- Bottom of the meter bar's scale, in dBFS. Default -48. 0 dBFS is always the top.
obj.meterFloorDb = -48

--- InputLevel.meterWarnDb
--- Variable
--- Peak level in dBFS at or above which the bar turns yellow rather than green.
--- Default -12. It turns red at clipThresholdDb.
obj.meterWarnDb = -12

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so there is one place —
-- here — where the dependency graph is visible and no module can be used before it has
-- its config. The config passed is this table itself, read live, so assigning to
-- `spoon.InputLevel.gainStep` and friends keeps working after start().
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path, which
-- has no pattern that would resolve a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

-- Resolved at each use rather than captured, so `deck` can be set after the spoon is
-- loaded and so the error lands on the first call that actually needed a broker
-- rather than at load time, where it would take the whole config down.
local function deck()
    local sd = obj.deck or spoon.StreamDeck
    if not sd then
        error("InputLevel needs a Stream Deck broker: hs.loadSpoon(\"StreamDeck\"), " ..
              "or set spoon.InputLevel.deck to one", 2)
    end
    return sd
end

local monitor = submodule("monitor.lua")(obj)
local streamdeck = submodule("streamdeck.lua")(obj, deck, monitor)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- InputLevel:state() -> table
--- Method
--- Snapshot of the current reading.
---
--- Returns a table with: peakDb (the latest window's peak in dBFS, or nil while
--- stale or not active), active (whether the helper's tap is currently engaged,
--- because some other process is using the mic, or nil while stale), clipped
--- (whether the hold from a recent crossing of clipThresholdDb is still in effect),
--- gain (0-100 input level, or nil), muted (boolean or nil), hasGainControl (whether
--- CoreAudio exposes a software input gain on this device at all), stale (no fresh
--- reading from the helper within staleAfter), and error (a string from the helper,
--- or nil).
function obj:state()
    return monitor.state()
end

--- InputLevel:subscribe(fn) -> token
--- Method
--- Call fn with a state snapshot on every poll tick. Returns a token for
--- unsubscribe().
function obj:subscribe(fn)
    return monitor.subscribe(fn)
end

--- InputLevel:unsubscribe(token)
--- Method
--- Remove a subscriber registered with subscribe().
function obj:unsubscribe(token)
    monitor.unsubscribe(token)
    return self
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- InputLevel:start()
--- Method
--- Launch the helper, claim the knob and strip segment, and begin polling.
function obj:start()
    monitor.start()
    streamdeck.start()
    return self
end

--- InputLevel:stop()
--- Method
--- Release the knob and strip segment, stop polling, and kill the helper.
function obj:stop()
    streamdeck.stop()
    monitor.stop()
    return self
end

return obj
