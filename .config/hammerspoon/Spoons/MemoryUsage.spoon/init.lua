--- === MemoryUsage ===
---
--- Memory in use, as a percentage over a rolling graph coloured by memory pressure, on
--- a Stream Deck key.
---
--- The spoon is assembled from two files, wired together at the bottom of this one:
---
---  * `monitor.lua`    - the sampler and its history
---  * `streamdeck.lua` - the Stream Deck key

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MemoryUsage"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- MemoryUsage.sampleInterval
--- Variable
--- How often (in seconds) to sample memory in use. Default 3.
---
--- Read by start(), so a change takes effect on the next start() rather than live.
obj.sampleInterval = 3

--- MemoryUsage.historyLength
--- Variable
--- How many samples the graph spans. Default 37.
---
--- The graph covers historyLength * sampleInterval seconds, and the bars share the
--- key's width between them, so a longer history means thinner bars.
obj.historyLength = 37

--- MemoryUsage.pressureColors
--- Variable
--- The colour for each memory pressure level, keyed "normal", "warn" and "critical".
---
--- Green, yellow and red by default, the way Activity Monitor colours its own pressure
--- graph. A sample whose pressure could not be read is drawn grey whatever this says.
obj.pressureColors = {
    normal   = {red=0.40, green=0.80, blue=0.45, alpha=1},
    warn     = {red=0.95, green=0.85, blue=0.30, alpha=1},
    critical = {red=0.90, green=0.25, blue=0.22, alpha=1},
}

--- MemoryUsage.activityMonitorBundleID
--- Variable
--- Bundle identifier of the app a press opens. Default "com.apple.ActivityMonitor".
obj.activityMonitorBundleID = "com.apple.ActivityMonitor"

--- MemoryUsage.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) shows memory in use. Default 7.
---
--- Only the drawing of the key is meant here; the press is claimed separately through
--- StreamDeck:addKey().
obj.streamDeckButton = 7

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, and is handed this table
-- as its config, read live. dofile rather than require for the reason NextEvent gives:
-- package.path has no pattern that resolves a second file inside the bundle.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local monitor = submodule("monitor.lua")(obj)
local streamdeck = submodule("streamdeck.lua")(obj, monitor)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- MemoryUsage:state() -> table
--- Method
--- Snapshot of memory in use.
---
--- Returns a table with: used and total (bytes, nil before the first sample), fraction
--- (used / total, 0-1), pressure ("normal", "warn", "critical", or nil when it could not
--- be read), history (recent samples, oldest first, each a table of fraction and
--- pressure) and error (the last usage sample's failure, or nil).
function obj:state()
    return monitor.state()
end

--- MemoryUsage:subscribe(fn) -> token
--- Method
--- Call fn with a state snapshot after every sample, for a surface of your own. Returns
--- a token for unsubscribe().
function obj:subscribe(fn)
    return monitor.subscribe(fn)
end

--- MemoryUsage:unsubscribe(token)
--- Method
--- Remove a subscriber registered with subscribe().
function obj:unsubscribe(token)
    monitor.unsubscribe(token)
    return self
end

-- ---------------------------------------------------------------------------
-- Stream Deck surface
-- ---------------------------------------------------------------------------

--- MemoryUsage:openActivityMonitor()
--- Method
--- Launch Activity Monitor, or bring it to the front if it is already running.
---
--- The spoon exposes the action and claims no key for it; which key presses this is a
--- decision about the whole deck. See StreamDeck:addKey().
function obj:openActivityMonitor()
    hs.application.launchOrFocusByBundleID(self.activityMonitorBundleID)
    return self
end

--- MemoryUsage:setStreamDeckDevice(dev)
--- Method
--- Mirror memory in use onto a key of an already-discovered deck. Pass nil to detach.
---
--- There is deliberately no discovery here, for the reason StreamDeck.spoon gives:
--- hs.streamdeck.init() installs a single process-wide callback.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- MemoryUsage:stopStreamDeck()
--- Method
--- Stop mirroring to the Stream Deck and blank the key.
function obj:stopStreamDeck()
    streamdeck.stop()
    return self
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- MemoryUsage:start()
--- Method
--- Begin sampling. The Stream Deck key is claimed by setStreamDeckDevice().
function obj:start()
    monitor.start()
    return self
end

--- MemoryUsage:stop()
--- Method
--- Stop sampling. A key left up keeps showing the last reading.
function obj:stop()
    monitor.stop()
    return self
end

return obj
