--- === ClaudeUsage.monitor ===
---
--- The single poller behind every display surface: reads Claude Code's OAuth
--- credentials, fetches the usage endpoint on a timer, absorbs rate limits behind
--- a backoff that survives reloads, and publishes a state snapshot to subscribers.
---
--- Nothing here draws anything. Surfaces subscribe; they never fetch, because the
--- API quota is shared with Claude Code itself and a second fetch loop would
--- double the request rate against a limit that reports no remaining quota.
---
--- `cfg` is the spoon table, read live so that assigning to
--- `spoon.ClaudeUsage.refreshInterval` and friends keeps working.
--- `clawd` supplies the utilization-to-expression mapping carried in the snapshot.

return function(cfg, clawd)

local M = {}

-- Internal state
local timer = nil
local usageData = nil
local usageRaw = nil          -- raw JSON of that payload, for lossless persistence
local usageFetchedAt = nil    -- os.time() of the last successful fetch
local retryAfterEpoch = nil   -- os.time() before which no request may be made
local retryBackoff = nil      -- current backoff step, doubles while requests fail
local lastError = nil
local credentials = nil
local credentialsChecked = false  -- has any credential lookup finished yet?
local subscribers = {}

-- ---------------------------------------------------------------------------
-- Credentials
-- ---------------------------------------------------------------------------

-- Decode Claude Code's credential JSON into its claudeAiOauth table. The blob
-- has the same shape whether it came from the Keychain or from a file.
local function parseCredentialBlob(raw)
    if not raw or raw == "" then
        return nil, "Empty credentials"
    end

    local ok, parsed = pcall(hs.json.decode, raw)
    if not ok or not parsed then
        return nil, "Failed to parse credentials JSON"
    end

    local oauth = parsed.claudeAiOauth
    if not oauth or not oauth.accessToken then
        return nil, "No claudeAiOauth.accessToken in credentials"
    end

    if oauth.expiresAt then
        local nowSec = os.time()
        local expireSec = math.floor(oauth.expiresAt / 1000)
        if nowSec >= expireSec then
            return nil, "OAuth token expired"
        end
    end

    return oauth
end

local function readCredentialsFile()
    local f = io.open(cfg.credentialsPath, "r")
    if not f then
        return nil, "No credentials in Keychain or " .. cfg.credentialsPath
    end
    local raw = f:read("*a")
    f:close()
    return parseCredentialBlob(raw)
end

-- Asynchronous: calls back with (oauth) or (nil, errorString).
--
-- Runs `security` out of process rather than reading it synchronously so that a
-- Keychain access prompt can never stall Hammerspoon's main thread, which also
-- drives every hotkey and window binding.
local function readCredentials(callback)
    local args = {"find-generic-password", "-s", cfg.keychainService, "-w"}

    local task = hs.task.new("/usr/bin/security", function(exitCode, stdOut, _stdErr)
        if exitCode == 0 and stdOut then
            local trimmed = stdOut:gsub("%s+$", "")
            local oauth, err = parseCredentialBlob(trimmed)
            -- A Keychain item that exists but is unusable (expired, malformed)
            -- is reported as-is; falling through to the file would mask it
            -- behind a less accurate "no credentials" error.
            return callback(oauth, err)
        end
        return callback(readCredentialsFile())
    end, args)

    if not task or not task:start() then
        return callback(readCredentialsFile())
    end
end

-- ---------------------------------------------------------------------------
-- Backoff
-- ---------------------------------------------------------------------------

-- The usage endpoint exposes no quota headers at all: a 200 carries none, and a
-- 429 carries only `Retry-After`, observed to be a constant 0. So there is
-- nothing to pace against before hitting the limit, and the header alone cannot
-- say how long to wait. It is read anyway, and used only when it asks for longer
-- than the ramp already planned.
--
-- Only the delta-seconds form is parsed. RFC 9110 also permits an HTTP-date, but
-- this endpoint sends delta-seconds; on anything unrecognised this returns nil
-- and the caller falls back to its own ramp, which is the safe direction.
local function parseRetryAfter(headers)
    if type(headers) ~= "table" then return nil end

    local raw
    for k, v in pairs(headers) do
        if type(k) == "string" and k:lower() == "retry-after" then
            raw = v
            break
        end
    end
    if not raw then return nil end

    return tonumber(tostring(raw):match("^%s*(%d+)%s*$"))
end

-- Escalate the wait after a failed request. Doubles per consecutive failure from
-- minRetryInterval up to maxRetryInterval; a server asking for longer than that
-- ramp wins, since the cap bounds our guessing rather than the server's say.
local function scheduleRetry(retryAfterSeconds)
    local wait = retryBackoff and (retryBackoff * 2) or cfg.minRetryInterval
    wait = math.max(cfg.minRetryInterval, math.min(wait, cfg.maxRetryInterval))

    if retryAfterSeconds and retryAfterSeconds > wait then
        wait = retryAfterSeconds
    end

    retryBackoff = wait
    retryAfterEpoch = os.time() + wait
end

local function clearRetry()
    retryBackoff = nil
    retryAfterEpoch = nil
end

local function retryWaitRemaining()
    if not retryAfterEpoch then return nil end
    local remaining = retryAfterEpoch - os.time()
    if remaining <= 0 then return nil end
    return remaining
end

-- ---------------------------------------------------------------------------
-- Persistence across reloads
-- ---------------------------------------------------------------------------

-- hs.reload() tears down the Lua state, so without this a reload forgets an
-- active backoff and immediately issues a request — the exact behaviour that
-- turns a few config edits into a burst of API calls against a limit that
-- publishes no remaining-quota header.
--
-- Backed by hs.settings (NSUserDefaults), which is an unencrypted plist: the
-- OAuth token is deliberately not part of this, and keeps being read from the
-- Keychain on every fetch.
--
-- The raw response body is stored rather than the decoded table. hs.settings
-- would coerce a deeply nested table through plist types, and re-encoding a
-- decoded payload turns an empty JSON array into an object; a string round-trips
-- exactly.
local function saveState()
    hs.settings.set(cfg.stateKey, {
        version = 1,
        usageRaw = usageRaw,
        usageFetchedAt = usageFetchedAt,
        retryAfterEpoch = retryAfterEpoch,
        retryBackoff = retryBackoff,
    })
end

local function loadState()
    local saved = hs.settings.get(cfg.stateKey)
    if type(saved) ~= "table" or saved.version ~= 1 then return end

    -- Only an outstanding deadline is worth restoring. One already in the past
    -- means the gate is open, and the ramp should start over from the floor
    -- rather than resume doubling from a step set who-knows-how-long ago.
    if type(saved.retryAfterEpoch) == "number" and saved.retryAfterEpoch > os.time() then
        retryAfterEpoch = saved.retryAfterEpoch
        if type(saved.retryBackoff) == "number" then
            retryBackoff = saved.retryBackoff
        end
    end

    if type(saved.usageRaw) == "string" and type(saved.usageFetchedAt) == "number" then
        local ok, parsed = pcall(hs.json.decode, saved.usageRaw)
        if ok and type(parsed) == "table" then
            usageRaw = saved.usageRaw
            usageData = parsed
            usageFetchedAt = saved.usageFetchedAt
        end
    end
end

function M.clearPersistedState()
    hs.settings.clear(cfg.stateKey)
end

-- ---------------------------------------------------------------------------
-- Monthly usage-credit budget: today's spend, and velocity against the
-- workdays left before it resets.
-- ---------------------------------------------------------------------------

-- The usage endpoint's `spend`/`extra_usage` blocks carry a running monthly
-- total only, with no reset timestamp and no per-day breakdown. Everything
-- below is derived from that single number sampled on a timer: today's spend
-- is the delta against the total at the first reading of the local day, and
-- the reset is assumed to be the start of next month UTC, since the payload
-- never says otherwise.

-- os.time() on a table built from UTC calendar fields interprets them as
-- local, off by the local/UTC gap. Adding that gap back gives the true epoch
-- for those UTC fields. See also menubar.lua's own copy, used there to turn
-- API reset timestamps (also UTC) into countdowns.
local function utcOffset()
    local now = os.time()
    local utc = os.time(os.date("!*t", now))
    return os.difftime(now, utc)
end

-- 00:00 UTC on the 1st of next month, as a true epoch.
local function nextMonthStartEpoch()
    local u = os.date("!*t")
    local year, month = u.year, u.month + 1
    if month > 12 then
        year, month = year + 1, 1
    end
    local asLocal = os.time({year = year, month = month, day = 1, hour = 0, min = 0, sec = 0, isdst = false})
    return asLocal + utcOffset()
end

-- Local weekdays from today through resetEpoch's local date, inclusive: today
-- still has hours left in it, and so does the reset day, which rolls over in
-- the evening local time. Advancing by reconstructing the date table (rather
-- than adding 86400 seconds) keeps this correct across a DST transition. No
-- holiday calendar, so a week with one in it reads as a workday busier than
-- it really is.
local function workdaysRemaining(resetEpoch)
    local t = os.date("*t")
    local last = os.date("*t", resetEpoch)
    local days = 0
    while t.year < last.year
        or (t.year == last.year and t.month < last.month)
        or (t.year == last.year and t.month == last.month and t.day <= last.day) do
        if t.wday ~= 1 and t.wday ~= 7 then
            days = days + 1
        end
        t = os.date("*t", os.time({year = t.year, month = t.month, day = t.day + 1, hour = 0, min = 0, sec = 0, isdst = false}))
    end
    return days
end

-- Where the day's opening balance is remembered, separate from cfg.stateKey so
-- that clearPersistedState() (which forgets the usage reading and backoff) does
-- not also reset today's tracked spend.
local dailyStateKey = cfg.stateKey .. ".daily"

local function localDateString(epoch)
    local f = os.date("*t", epoch)
    return string.format("%04d-%02d-%02d", f.year, f.month, f.day)
end

-- (todaySpendMinor, sinceEpoch): spend since the day's opening reading, and
-- when that reading was taken. Not necessarily midnight — a machine asleep
-- overnight takes it whenever it wakes, so this means "since we started
-- watching today," not "since 00:00."
local function todaySpend(usedMinor)
    local now = os.time()
    local today = localDateString(now)
    local state = hs.settings.get(dailyStateKey)
    if type(state) ~= "table" then state = {} end

    local opening, since

    if type(state.lastTotal) == "number" and usedMinor < state.lastTotal then
        -- The total went backwards, which only happens when the month rolled
        -- over. Nothing before that belongs to this budget.
        opening, since = 0, now
    elseif state.date ~= today then
        -- A new local day. Carry the previous day's final reading forward as
        -- today's opening, so spend during a gap in readings -- overnight, or
        -- before the machine woke -- counts toward today instead of being
        -- dropped.
        if type(state.lastTotal) == "number" then
            opening = state.lastTotal
            since = state.lastSeen or now
        else
            opening, since = usedMinor, now
        end
    elseif type(state.opening) == "number" then
        opening = state.opening
        since = state.since or now
    else
        opening, since = usedMinor, now
    end

    hs.settings.set(dailyStateKey, {
        date = today,
        opening = opening,
        since = since,
        lastTotal = usedMinor,
        lastSeen = now,
    })

    return math.max(0, usedMinor - opening), since
end

-- Monthly usage-credit figures plus today's burn rate, or nil when the payload
-- carries neither `spend` nor `extra_usage` (a fixed-window plan reporting
-- five_hour/seven_day instead has no monthly credit budget to track).
--
-- `spend` states its currency and minor-unit exponent explicitly; `extra_usage`
-- is the flatter older form. Prefer `spend`, falling back to `extra_usage`
-- figure by figure.
local function monthlyBudget(data)
    if type(data) ~= "table" then return nil end
    local spend = type(data.spend) == "table" and data.spend or {}
    local extra = type(data.extra_usage) == "table" and data.extra_usage or {}
    if not next(spend) and not next(extra) then return nil end

    local used, limit, currency, exponent

    if type(spend.used) == "table" and spend.used.amount_minor ~= nil then
        used = spend.used.amount_minor
        currency = spend.used.currency
        exponent = spend.used.exponent
    end
    if type(spend.limit) == "table" and spend.limit.amount_minor ~= nil then
        limit = spend.limit.amount_minor
        currency = currency or spend.limit.currency
        exponent = exponent or spend.limit.exponent
    end
    if used == nil then used = extra.used_credits end
    if limit == nil then limit = extra.monthly_limit end
    if used == nil and limit == nil then return nil end

    used = used or 0
    currency = currency or extra.currency or "USD"
    exponent = exponent or extra.decimal_places or 2

    local remaining = (limit and limit > 0) and math.max(0, limit - used) or nil
    local resetsAt = nextMonthStartEpoch()
    local workdays = workdaysRemaining(resetsAt)
    local today, todaySince = todaySpend(used)

    -- The day's ration is what is left spread evenly over the workdays that
    -- are left, today included. Today's spend against that ration is the
    -- velocity: 100% is exactly on pace to finish the budget as the month
    -- ends, 150% is half again that fast.
    local ration, dayPct
    if remaining and workdays > 0 then
        ration = remaining / workdays
        if ration > 0 then
            dayPct = today / ration * 100.0
        end
    end

    return {
        used = used,
        limit = limit,
        remaining = remaining,
        currency = currency,
        exponent = exponent,
        resetsAt = resetsAt,
        workdays = workdays,
        today = today,
        todaySince = todaySince,
        ration = ration,
        dayPct = dayPct,
    }
end

-- ---------------------------------------------------------------------------
-- State snapshot
-- ---------------------------------------------------------------------------

-- The title and icon track the session window, and read it from limits[] first
-- for the same reason the menu does. Sourcing them from five_hour alone would
-- leave the title and icon dead on any payload that reports the session only
-- through limits[], while the dropdown carried on working.
--
-- An org on usage-based billing gets neither: five_hour is null, every
-- seven_day* key is null, and limits[] is an empty array, because there is no
-- fixed session window to report at all. What such a payload does carry is
-- spend.percent, so that becomes the number in the title and on the Stream
-- Deck key once the fixed-window sources have both come up empty.
local function sessionUtilization(data)
    if type(data) ~= "table" then return nil end

    if type(data.limits) == "table" then
        for _, entry in ipairs(data.limits) do
            if type(entry) == "table" and entry.percent
                and (entry.kind == "session" or entry.group == "session") then
                return entry.percent
            end
        end
    end

    if type(data.five_hour) == "table" then
        return data.five_hour.utilization
    end

    if type(data.spend) == "table" and type(data.spend.percent) == "number" then
        return data.spend.percent
    end

    return nil
end

-- The one place the display string is decided, so every surface agrees on what
-- "stale" and "unknown" look like.
--
-- A failed refresh keeps the last good reading rather than blanking it: during a
-- rate limit the number is minutes stale, which is far more useful than "--". The
-- asterisk marks it as stale so a persistent failure cannot masquerade as a live
-- value, and each surface explains the reason in its own way.
--
-- Before the first lookup finishes there is no answer about credentials yet, so
-- "?" — which means there are none — would be a lie for as long as the Keychain
-- takes. That gap reads "..." on every surface.
--
-- Today's velocity and the plain monthly/session percentage are on different
-- scales — 100% is unremarkable for velocity but alarming for a session
-- window — so both are shown side by side ("62/11%") rather than picking one,
-- with the velocity first since it is what the eye level reacts to.
local function displayText(dayPct, monthPct)
    local text
    if dayPct and monthPct then
        text = string.format("%.0f/%.0f%%", dayPct, monthPct)
    elseif dayPct then
        text = string.format("%.0f%%", dayPct)
    elseif monthPct then
        text = string.format("%.0f%%", monthPct)
    end

    if text then
        if lastError then
            return text .. "*"
        end
        return text
    end
    if not credentialsChecked then return "..." end
    if not credentials then return "?" end
    return "--"
end

--- ClaudeUsage.monitor.state() -> table
--- Function
--- Snapshot of the current usage state.
---
--- utilization (percentage driving the compact surfaces, or nil), level (1-5
--- eye level), text (the display string), usageData (last decoded payload or
--- nil), fetchedAt (os.time of that payload), error (last error string or
--- nil), retryIn (seconds until the backoff gate opens, or nil),
--- hasCredentials, plan (subscription type or nil), and monthly (today's
--- spend and velocity against the usage-credit budget, or nil on a
--- fixed-window plan with no such budget — see monthlyBudget()).
---
--- text shows both today's velocity (monthly.dayPct) and the plain
--- session/monthly percentage when both exist, e.g. "62/11%"; it falls back
--- to whichever one exists on a fixed-window plan, or before there is a full
--- day of readings to derive a ration from. level reacts to the velocity
--- when there is one, since that moves same-day where the plain percentage
--- barely does; otherwise it reacts to the plain percentage as before. The
--- dropdown menu is built from usageData/monthly directly and always shows
--- the plain percentages alongside the velocity, regardless of this pairing.
---
--- The credentials table itself is deliberately not exposed: it holds the OAuth
--- access token, and this snapshot is handed to every subscriber.
function M.state()
    local monthly = monthlyBudget(usageData)
    local monthPct = sessionUtilization(usageData)
    local dayPct = monthly and monthly.dayPct
    local level = dayPct and clawd.levelForVelocity(dayPct) or clawd.levelFor(monthPct)

    return {
        utilization = dayPct or monthPct,
        level = level,
        text = displayText(dayPct, monthPct),
        usageData = usageData,
        fetchedAt = usageFetchedAt,
        error = lastError,
        retryIn = retryWaitRemaining(),
        hasCredentials = credentials ~= nil,
        plan = credentials and credentials.subscriptionType or nil,
        monthly = monthly,
    }
end

-- ---------------------------------------------------------------------------
-- Subscribers
-- ---------------------------------------------------------------------------

--- ClaudeUsage.monitor.subscribe(fn) -> token
--- Function
--- Register a function to be called with a state snapshot on every state change.
function M.subscribe(fn)
    assert(type(fn) == "function", "subscribe expects a function")
    table.insert(subscribers, fn)
    -- Hand over the current state immediately so a late subscriber paints itself
    -- now rather than staying blank until the next poll.
    local ok, err = pcall(fn, M.state())
    if not ok then
        hs.printf("[ClaudeUsage] subscriber error: %s", tostring(err))
    end
    return fn
end

--- ClaudeUsage.monitor.unsubscribe(token) -> boolean
--- Function
--- Remove a subscriber previously registered with subscribe().
function M.unsubscribe(token)
    for i, fn in ipairs(subscribers) do
        if fn == token then
            table.remove(subscribers, i)
            return true
        end
    end
    return false
end

-- Fan the new state out to every surface. A throwing subscriber is logged and
-- skipped: one broken renderer must not stop the others from updating, and must
-- not leave the poll loop half-applied.
local function publish()
    local state = M.state()
    -- Saving here rather than at each call site means persisted state can never
    -- drift from displayed state. It does mean a redundant write on gated ticks
    -- that changed nothing, which is a cheap plist write every refreshInterval.
    saveState()
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, state)
        if not ok then
            hs.printf("[ClaudeUsage] subscriber error: %s", tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------------
-- API fetch
-- ---------------------------------------------------------------------------

--- ClaudeUsage.monitor.fetchUsage()
--- Function
--- Refresh the usage reading now, unless the backoff gate is closed.
function M.fetchUsage()
    -- The poll timer keeps its steady tick and this gate absorbs the backoff, so
    -- no timer has to be torn down and rebuilt at a new interval. Ticks that fall
    -- inside a backoff window make no request; they only refresh the countdown.
    if retryWaitRemaining() then
        publish()
        return
    end

    readCredentials(function(creds, err)
        credentials = creds
        credentialsChecked = true
        if not creds then
            lastError = err
            usageData = nil
            usageRaw = nil
            usageFetchedAt = nil
            clearRetry()
            publish()
            return
        end

        local url = "https://api.anthropic.com/api/oauth/usage"
        local headers = {
            ["Authorization"] = "Bearer " .. creds.accessToken,
            ["anthropic-beta"] = "oauth-2025-04-20",
        }

        hs.http.asyncGet(url, headers, function(status, body, responseHeaders)
            -- Rate limits and server-side faults are the retryable cases; a
            -- negative status is how hs.http reports a transport failure. Client
            -- errors such as 401 are left to the steady tick, since backing off
            -- from them buys nothing.
            if status == 429 or status >= 500 or status < 0 then
                scheduleRetry(parseRetryAfter(responseHeaders))
                lastError = (status == 429)
                    and "Rate limited (HTTP 429)"
                    or ("HTTP " .. tostring(status))
                -- usageData is deliberately left in place; see displayText.
                publish()
                return
            end

            if status ~= 200 then
                clearRetry()
                lastError = "HTTP " .. tostring(status)
                publish()
                return
            end

            local ok, parsed = pcall(hs.json.decode, body)
            if not ok or not parsed then
                clearRetry()
                lastError = "Invalid JSON response"
                publish()
                return
            end

            clearRetry()
            lastError = nil
            usageData = parsed
            usageRaw = body
            usageFetchedAt = os.time()
            publish()
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- ClaudeUsage.monitor.start()
--- Function
--- Restore persisted state and begin polling. Repeat calls are ignored, since a
--- second timer would double the request rate against the shared quota.
function M.start()
    if timer then return end

    loadState()

    -- A reload holding a reading younger than one poll interval needs no request:
    -- paint what we already have and let the timer take it from there. fetchUsage
    -- would also no-op behind a restored backoff gate, but skipping it outright is
    -- what keeps repeated reloads from each costing a request.
    local cacheAge = usageFetchedAt and (os.time() - usageFetchedAt)
    if usageData and cacheAge and cacheAge < cfg.refreshInterval then
        publish()
    else
        M.fetchUsage()
    end

    timer = hs.timer.doEvery(cfg.refreshInterval, M.fetchUsage)
end

--- ClaudeUsage.monitor.stop()
--- Function
--- Stop polling and forget the in-memory reading. Persisted state is left alone;
--- clearPersistedState() is what discards that.
function M.stop()
    if timer then
        timer:stop()
        timer = nil
    end
    usageData = nil
    usageRaw = nil
    usageFetchedAt = nil
    lastError = nil
    credentials = nil
    credentialsChecked = false
    clearRetry()
end

return M

end
