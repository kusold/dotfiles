--- === Amphetamine.amphetamine ===
---
--- The bridge to Amphetamine.app: every Apple Event this spoon sends, and nothing
--- else. No timers, no state, no drawing.
---
--- AppleScript is the only way in. Amphetamine ships no command line tool, and its
--- Info.plist declares no CFBundleURLTypes, so there is no URL scheme to open either;
--- what it does declare is NSAppleScriptEnabled and an OSAScriptingDefinition, whose
--- dictionary is Contents/Resources/Amphetamine.sdef inside the bundle. Every command
--- named below comes from that file.
---
--- `session time remaining` is the command that makes a countdown possible at all: it
--- answers in seconds, and for the session kinds that have no seconds to report it
--- answers with a negative sentinel instead. Reading those sentinels is this file's
--- job, so that nothing above it has to know the numbers; what it hands up is a kind.
---
--- Scripts run out of process through osascript rather than in process through
--- hs.osascript, for the reason ClaudeUsage.monitor shells out to `security`: an Apple
--- Event carries no deadline of its own, and Amphetamine can put up a modal — its
--- `enable closed display mode` command documents one — which in process would stall
--- the main thread that also drives every hotkey and window binding.
---
--- `cfg` is the spoon table, read live, which is why the scripts carrying a setting
--- are built per call rather than held as constants.

return function(cfg)

local M = {}

-- Addressed by bundle identifier rather than by name, for the reason
-- NextEvent.calendarBundleID gives: a name can resolve to more than one app, an
-- identifier cannot. Not configurable, because the terminology below is this app's.
local BUNDLE_ID = "com.if.Amphetamine"

-- Sentinels of `session time remaining`, from the sdef's description of it. Any other
-- answer is a count of seconds.
local INFINITE = 0    -- session of infinite duration
local TRIGGER  = -1   -- session started by a Trigger
local EXTERNAL = -2   -- app-based ("while app is running") or date-based ("until XX:XX")
local INACTIVE = -3   -- no active session

-- ---------------------------------------------------------------------------
-- Running scripts
-- ---------------------------------------------------------------------------

-- osascript prints the OSStatus in parentheses at the end of its message, and two of
-- them mean a human has to do something before this spoon can work at all: -1743 is
-- TCC withholding Apple Events until Hammerspoon is granted Automation access to
-- Amphetamine, and -1728 is `application id` failing to resolve, which for an
-- identifier fixed in this file means Amphetamine is not installed. Both are worth
-- saying on a key; everything else is for the console.
local function asError(exitCode, stderr)
    local message = (stderr or ""):gsub("%s+$", "")
    if message == "" then
        message = string.format("osascript exited %s", tostring(exitCode))
    end

    local status = tonumber(message:match("%((%-?%d+)%)%s*$"))
    local hint
    if status == -1743 then
        hint = "allow access"
    elseif status == -1728 then
        hint = "not found"
    end

    return {message = message, hint = hint, status = status}
end

-- Calls back once, as callback(exitCode, stdout, stderr).
local function run(script, callback)
    local settled = false
    local watchdog = nil
    local task = nil

    local function settle(exitCode, out, err)
        if settled then return end
        settled = true
        if watchdog then watchdog:stop(); watchdog = nil end
        callback(exitCode, out or "", err or "")
    end

    task = hs.task.new("/usr/bin/osascript", function(exitCode, out, err)
        settle(exitCode, out, err)
    end, {"-e", script})

    if not task or not task:start() then
        return settle(-1, "", "could not run osascript")
    end

    -- An Apple Event has no deadline and Amphetamine can block on a modal, so the task
    -- is given one. Terminating it makes its own callback fire in turn, which is what
    -- `settled` is for: the caller is called back exactly once either way.
    watchdog = hs.timer.doAfter(cfg.commandTimeout, function()
        watchdog = nil
        if settled then return end
        pcall(function() task:terminate() end)
        settle(-1, "", string.format("no answer from Amphetamine in %ss", tostring(cfg.commandTimeout)))
    end)
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- `application id ... is running` is tested before anything is told to Amphetamine
-- because `tell application` launches what it addresses, and a poll running every
-- refreshInterval must not resurrect an Amphetamine that was deliberately quit.
-- Reading the property does not launch it.
local READ_SCRIPT = string.format([==[
if application id "%s" is running then
	tell application id "%s"
		set a to session is active
		set r to session time remaining
	end tell
	return (a as text) & "|" & (r as text)
else
	return "false|%d"
end if
]==], BUNDLE_ID, BUNDLE_ID, INACTIVE)

local function parseReading(stdout)
    local activeText, remainingText = (stdout or ""):match("^(%a+)|(%-?%d+)")
    if not activeText then return nil end

    local remaining = tonumber(remainingText)
    if activeText ~= "true" or remaining == INACTIVE then
        return {active = false, kind = "off"}
    end
    if remaining == INFINITE then return {active = true, kind = "infinite"} end
    if remaining == TRIGGER then return {active = true, kind = "trigger"} end
    if remaining > 0 then return {active = true, kind = "timed", remaining = remaining} end

    -- EXTERNAL, and any sentinel a later Amphetamine adds: a session is running and
    -- this is not the command that can say how long for. Reporting it as running with
    -- no countdown is the answer that stays true if that list grows.
    return {active = true, kind = "external"}
end

--- Amphetamine.amphetamine.read(callback)
--- Function
--- Read the current session. Calls back as callback(reading) or callback(nil, err).
---
--- reading is {active = boolean, kind = string, remaining = number or nil}, where kind
--- is "off", "infinite", "timed", "trigger" or "external", and remaining is a count of
--- seconds carried only by "timed".
---
--- err is {message = string, hint = string or nil, status = number or nil}, where hint
--- is a short phrase fit for a key when the cause is something only a human can fix.
function M.read(callback)
    run(READ_SCRIPT, function(exitCode, out, err)
        if exitCode ~= 0 then return callback(nil, asError(exitCode, err)) end

        local reading = parseReading(out)
        if not reading then
            return callback(nil, {
                message = "could not read session state from: " .. (out or ""):gsub("%s+$", ""),
            })
        end
        callback(reading)
    end)
end

-- ---------------------------------------------------------------------------
-- Acting
-- ---------------------------------------------------------------------------

--- Amphetamine.amphetamine.toggle(callback)
--- Function
--- End the session if one is running, start an endless one if not. Calls back as
--- callback("on"|"off") or callback(nil, err).
---
--- Both halves are one script, so the decision is made against Amphetamine's own
--- state at the moment it acts rather than against a poll that may be a refreshInterval
--- old — which is the difference between a key that toggles and a key that sometimes
--- turns on twice.
---
--- Deliberately not guarded by `is running`, unlike read(): a press meaning "keep this
--- Mac awake" should launch Amphetamine if it has been quit, and `tell` does.
function M.toggle(callback)
    local script = string.format([==[
tell application id "%s"
	if session is active then
		end session
		return "off"
	else
		start new session with options {duration:0, interval:0, displaySleepAllowed:%s}
		return "on"
	end if
end tell
]==], BUNDLE_ID, tostring(cfg.displaySleepAllowed))

    run(script, function(exitCode, out, err)
        if exitCode ~= 0 then return callback(nil, asError(exitCode, err)) end

        local result = (out or ""):match("^(%a+)")
        if result ~= "on" and result ~= "off" then
            return callback(nil, {message = "unexpected toggle result: " .. (out or ""):gsub("%s+$", "")})
        end
        callback(result)
    end)
end

--- Amphetamine.amphetamine.sessionFor(minutes, callback)
--- Function
--- Start a session of that many minutes, replacing any session already running. Calls
--- back as callback(true) or callback(nil, err).
---
--- Per the sdef, `start new session` ends whatever was running first, Trigger sessions
--- included, so this needs no matching stop and means the same thing whatever the key
--- was showing when it was pressed.
function M.sessionFor(minutes, callback)
    -- `minutes` here is AppleScript's own constant for sixty rather than a piece of
    -- Amphetamine terminology, which is why it is bare rather than quoted: the record
    -- carries the number 60, and the length of the session is `duration` times that.
    -- Which is what makes `duration` a count of minutes, and also why it may never
    -- arrive as zero — see nextTarget() in init.lua.
    local script = string.format([==[
tell application id "%s" to start new session with options {duration:%d, interval:minutes, displaySleepAllowed:%s}
]==], BUNDLE_ID, minutes, tostring(cfg.displaySleepAllowed))

    run(script, function(exitCode, _out, err)
        if exitCode ~= 0 then return callback(nil, asError(exitCode, err)) end
        callback(true)
    end)
end

--- Amphetamine.amphetamine.endSession(callback)
--- Function
--- End the running session. Calls back as callback(true) or callback(nil, err).
---
--- Guarded by `is running` because ending a session in an Amphetamine that is not
--- running is already true, and launching it to say so would be the one way this call
--- could leave the Mac more awake than it found it.
function M.endSession(callback)
    local script = string.format([==[
if application id "%s" is running then
	tell application id "%s" to end session
end if
]==], BUNDLE_ID, BUNDLE_ID)

    run(script, function(exitCode, _out, err)
        if exitCode ~= 0 then return callback(nil, asError(exitCode, err)) end
        callback(true)
    end)
end

return M

end
