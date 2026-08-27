--- === StreamDeckMedia.nowplaying ===
---
--- What macOS thinks is playing — title, artist, album, position and artwork — for
--- whichever app owns the system's now-playing session: Chrome, Music, Spotify, the
--- same one the media keys talk to.
---
--- This module is the only place in the spoon that touches a private framework, and
--- it is a separate file for exactly that reason. MediaRemote is private, and since
--- macOS 15.4 it answers only callers that are Apple-signed binaries — Hammerspoon
--- asking directly gets nil back whether or not anything is playing. The way through
--- is out of process: adapter.m built as a dylib and loaded into /usr/bin/perl,
--- which passes that check. See adapter.m for the mechanics.
---
--- That is a deliberate bypass of a restriction Apple added on purpose, so treat
--- this file as load-bearing-until-it-isn't: an OS update can break it, and when it
--- does the failure is contained here. Every surface reading from it goes through
--- state(), which reports `unavailable` rather than throwing, so a broken adapter
--- costs you a readout and nothing else.
---
--- The adapter is compiled on demand from source that ships in the spoon bundle, so
--- there is no binary to keep in sync with the machine's architecture. It needs the
--- Xcode command line tools; without them this module stays unavailable and says so.

return function(cfg)

local M = {}

-- ---------------------------------------------------------------------------
-- Paths
-- ---------------------------------------------------------------------------

local SOURCE  = cfg.spoonPath .. "adapter.m"
local LOADER  = cfg.spoonPath .. "adapter.pl"
local CACHE   = cfg.cachePath
local DYLIB   = CACHE .. "/adapter.dylib"
local ART_DIR = CACHE .. "/artwork"

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local state = {unavailable = true, reason = "not started"}
local subscribers = {}
local nextToken = 0
local timer = nil        -- the pending poll, if any
local running = false
local inFlight = false   -- a fetch is out; do not start a second
local build = "unbuilt"  -- unbuilt | building | ok | failed
local artCache = {}      -- path -> hs.image, so a repaint does not re-read the file

local function log(fmt, ...)
    if cfg.nowPlayingDebug then hs.printf("[StreamDeckMedia] " .. fmt, ...) end
end

-- ---------------------------------------------------------------------------
-- Snapshot
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.nowplaying.state() -> table
--- Function
--- The last snapshot. Never nil, so callers need no guard before indexing it.
---
--- Keys: `title`, `artist`, `album` (strings, any may be absent — a stream often
--- has no album), `duration`, `elapsed`, `rate`, `timestamp` (numbers, seconds),
--- `artworkPath` (string), `playing` (boolean). Two flags say why there is nothing
--- to show: `idle` for nothing playing, `unavailable` with a `reason` for a module
--- that cannot read at all. Position is not a key — it moves between polls, so ask
--- position() for it.
function M.state()
    return state
end

--- StreamDeckMedia.nowplaying.position([snapshot]) -> number or nil
--- Function
--- Where the track is now, in seconds, advanced from when the snapshot was taken.
---
--- The session reports a position and the time it was true, not a live clock, so
--- this projects one from the other. That is what lets a progress bar animate at
--- any framerate off a snapshot that is seconds old, and why a paused track sits
--- still: its rate is 0.
function M.position(snapshot)
    local s = snapshot or state
    if not s.elapsed then return nil end
    if not (s.playing and s.timestamp) then return s.elapsed end

    local moved = (hs.timer.secondsSinceEpoch() - s.timestamp) * (s.rate or 1)
    local at = s.elapsed + moved
    -- Clamping matters at the end of a track: the session can go a poll or two
    -- without an update, and a bar past its own track reads as a bug.
    if s.duration then at = math.min(at, s.duration) end
    return math.max(0, at)
end

--- StreamDeckMedia.nowplaying.artwork([snapshot]) -> hs.image or nil
--- Function
--- The album art, read from the file the adapter cached it in.
---
--- Cached by path, because the artwork identifier is stable for a track and a
--- repainting progress bar would otherwise re-read the same JPEG every frame.
function M.artwork(snapshot)
    local path = (snapshot or state).artworkPath
    if not path then return nil end
    if artCache[path] == nil then
        artCache[path] = hs.image.imageFromPath(path) or false
    end
    return artCache[path] or nil
end

-- ---------------------------------------------------------------------------
-- Subscribers
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.nowplaying.subscribe(fn) -> token
--- Function
--- Call fn(state) when the track changes, and once immediately with the current one.
---
--- Fires on a change of track or play state, not on every poll: the position moves
--- constantly and a subscriber that wants it animating should run its own timer and
--- ask position(), rather than be woken for a number it can compute.
function M.subscribe(fn)
    nextToken = nextToken + 1
    subscribers[nextToken] = fn
    local ok, err = pcall(fn, state)
    if not ok then hs.printf("[StreamDeckMedia] subscriber failed: %s", tostring(err)) end
    return nextToken
end

--- StreamDeckMedia.nowplaying.unsubscribe(token)
--- Function
--- Stop calling a subscriber registered with subscribe().
function M.unsubscribe(token)
    subscribers[token] = nil
end

-- What counts as a different thing to show. Position is deliberately absent: it
-- changes on every poll, and waking every surface twice a second to redraw a
-- string that has not changed is how a readout becomes a battery cost.
local function signature(s)
    return table.concat({
        s.title or "", s.artist or "", s.album or "",
        s.artworkPath or "", tostring(s.playing), tostring(s.idle),
        tostring(s.unavailable),
    }, "\30")
end

local function publish(next)
    local changed = signature(next) ~= signature(state)
    state = next
    if not changed then return end

    for _, fn in pairs(subscribers) do
        local ok, err = pcall(fn, state)
        if not ok then hs.printf("[StreamDeckMedia] subscriber failed: %s", tostring(err)) end
    end
end

-- ---------------------------------------------------------------------------
-- Adapter build
-- ---------------------------------------------------------------------------

-- hs.fs.mkdir creates one level and fails if the parent is missing, so an absolute
-- path is walked a component at a time. Every level but the last is expected to
-- exist already and to fail benignly; the last one is checked by the build that
-- follows, which reports its own error if the directory never appeared.
local function mkdirp(path)
    local built = ""
    for part in path:gmatch("[^/]+") do
        built = built .. "/" .. part
        hs.fs.mkdir(built)
    end
end

local function stale()
    local src = hs.fs.attributes(SOURCE, "modification")
    local out = hs.fs.attributes(DYLIB, "modification")
    if not src then return false, "adapter.m missing" end
    if not out then return true end
    return out < src
end

local function ensureBuilt(done)
    if build == "ok" then return done(true) end
    if build == "failed" then return done(false) end
    if build == "building" then return end   -- the in-flight build will start the poll

    local needed, missing = stale()
    if missing then
        build = "failed"
        publish({unavailable = true, reason = missing})
        return done(false)
    end
    if not needed then
        build = "ok"
        return done(true)
    end

    build = "building"
    mkdirp(ART_DIR)
    log("building %s", DYLIB)

    hs.task.new("/usr/bin/clang", function(code, _out, err)
        if code == 0 then
            build = "ok"
            log("build ok")
            return done(true)
        end
        build = "failed"
        -- Worth surfacing without debug on: the whole module is dead until this is
        -- fixed, and the usual cause (no command line tools) is not self-evident
        -- from an empty readout.
        hs.printf("[StreamDeckMedia] adapter build failed (%s): %s", tostring(code), tostring(err))
        publish({unavailable = true, reason = "adapter build failed"})
        done(false)
    end, {
        "-dynamiclib", "-fobjc-arc", "-O2", "-framework", "Foundation",
        "-o", DYLIB, SOURCE,
    }):start()
end

-- ---------------------------------------------------------------------------
-- Polling
-- ---------------------------------------------------------------------------

local schedule  -- forward declaration; fetch reschedules itself

local function parse(out)
    local ok, decoded = pcall(hs.json.decode, out)
    if not ok or type(decoded) ~= "table" then
        return {unavailable = true, reason = "unparsable adapter output"}
    end
    if decoded.error then
        return {unavailable = true, reason = "adapter: " .. tostring(decoded.error)}
    end
    if decoded.idle then
        return {idle = true, playing = false}
    end
    -- Normalised, not passed through: JSON true survives hs.json.decode as a Lua
    -- boolean, but a 0 would not — every number is truthy in Lua, so a paused
    -- track would read as playing anywhere this value is tested directly.
    decoded.playing = decoded.playing == true or decoded.playing == 1
    return decoded
end

local function fetch()
    if inFlight then return end
    inFlight = true

    local task = hs.task.new("/usr/bin/perl", function(code, out, err)
        inFlight = false
        if code == 0 then
            local next = parse(out)
            log("%s", hs.inspect(next, {depth = 1}))
            publish(next)
        else
            hs.printf("[StreamDeckMedia] adapter run failed (%s): %s", tostring(code), tostring(err))
            publish({unavailable = true, reason = "adapter run failed"})
        end
        schedule()
    end, {LOADER, DYLIB})

    -- setEnvironment replaces the environment rather than adding to it, so the few
    -- things perl and the adapter actually need are listed explicitly.
    task:setEnvironment({
        PATH = "/usr/bin:/bin",
        HOME = os.getenv("HOME"),
        NP_ARTWORK_DIR = ART_DIR,
    })
    task:start()
end

schedule = function()
    if timer then timer:stop() end
    if not running then return end
    local gap = (state.idle or state.unavailable) and cfg.idlePollInterval or cfg.pollInterval
    timer = hs.timer.doAfter(gap, fetch)
end

--- StreamDeckMedia.nowplaying.refresh()
--- Function
--- Poll now instead of waiting for the next tick.
---
--- For the moment after a transport command, when the session is about to change
--- and the readout would otherwise sit wrong for a poll interval.
function M.refresh()
    if not running then return end
    ensureBuilt(function(ok) if ok then fetch() end end)
end

--- StreamDeckMedia.nowplaying.start()
--- Function
--- Build the adapter if needed and begin polling.
function M.start()
    if running then return M end
    running = true
    ensureBuilt(function(ok)
        if ok then fetch() end
    end)
    return M
end

--- StreamDeckMedia.nowplaying.stop()
--- Function
--- Stop polling. Subscribers stay registered and the last snapshot stays readable.
function M.stop()
    running = false
    if timer then timer:stop() end
    timer = nil
    return M
end

return M

end
