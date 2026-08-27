--- === StreamDeckMedia ===
---
--- Volume and media transport on two Stream Deck Plus knobs, with the touch strip
--- above them saying what each knob does and where it stands.
---
--- Turn the volume knob to change the level and press it to mute; turn the media
--- knob to skip tracks and press it to play or pause. The segment above the volume
--- knob shows the level; the one above the media knob shows previous, play/pause and
--- next, and tapping it opens a full-width view of the track — artwork, title,
--- artist, album and progress — across the whole strip.
---
--- Neither knob drives a particular app. Both post the same media-key events the
--- keyboard's own volume and transport keys post, so they inherit the system's
--- answers to "which output device" and "which player", and they get the standard
--- macOS HUDs for free. The readout comes from the same now-playing session those
--- keys talk to, so the knobs and the strip cannot disagree about what they mean.
---
--- The spoon is assembled from four modules, wired together at the bottom of this
--- file:
---
---  * `draw.lua`       - the palette, the fonts and the canvas work both knobs share
---  * `nowplaying.lua` - the now-playing session: polling, snapshots, artwork
---  * `volume.lua`     - the volume knob and its strip segment
---  * `media.lua`      - the transport knob, its strip segment and the full-width view
---
--- It does not own the Stream Deck. Discovery, the one encoder callback, the one
--- screen callback and arbitration of the strip are all process-wide or per-device
--- singletons, so they belong to a broker that nothing else on the deck has to know
--- about — the StreamDeck spoon. This claims two knobs and two strip segments from
--- that broker and touches the device no other way, which is what lets an unrelated
--- surface hold a key on the same deck.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "StreamDeckMedia"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- StreamDeckMedia.deck
--- Variable
--- The Stream Deck broker to claim knobs and strip segments from. Default nil,
--- meaning `spoon.StreamDeck`.
---
--- Set it before start() to use a different broker — anything answering addEncoder,
--- addStrip, paintStrip, blankStrip, holdStrip, refreshHold, releaseStrip and
--- stripHeld, and carrying SEGMENTS, SEGMENT_W and SEGMENT_H. It is looked up on use
--- rather than captured at load time, so assigning it after hs.loadSpoon() works;
--- changing it under running surfaces is not supported, since the claims they made
--- stay on the broker they were made against.
obj.deck = nil

--- StreamDeckMedia.volumeEncoder
--- Variable
--- Which knob drives the volume, numbered from 1 at the left. Default 1.
---
--- hs.streamdeck:setScreenImage() indexes touch strip segments with the same
--- numbering hs.streamdeck:encoderCallback() reports knobs in, so this one value
--- picks both the knob and the strip segment directly above it.
---
--- It must not collide with mediaEncoder — the broker logs it if it does, and the
--- loser of the collision goes silent.
obj.volumeEncoder = 1

--- StreamDeckMedia.volumeStep
--- Variable
--- Volume-key presses per detent, whichever increment is in play. Default 1.
obj.volumeStep = 1

--- StreamDeckMedia.volumeSpinGap
--- Variable
--- Seconds between detents at or under which one follows the other closely enough
--- to count toward a spin. Default 0.15.
---
--- Generous on purpose: it is volumeSpinDetents, not this, that decides how eager
--- the coarse increment is, and a gap this wide only ever matters to someone
--- already turning the knob continuously.
obj.volumeSpinGap = 0.15

--- StreamDeckMedia.volumeSpinDetents
--- Variable
--- Detents inside volumeSpinGap of each other before the coarse increment takes
--- over. Default 3, so a spin opens fine and gets out of its own way.
---
--- Set to 1 for coarse from the first detent of a spin, or high enough that it
--- cannot be reached to keep every detent fine.
obj.volumeSpinDetents = 3

--- StreamDeckMedia.volumeShowStrip
--- Variable
--- Mirror the level onto the touch strip segment above the volume knob. Default true.
obj.volumeShowStrip = true

--- StreamDeckMedia.volumeDebug
--- Variable
--- Log each volume detent's gap, run length and chosen increment. Default false.
---
--- Here because volumeSpinGap and volumeSpinDetents are claims about a particular
--- hand on a particular knob, and guessing at them once already produced a knob that
--- silently never left its fine increment.
obj.volumeDebug = false

--- StreamDeckMedia.mediaEncoder
--- Variable
--- Which knob drives the transport, numbered from 1 at the left. Default 3.
---
--- Picks both the knob and the strip segment above it, as volumeEncoder does, and
--- must not collide with it.
obj.mediaEncoder = 3

--- StreamDeckMedia.mediaCooldown
--- Variable
--- Seconds a skip suppresses further skips in the same direction. Default 0.3.
---
--- Sets the ceiling on how fast a held turn walks through tracks. Lower it for a
--- faster walk; raise it towards a second if a single flick still overshoots.
obj.mediaCooldown = 0.3

--- StreamDeckMedia.mediaShowStrip
--- Variable
--- Show the transport controls on the touch strip segment above the media knob.
--- Default true.
---
--- The tap that opens the full-width view lands on that segment, so turning this off
--- also takes away the way in to the view; showView() still opens it by hand.
obj.mediaShowStrip = true

--- StreamDeckMedia.mediaDebug
--- Variable
--- Log each transport detent and whether it skipped or was swallowed. Default false.
---
--- Here for the same reason volumeDebug is: mediaCooldown is a claim about a
--- particular hand on a particular knob, and the only way to see the swallowed
--- detents is to print them.
obj.mediaDebug = false

--- StreamDeckMedia.viewSeconds
--- Variable
--- Seconds before the full-width view releases the strip on its own, or nil to leave
--- it up until it is tapped again. Default nil.
---
--- Sticky by default, which is what makes the view something you can look back at
--- rather than something you have to catch. The cost is that it covers the volume
--- readout until dismissed: the knob and the keys still change the volume and macOS
--- still draws its own HUD, there is just no strip readout behind the view. Set this
--- to a number to get a backstop for walking away from it instead.
obj.viewSeconds = nil

--- StreamDeckMedia.viewRefresh
--- Variable
--- Seconds between repaints of the full-width view. Default 0.5.
---
--- Only the progress bar and clock move, so this costs nothing while the view is
--- down and nothing while it is paused — which matters now that it can stay up
--- indefinitely. It repaints from a projected position rather than a fresh poll —
--- see StreamDeckMedia:position().
obj.viewRefresh = 0.5

--- StreamDeckMedia.pollInterval
--- Variable
--- Seconds between now-playing polls while something is playing. Default 2.
---
--- A poll costs one perl process, about 35ms of CPU. There is a notification API in
--- MediaRemote that would replace polling with a stream, at the cost of a
--- long-running helper process to hold the subscription; polling this cheaply is
--- not worth that yet.
obj.pollInterval = 2

--- StreamDeckMedia.idlePollInterval
--- Variable
--- Seconds between now-playing polls while nothing is playing. Default 6.
---
--- Slower because the only thing a poll can discover while idle is that playback
--- started, and a couple of seconds late to that is not worth the wakeups.
obj.idlePollInterval = 6

--- StreamDeckMedia.nowPlayingDebug
--- Variable
--- Log every now-playing poll result and each adapter build step. Default false.
obj.nowPlayingDebug = false

--- StreamDeckMedia.spoonPath
--- Variable
--- Where the bundle was loaded from, with a trailing slash. The adapter sources are
--- read from here.
obj.spoonPath = hs.spoons.scriptPath()

--- StreamDeckMedia.cachePath
--- Variable
--- Where the compiled adapter and the cached artwork are kept.
---
--- Outside the bundle on purpose: everything under it is build output, rebuilt from
--- source on demand, and a spoon directory that rewrites itself is one that cannot
--- be shipped read-only or diffed against what was installed.
obj.cachePath = os.getenv("HOME") .. "/.cache/hammerspoon/StreamDeckMedia"

-- ---------------------------------------------------------------------------
-- Module wiring
-- ---------------------------------------------------------------------------

-- Each module file returns a factory taking its dependencies, so there is one
-- place — here — where the dependency graph is visible, and no module can be used
-- before it has been given its config.
--
-- The config passed is this table itself, read live: assigning to
-- `spoon.StreamDeckMedia.mediaCooldown` at any time keeps working as it did when
-- every setting lived in one file. The two paths above are the exception, since
-- they are read once, at the top of nowplaying.lua.
--
-- dofile rather than require: hs.loadSpoon finds a spoon through package.path,
-- which has no pattern that would resolve a second file inside the bundle.
--
-- resourcePath() resolves against the file its caller was loaded from, so this
-- helper only works while it lives alongside the modules it loads.
local function submodule(name)
    return dofile(hs.spoons.resourcePath(name))
end

-- Resolved at each use rather than captured, so `deck` can be set after the spoon
-- is loaded and so the error lands on the first call that actually needed a broker
-- rather than at load time, where it would take the whole config down.
local function deck()
    local sd = obj.deck or spoon.StreamDeck
    if not sd then
        error("StreamDeckMedia needs a Stream Deck broker: hs.loadSpoon(\"StreamDeck\"), " ..
              "or set spoon.StreamDeckMedia.deck to one", 2)
    end
    return sd
end

local draw = submodule("draw.lua")
local nowplaying = submodule("nowplaying.lua")(obj)
local volume = submodule("volume.lua")(obj, deck, draw)
local media = submodule("media.lua")(obj, deck, draw, nowplaying)

-- ---------------------------------------------------------------------------
-- Now-playing session
-- ---------------------------------------------------------------------------

--- StreamDeckMedia:nowPlaying() -> table
--- Method
--- The last now-playing snapshot. Never nil, so callers need no guard before
--- indexing it.
---
--- Keys: `title`, `artist`, `album` (strings, any may be absent — a stream often
--- has no album), `duration`, `elapsed`, `rate`, `timestamp` (numbers, seconds),
--- `artworkPath` (string), `playing` (boolean). Two flags say why there is nothing
--- to show: `idle` for nothing playing, `unavailable` with a `reason` for a session
--- that cannot be read at all. Position is not a key — it moves between polls, so
--- ask position() for it.
function obj:nowPlaying()
    return nowplaying.state()
end

--- StreamDeckMedia:position([snapshot]) -> number or nil
--- Method
--- Where the track is now, in seconds, advanced from when the snapshot was taken.
---
--- The session reports a position and the time it was true, not a live clock, so
--- this projects one from the other. That is what lets a progress bar animate at
--- any framerate off a snapshot that is seconds old, and why a paused track sits
--- still: its rate is 0.
function obj:position(snapshot)
    return nowplaying.position(snapshot)
end

--- StreamDeckMedia:artwork([snapshot]) -> hs.image or nil
--- Method
--- The album art for a snapshot, read from the file the adapter cached it in.
function obj:artwork(snapshot)
    return nowplaying.artwork(snapshot)
end

--- StreamDeckMedia:subscribe(fn) -> token
--- Method
--- Call fn(snapshot) when the track changes, and once immediately with the current
--- one. Returns a token for unsubscribe().
---
--- Fires on a change of track or play state, not on every poll: the position moves
--- constantly and a subscriber that wants it animating should run its own timer and
--- ask position(), rather than be woken for a number it can compute.
function obj:subscribe(fn)
    return nowplaying.subscribe(fn)
end

--- StreamDeckMedia:unsubscribe(token)
--- Method
--- Stop calling a subscriber registered with subscribe().
function obj:unsubscribe(token)
    nowplaying.unsubscribe(token)
    return self
end

--- StreamDeckMedia:refresh()
--- Method
--- Poll the session now instead of waiting for the next tick. A no-op before
--- start().
function obj:refresh()
    nowplaying.refresh()
    return self
end

-- ---------------------------------------------------------------------------
-- Volume
-- ---------------------------------------------------------------------------

--- StreamDeckMedia:volumeLevel() -> number, boolean, hs.audiodevice
--- Method
--- The default output device's level, mutedness and identity.
---
--- Level is nil for a device CoreAudio exposes no volume control on, which is
--- ordinary for HDMI and for outboard DACs that keep their own; mutedness is nil on
--- the same grounds and independently of the level.
function obj:volumeLevel()
    return volume.level()
end

--- StreamDeckMedia:nudgeVolume(up)
--- Method
--- Move the output level one detent in the given direction, as turning the knob
--- does — including the spin detection, so calling this in a loop goes coarse the
--- same way a spin would.
function obj:nudgeVolume(up)
    volume.nudge(up)
    return self
end

--- StreamDeckMedia:toggleMute()
--- Method
--- Toggle mute, by the same key the keyboard's mute key sends.
function obj:toggleMute()
    volume.toggleMute()
    return self
end

--- StreamDeckMedia:volumeImage([level, muted]) -> hs.image
--- Method
--- The volume segment's artwork for a level, defaulting to the current one.
---
--- Public so the readout can be previewed with no deck connected: hs.canvas has no
--- way to show what it drew other than handing back the image.
function obj:volumeImage(level, muted)
    return volume.screenImage(level, muted)
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

--- StreamDeckMedia:skip(forward) -> boolean
--- Method
--- Send one track skip, unless the cooldown swallows it. Returns whether it went.
function obj:skip(forward)
    return media.skip(forward)
end

--- StreamDeckMedia:togglePlay()
--- Method
--- Play or pause, by the same key the keyboard's play key sends.
function obj:togglePlay()
    media.togglePlay()
    return self
end

--- StreamDeckMedia:mediaImage([snapshot]) -> hs.image
--- Method
--- The media segment's artwork: previous, play/pause and next, dimmed when there is
--- nothing playing.
function obj:mediaImage(snapshot)
    return media.screenImage(snapshot)
end

--- StreamDeckMedia:viewImage([snapshot]) -> hs.image
--- Method
--- The full-width view as one image the width of the whole strip, for previewing it
--- without a deck connected.
function obj:viewImage(snapshot)
    return media.viewImage(snapshot)
end

--- StreamDeckMedia:showView()
--- Method
--- Take the whole strip for the full-width view of the current track.
function obj:showView()
    media.showView()
    return self
end

--- StreamDeckMedia:hideView()
--- Method
--- Dismiss the full-width view and give the strip back to the segment claims.
function obj:hideView()
    media.hideView()
    return self
end

-- ---------------------------------------------------------------------------
-- Surfaces
-- ---------------------------------------------------------------------------

--- StreamDeckMedia:startVolume()
--- Method
--- Claim the volume knob and its strip segment, and begin tracking the default
--- output device.
function obj:startVolume()
    volume.start()
    return self
end

--- StreamDeckMedia:stopVolume()
--- Method
--- Release the volume knob and its strip segment, and stop tracking the output
--- device.
function obj:stopVolume()
    volume.stop()
    return self
end

--- StreamDeckMedia:startMedia()
--- Method
--- Claim the transport knob and its strip segment, and follow the session.
---
--- This only subscribes; it does not start the polling that feeds the subscription.
--- start() does both, in the order that gets the first readout out fastest.
function obj:startMedia()
    media.start()
    return self
end

--- StreamDeckMedia:stopMedia()
--- Method
--- Release the transport knob and its strip segment, dismiss the full-width view if
--- it is up, and stop following the session.
function obj:stopMedia()
    media.stop()
    return self
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- StreamDeckMedia:start()
--- Method
--- Claim both knobs and begin polling the now-playing session.
---
--- This starts everything, rather than leaving each surface to be opted into: the
--- knobs are what the spoon is for, and the poller exists to feed one of them, so
--- there is no useful state where it is running and they are not. startVolume(),
--- stopVolume(), startMedia() and stopMedia() are there for giving one of them back
--- at runtime.
function obj:start()
    self:startVolume()
    self:startMedia()

    -- Last, and after the media surface has subscribed: starting the poller fetches
    -- immediately, and there is no reason for the first readout to wait a poll
    -- interval for a subscriber that is already there.
    nowplaying.start()
    return self
end

--- StreamDeckMedia:stop()
--- Method
--- Release both knobs, blank their strip segments and stop polling.
---
--- The last snapshot stays readable through nowPlaying() and the images stay
--- renderable, so stopping is giving up the deck and the wakeups, not the data.
function obj:stop()
    nowplaying.stop()
    self:stopMedia()
    self:stopVolume()
    return self
end

return obj
