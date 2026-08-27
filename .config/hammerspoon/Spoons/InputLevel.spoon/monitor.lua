--- === InputLevel.monitor ===
---
--- Runs the AVAudioEngine helper, polls its output continuously, latches a clip
--- indicator over what it reports, and mirrors live input gain/mute off CoreAudio.
--- Publishes one state snapshot to every subscriber.
---
--- Unlike NextEvent's helper, this one never exits on its own — it runs the whole
--- time the spoon is started, gating its own mic tap on whether some other process
--- is using the input device — so this module also owns starting and killing it,
--- which NextEvent's one-shot equivalent never needed.

return function(cfg)

local M = {}

local pollTimer = nil
local watchedDevice = nil   -- the hs.audiodevice whose watcher we currently hold
local watchedUID = nil      -- its uid(), to notice a default-device switch on poll
local subscribers = {}
local nextToken = 1

local peakDb = nil          -- last reading from the helper, or nil before one arrives
local active = nil           -- whether the helper's tap is currently engaged
local lastReadAt = nil       -- os.time() the last reading was decoded
local clipHeldUntil = nil    -- hs.timer.secondsSinceEpoch() until which "clipped" reads true
local helperError = nil      -- "no-access", "access-timeout", a gate failure, or a decode failure

local BUNDLE_ID = "org.kusold.InputLevelHelper"

-- The helper is launched through LaunchServices and so inherits no stdout of ours; a
-- file is how its answer comes back. TMPDIR is per-user and mode 700, which a fixed
-- name under /tmp would not be.
local OUT = (function()
    local dir = os.getenv("TMPDIR")
    if not dir then return os.tmpname() end
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end
    return dir .. "InputLevel.json"
end)()

-- ---------------------------------------------------------------------------
-- State snapshot
-- ---------------------------------------------------------------------------

--- InputLevel.monitor.state() -> table
--- Function
--- Snapshot of the current reading. See InputLevel:state() for the fields.
function M.state()
    local now = hs.timer.secondsSinceEpoch()
    local device = hs.audiodevice.defaultInputDevice()
    local gain = device and device:inputVolume()
    local fresh = lastReadAt and (os.time() - lastReadAt) <= cfg.staleAfter

    return {
        peakDb = fresh and peakDb or nil,
        active = fresh and active or nil,
        clipped = fresh and clipHeldUntil ~= nil and now < clipHeldUntil or false,
        gain = gain,
        -- Not `device and device:inputMuted() or nil`: inputMuted() legitimately
        -- returns false for the ordinary unmuted case, and that idiom's `or nil`
        -- would collapse it to nil — indistinguishable from "unsupported" — losing
        -- the one case that matters most.
        muted = device and device:inputMuted(),
        hasGainControl = gain ~= nil,
        stale = not fresh,
        error = helperError,
    }
end

local function publish()
    local state = M.state()
    for _, fn in pairs(subscribers) do
        -- One subscriber throwing must not cost the others their update.
        local ok, err = pcall(fn, state)
        if not ok then
            hs.printf("[InputLevel] subscriber failed: %s", tostring(err))
        end
    end
end

--- InputLevel.monitor.subscribe(fn) -> token
--- Function
--- Call fn(snapshot) on every publish. Returns a token for unsubscribe().
function M.subscribe(fn)
    local token = nextToken
    nextToken = nextToken + 1
    subscribers[token] = fn
    -- Hand over the current state immediately so a late subscriber paints itself now
    -- rather than staying blank until the next tick.
    local ok, err = pcall(fn, M.state())
    if not ok then
        hs.printf("[InputLevel] subscriber failed: %s", tostring(err))
    end
    return token
end

--- InputLevel.monitor.unsubscribe(token)
--- Function
--- Remove a subscriber registered with subscribe().
function M.unsubscribe(token)
    if token then subscribers[token] = nil end
end

-- ---------------------------------------------------------------------------
-- Gain and mute
-- ---------------------------------------------------------------------------

--- InputLevel.monitor.nudgeGain(up)
--- Function
--- Move the default input device's gain by cfg.gainStep, clamped to [0, 100].
---
--- A device with no software input gain control (the physical preamp knob is the
--- only control CoreAudio exposes) reports setInputVolume() false; there is nothing
--- to do about that here beyond letting the caller's read of hasGainControl say so.
function M.nudgeGain(up)
    local device = hs.audiodevice.defaultInputDevice()
    local level = device and device:inputVolume()
    if not (device and level) then return end

    local target = math.max(0, math.min(100, level + (up and cfg.gainStep or -cfg.gainStep)))
    device:setInputVolume(target)
    publish()
end

--- InputLevel.monitor.toggleMute()
--- Function
--- Toggle mute on the default input device.
function M.toggleMute()
    local device = hs.audiodevice.defaultInputDevice()
    local muted = device and device:inputMuted()
    if not (device and muted ~= nil) then return end

    device:setInputMuted(not muted)
    publish()
end

-- ---------------------------------------------------------------------------
-- Device watching
-- ---------------------------------------------------------------------------

-- Anything else on the machine can move input gain or mute — System Settings, a
-- hardware mute button on the mic itself — and a readout that only tracked the knob
-- would sit there being confidently wrong. Watching the device closes that gap.
--
-- This is a per-device watcher (device:watcherCallback()), not the module-level
-- hs.audiodevice.watcher — that one is a single process-wide callback already
-- claimed by StreamDeckMedia.volume for "dOut", and a second setCallback() here
-- would silently replace it rather than add a second listener. So a default-device
-- switch is noticed by comparing uid() on the poll tick below instead of subscribing
-- to that watcher's "dIn " event.
local function watch(device)
    if watchedDevice then
        pcall(function() watchedDevice:watcherStop() end)
        pcall(function() watchedDevice:watcherCallback(nil) end)
    end
    watchedDevice = device
    watchedUID = device and device:uid()
    if not device then return end

    device:watcherCallback(function(_uid, event)
        if event == "vmvc" or event == "mute" then
            publish()
        end
    end)
    device:watcherStart()
end

-- ---------------------------------------------------------------------------
-- Helper process
-- ---------------------------------------------------------------------------

local function killHelper()
    for _, app in ipairs(hs.application.applicationsForBundleID(BUNDLE_ID)) do
        app:kill9()
    end
end

local function launchHelper()
    local app = hs.spoons.resourcePath("InputLevel.app")

    -- open(1) returns as soon as LaunchServices has taken the request, long before
    -- the helper has answered, so a zero exit says only "launched". A non-zero one
    -- is worth reporting immediately rather than waiting for the poll timer to
    -- notice the output file never arrived. See NextEvent.monitor.refresh() for the
    -- same reasoning against the same command.
    local launcher = hs.task.new("/usr/bin/open", function(rc, _stdOut, stdErr)
        if rc ~= 0 then
            helperError = string.format("helper would not launch (open rc=%s) %s",
                                         tostring(rc), (stdErr or ""):gsub("%s+$", ""))
            publish()
        end
    end, {"-n", "-g", "-a", app, "--args", OUT})

    if not (launcher and launcher:start()) then
        helperError = "could not build the helper launch task"
        publish()
    end
end

local function poll()
    local current = hs.audiodevice.defaultInputDevice()
    if (current and current:uid() or nil) ~= watchedUID then
        watch(current)
    end

    local f = io.open(OUT, "r")
    if not f then return end
    local raw = f:read("a")
    f:close()
    if raw == "" then return end

    local ok, parsed = pcall(hs.json.decode, raw)
    if not ok or type(parsed) ~= "table" then
        helperError = "could not decode helper output"
        publish()
        return
    end

    if parsed.error then
        -- "no-access" means the grant this bundle holds was refused or revoked, which
        -- polling again cannot fix. See helper/inputlevel.swift for why the grant
        -- lives on the bundle rather than on Hammerspoon.
        helperError = parsed.error
        publish()
        return
    end

    -- The helper writes a fresh tick whether or not it's currently tapping, so
    -- lastReadAt means "helper alive" independent of active — that distinction is
    -- what lets the strip show "no call in progress" rather than "helper is dead".
    lastReadAt = os.time()
    active = parsed.active or false
    helperError = parsed.gateError

    if active then
        peakDb = parsed.peakDb
        if parsed.over then
            clipHeldUntil = hs.timer.secondsSinceEpoch() + cfg.clipHoldSeconds
        end
    else
        peakDb = nil
    end

    publish()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- InputLevel.monitor.start()
--- Function
--- Kill any orphaned instance of the helper, launch a fresh one, and begin polling
--- and watching. Repeat calls are ignored.
function M.start()
    if pollTimer then return end

    -- A previous Hammerspoon exit that skipped stop() (a crash, or hs.reload()
    -- tearing down the Lua state) leaves this helper running, since unlike
    -- NextEvent's one-shot equivalent it never exits on its own. Killing whatever is
    -- already there first is what keeps every restart at exactly one instance.
    killHelper()
    os.remove(OUT)
    launchHelper()

    watch(hs.audiodevice.defaultInputDevice())
    pollTimer = hs.timer.doEvery(cfg.pollInterval, poll)
end

--- InputLevel.monitor.stop()
--- Function
--- Stop polling and watching, and kill the helper. NextEvent needed no equivalent of
--- this, since its helper exits on its own once it has answered.
function M.stop()
    if pollTimer then
        pollTimer:stop()
        pollTimer = nil
    end
    watch(nil)
    killHelper()
    os.remove(OUT)

    peakDb = nil
    active = nil
    lastReadAt = nil
    clipHeldUntil = nil
    helperError = nil
end

return M

end
