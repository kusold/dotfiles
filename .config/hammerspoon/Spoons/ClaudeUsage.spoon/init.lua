--- === ClaudeUsage ===
---
--- Claude Code session usage with an animated Clawd mascot, shown on a menubar
--- item and/or a Stream Deck key. Eyes change expression based on rate limit
--- utilization (anime-style).
---
--- start() only begins polling; each display surface is opted into separately
--- with startMenubar() and startStreamDeck().
---
--- The spoon is assembled from four modules, wired together at the bottom of this
--- file:
---
---  * `clawd.lua`      - the mascot pixel map and canvas drawing
---  * `monitor.lua`    - credentials, the polling loop, backoff, state snapshots
---  * `menubar.lua`    - the menubar item and its dropdown
---  * `streamdeck.lua` - the Stream Deck key
---
--- Both surfaces subscribe to the one monitor; neither fetches for itself.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ClaudeUsage"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- ClaudeUsage.refreshInterval
--- Variable
--- How often (in seconds) to poll for usage data. Default 180.
---
--- Claude Code hits this same endpoint with this same token for its own usage
--- display, so the quota is shared; polling aggressively here can starve it. The
--- five-hour window this reports moves slowly enough that minutes of latency are
--- not noticeable.
obj.refreshInterval = 180

--- ClaudeUsage.minRetryInterval
--- Variable
--- Floor (in seconds) for the wait after a rate-limited or failed request, and
--- the first step of the backoff ramp. Default 60.
---
--- The endpoint sends `Retry-After: 0`, so a literal reading of the header would
--- mean retrying immediately; this floor is what makes it safe to honour.
obj.minRetryInterval = 60

--- ClaudeUsage.maxRetryInterval
--- Variable
--- Ceiling (in seconds) on the self-imposed backoff ramp. Default 1800.
---
--- A longer explicit Retry-After from the server overrides this — the cap limits
--- how far our own guessing escalates, not how long the server may ask us to
--- wait. Observed recovery from a rate limit took roughly 15 minutes of near
--- idleness, so the ceiling is set above that.
obj.maxRetryInterval = 1800

--- ClaudeUsage.stateKey
--- Variable
--- hs.settings key under which state is persisted across reloads.
obj.stateKey = "ClaudeUsage.state"

--- ClaudeUsage.keychainService
--- Variable
--- macOS Keychain generic-password service holding Claude Code's OAuth blob.
--- This is where Claude Code stores credentials on macOS; credentialsPath is
--- only consulted when no such Keychain item can be read.
obj.keychainService = "Claude Code-credentials"

--- ClaudeUsage.credentialsPath
--- Variable
--- Fallback path to a Claude credentials file, for setups that keep one on disk
--- rather than in the Keychain.
obj.credentialsPath = os.getenv("HOME") .. "/.claude/.credentials.json"

--- ClaudeUsage.streamDeckButton
--- Variable
--- Which Stream Deck key (1-based) shows the usage. Default 1.
obj.streamDeckButton = 1

--- ClaudeUsage.usageURL
--- Variable
--- Opened when the Stream Deck key is pressed.
obj.usageURL = "https://claude.ai/settings/usage"

--- ClaudeUsage.manageButtonCallback
--- Variable
--- Whether to install hs.streamdeck:buttonCallback() on a deck handed to this spoon.
--- Default true.
---
--- That callback is per-device and reports every key on the deck, not just this
--- spoon's, so a config where something else also wants a key must set this false and
--- route its own claim on this key to openUsage(). Left true in that situation, this
--- spoon would answer for keys it knows nothing about and silently drop their presses.
obj.manageButtonCallback = true

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so there is one
-- place — here — where the dependency graph is visible, and no module can be used
-- before it has been given its config.
--
-- The config passed is this table itself, read live: assigning to
-- `spoon.ClaudeUsage.refreshInterval` before start(), or to `streamDeckButton`
-- at any time, keeps working as it did when every setting lived in one file.
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path,
-- which has no pattern that would resolve a second file inside the bundle.
--
-- resourcePath() resolves against the file its caller was loaded from, so this
-- helper only works while it lives alongside the modules it loads.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

local clawd = submodule("clawd.lua")
local monitor = submodule("monitor.lua")(obj, clawd)
local menubar = submodule("menubar.lua")(obj, monitor, clawd)
local streamdeck = submodule("streamdeck.lua")(obj, monitor, clawd)

-- ---------------------------------------------------------------------------
-- Usage state
-- ---------------------------------------------------------------------------

--- ClaudeUsage:state()
--- Method
--- Snapshot of the current usage state, for consumers other than the menubar.
---
--- Returns a table with: utilization (session percent or nil), level (1-5 eye
--- level), text (the display string), usageData (last decoded payload or nil),
--- fetchedAt (os.time of that payload), error (last error string or nil), retryIn
--- (seconds until the backoff gate opens, or nil), hasCredentials, and plan (the
--- subscription type, or nil).
function obj:state()
    return monitor.state()
end

--- ClaudeUsage:subscribe(fn)
--- Method
--- Register a function to be called with a state snapshot on every state change.
---
--- This is how a second display surface reuses the single poller instead of
--- fetching on its own: the API quota is shared with Claude Code itself, so a
--- second fetch loop would double the request rate against a limit that reports
--- no remaining-quota header. Returns a token for unsubscribe().
function obj:subscribe(fn)
    return monitor.subscribe(fn)
end

--- ClaudeUsage:unsubscribe(token)
--- Method
--- Remove a subscriber previously registered with subscribe().
function obj:unsubscribe(token)
    return monitor.unsubscribe(token)
end

--- ClaudeUsage:fetchUsage()
--- Method
--- Refresh now, unless a backoff is still in force — in which case this only
--- republishes the current state so countdowns move.
function obj:fetchUsage()
    monitor.fetchUsage()
end

--- ClaudeUsage:clearPersistedState()
--- Method
--- Forget the persisted reading and backoff deadline.
function obj:clearPersistedState()
    monitor.clearPersistedState()
    return self
end

-- ---------------------------------------------------------------------------
-- Menubar surface
-- ---------------------------------------------------------------------------

--- ClaudeUsage:startMenubar()
--- Method
--- Add the menubar item and mirror the usage onto it.
---
--- The item appears whether or not credentials have resolved yet — they are read
--- asynchronously, so until then its title reads "..." and its menu reports why.
--- Safe to call before or after start(); it paints from whatever the monitor has.
function obj:startMenubar()
    menubar.start()
    return self
end

--- ClaudeUsage:stopMenubar()
--- Method
--- Remove the menubar item and stop mirroring to it.
function obj:stopMenubar()
    menubar.stop()
    return self
end

-- ---------------------------------------------------------------------------
-- Stream Deck surface
-- ---------------------------------------------------------------------------

--- ClaudeUsage:openUsage()
--- Method
--- Open the usage page, which is what pressing the Stream Deck key does.
---
--- Exposed so that a config brokering key presses can wire a key to it without
--- reaching into the surface, having set manageButtonCallback false.
function obj:openUsage()
    hs.urlevent.openURL(self.usageURL)
    return self
end

--- ClaudeUsage:startStreamDeck()
--- Method
--- Claim a Stream Deck and mirror the usage onto one of its keys.
---
--- Note that hs.streamdeck.init() installs a single process-wide discovery
--- callback, so calling this hands Stream Deck discovery to this spoon; any other
--- Stream Deck code in the config must go through setStreamDeckDevice() instead.
--- Hammerspoon also claims the USB device exclusively, so the official Elgato
--- Stream Deck app cannot be running.
function obj:startStreamDeck()
    streamdeck.start()
    return self
end

--- ClaudeUsage:setStreamDeckDevice(dev)
--- Method
--- Use an already-discovered device instead of managing discovery here, for
--- configs that call hs.streamdeck.init() themselves. Pass nil to detach.
function obj:setStreamDeckDevice(dev)
    streamdeck.setDevice(dev)
    return self
end

--- ClaudeUsage:stopStreamDeck()
--- Method
--- Stop mirroring to the Stream Deck and blank the key.
function obj:stopStreamDeck()
    streamdeck.stop()
    return self
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- ClaudeUsage:start()
--- Method
--- Begin polling for usage.
---
--- This starts no display surface of its own: a poller with no subscribers is
--- what every surface shares, so both the menubar and the Stream Deck key are
--- claimed explicitly, by startMenubar() and startStreamDeck().
function obj:start()
    monitor.start()
    return self
end

--- ClaudeUsage:stop()
--- Method
--- Stop polling.
---
--- Each surface is torn down only by its own stopMenubar()/stopStreamDeck(), so
--- that start() and stop() round-trip without silently losing one. Surfaces left
--- up after this show their last reading and stay refreshable by hand, since
--- fetchUsage() does not need the timer.
function obj:stop()
    monitor.stop()
    return self
end

return obj
