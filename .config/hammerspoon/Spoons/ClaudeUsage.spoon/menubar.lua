--- === ClaudeUsage.menubar ===
---
--- The menubar surface: Clawd plus the session percentage in the title, and a
--- dropdown breaking the payload down per limit window.
---
--- It subscribes to the monitor and never fetches. The dropdown is built on each
--- click from a fresh monitor.state(), so its countdowns and "retrying in" line
--- are current at the moment it opens rather than as of the last poll.

return function(cfg, monitor, clawd)

local M = {}

local bar = nil
local token = nil

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

local function parseISO8601(str)
    if not str then return nil end
    local y, m, d, H, M_, S = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return nil end
    return os.time({
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(H), min = tonumber(M_), sec = tonumber(S),
        isdst = false,
    })
end

local function utcOffset()
    local now = os.time()
    local utc = os.time(os.date("!*t", now))
    return os.difftime(now, utc)
end

local function formatCountdown(resetUtcEpoch)
    if not resetUtcEpoch then return nil end
    local nowUtc = os.time() - utcOffset()
    local diff = resetUtcEpoch - nowUtc
    if diff <= 0 then return "now" end
    local hours = math.floor(diff / 3600)
    local mins = math.floor((diff % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", mins)
end

local function formatPercent(val)
    if not val then return "N/A" end
    return string.format("%.0f%%", val)
end

local function formatDuration(seconds)
    if not seconds or seconds <= 0 then return nil end
    if seconds < 60 then
        return string.format("%ds", seconds)
    end
    local mins = math.floor(seconds / 60)
    if mins < 60 then
        return string.format("%dm", mins)
    end
    return string.format("%dh %dm", math.floor(mins / 60), mins % 60)
end

local CURRENCY_SYMBOLS = { USD = "$", EUR = "€", GBP = "£" }

local function currencyPrefix(currency)
    if not currency or currency == "" then return "" end
    return CURRENCY_SYMBOLS[currency] or (currency .. " ")
end

-- Money tables under `spend` carry their own scale: amount_minor is an integer
-- in the currency's smallest unit and exponent says how far to shift it.
local function formatMoneyObject(m)
    if type(m) ~= "table" or not m.amount_minor then return nil end
    local exponent = m.exponent or 2
    return string.format("%s%." .. exponent .. "f",
        currencyPrefix(m.currency), m.amount_minor / (10 ^ exponent))
end

-- `extra_usage` pairs used_credits/monthly_limit with decimal_places rather
-- than an *_minor suffix, which reads as already-scaled major units — but
-- both are minor-unit amounts: dividing by 10^decimal_places is what lines
-- them up with spend.used/spend.limit's amount_minor for the same figures.
local function formatMinorAmount(value, currency, decimalPlaces)
    if not value then return nil end
    local exponent = decimalPlaces or 2
    return string.format("%s%." .. exponent .. "f",
        currencyPrefix(currency), value / (10 ^ exponent))
end

local LIMIT_LABELS = {
    session = "Session (5h)",
    weekly = "Weekly (7d)",
    weekly_scoped = "Weekly",
}

-- Entries in limits[] are self-describing, so an unrecognised kind still renders
-- legibly rather than being dropped when the API grows a new one.
local function limitLabel(entry)
    local label = LIMIT_LABELS[entry.kind]
    if not label then
        local pretty = tostring(entry.kind or "Limit"):gsub("_", " ")
        label = pretty:sub(1, 1):upper() .. pretty:sub(2)
    end

    local scope = entry.scope or {}
    local qualifiers = {}
    if type(scope.model) == "table" and scope.model.display_name then
        table.insert(qualifiers, scope.model.display_name)
    end
    if scope.surface then
        table.insert(qualifiers, tostring(scope.surface))
    end
    if #qualifiers > 0 then
        label = label .. " · " .. table.concat(qualifiers, "/")
    end
    return label
end

-- ---------------------------------------------------------------------------
-- Menu builder (called dynamically on each click)
-- ---------------------------------------------------------------------------

-- Separators only mean something between two populated sections, and which
-- sections populate depends on what the payload happened to carry. Deciding
-- here, against what has actually been inserted, avoids the adjacent dividers
-- that per-section table.insert calls produce whenever a section comes up empty.
local function addSeparator(items)
    if #items > 0 and items[#items].title ~= "-" then
        table.insert(items, { title = "-" })
    end
end

local function addRow(items, line)
    table.insert(items, { title = line, disabled = true })
end

local function addRefreshRow(items)
    table.insert(items, { title = "Refresh Now", fn = monitor.fetchUsage })
end

local function addLimitRows(items, limits)
    for _, entry in ipairs(limits) do
        if type(entry) == "table" and entry.percent then
            local line = limitLabel(entry) .. ": " .. formatPercent(entry.percent)
            local countdown = formatCountdown(parseISO8601(entry.resets_at))
            if countdown then
                line = line .. "  (resets in " .. countdown .. ")"
            end
            if entry.severity and entry.severity ~= "normal" then
                line = line .. "  [" .. tostring(entry.severity) .. "]"
            end
            if entry.is_active == false then
                line = line .. "  (inactive)"
            end
            addRow(items, line)
        end
    end
end

-- Fallback for payloads with no limits[]: the fixed per-window keys.
local function addNamedWindowRows(items, data)
    if data.five_hour then
        local line = "Session (5h): " .. formatPercent(data.five_hour.utilization)
        local countdown = formatCountdown(parseISO8601(data.five_hour.resets_at))
        if countdown then
            line = line .. "  (resets in " .. countdown .. ")"
        end
        addRow(items, line)
    end

    if data.seven_day and data.seven_day.utilization then
        local line = "Weekly (7d): " .. formatPercent(data.seven_day.utilization)
        local countdown = formatCountdown(parseISO8601(data.seven_day.resets_at))
        if countdown then
            line = line .. "  (resets in " .. countdown .. ")"
        end
        addRow(items, line)
    end

    if data.seven_day_opus and data.seven_day_opus.utilization then
        addRow(items, "Weekly Opus: " .. formatPercent(data.seven_day_opus.utilization))
    end

    if data.seven_day_sonnet and data.seven_day_sonnet.utilization then
        addRow(items, "Weekly Sonnet: " .. formatPercent(data.seven_day_sonnet.utilization))
    end
end

local function addSpendRows(items, spend)
    local used = formatMoneyObject(spend.used)
    if used then
        local line = "Credit spend: " .. used
        local limit = formatMoneyObject(spend.limit)
        if limit and spend.limit.amount_minor > 0 then
            line = line .. " of " .. limit
        end
        if spend.percent then
            line = line .. "  (" .. formatPercent(spend.percent) .. ")"
        end
        if spend.severity and spend.severity ~= "normal" then
            line = line .. "  [" .. tostring(spend.severity) .. "]"
        end
        addRow(items, line)
    end

    local balance = formatMoneyObject(spend.balance)
    if balance then
        addRow(items, "Credit balance: " .. balance)
    end

    if spend.enabled == false then
        local line = "Credits disabled"
        if spend.disabled_reason then
            line = line .. ": " .. tostring(spend.disabled_reason)
        end
        addRow(items, line)
    end
end

-- Unlike entry.resets_at elsewhere in this file, monitor.lua's monthly.resetsAt
-- is already a true epoch (comparable directly to os.time()), not a UTC
-- timestamp still waiting on parseISO8601's local-timezone correction. So this
-- takes the plain difference rather than routing through formatCountdown,
-- which would apply that correction a second time.
local function formatBudgetCountdown(resetEpoch)
    if not resetEpoch then return nil end
    local diff = resetEpoch - os.time()
    if diff <= 0 then return "now" end
    local hours = math.floor(diff / 3600)
    local mins = math.floor((diff % 3600) / 60)
    -- Unlike the file's other duration formatters, this one routinely spans
    -- weeks (a monthly credit reset, not a 5h/7d rate-limit window), so it
    -- breaks out days rather than printing triple-digit hours.
    if hours >= 24 then
        return string.format("%dd %dh", math.floor(hours / 24), hours % 24)
    end
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", mins)
end

-- Today's spend against the ration, and the workdays left before the
-- usage-credit budget resets. `monthly` is monitor.state().monthly — nil on a
-- fixed-window plan with no monthly credit budget to pace against.
local function addBudgetVelocityRows(items, monthly)
    if not monthly then return end

    if monthly.remaining then
        addRow(items, "Remaining this cycle: " ..
            (formatMinorAmount(monthly.remaining, monthly.currency, monthly.exponent) or "N/A"))
    end

    local since = monthly.todaySince and os.date("%H:%M", monthly.todaySince)
    addRow(items, "Today: " ..
        (formatMinorAmount(monthly.today, monthly.currency, monthly.exponent) or "N/A") ..
        (since and ("  (since " .. since .. ")") or ""))

    if monthly.ration then
        addRow(items, "Ration: " ..
            (formatMinorAmount(monthly.ration, monthly.currency, monthly.exponent) or "N/A") ..
            "/workday  (" .. monthly.workdays .. " left)")
    end

    if monthly.dayPct then
        addRow(items, string.format("Velocity: %.0f%% of today's ration", monthly.dayPct))
    end

    local resetIn = formatBudgetCountdown(monthly.resetsAt)
    if resetIn then
        addRow(items, "Resets in " .. resetIn)
    end
end

local function addExtraUsageRows(items, extra)
    local used = formatMinorAmount(extra.used_credits, extra.currency, extra.decimal_places)
    if used then
        local line = "Extra usage: " .. used
        if extra.monthly_limit and extra.monthly_limit > 0 then
            line = line .. " of " ..
                formatMinorAmount(extra.monthly_limit, extra.currency, extra.decimal_places) .. "/mo"
        end
        if extra.utilization then
            line = line .. "  (" .. formatPercent(extra.utilization) .. ")"
        end
        addRow(items, line)
    end

    if extra.spend_limit_reached then
        addRow(items, "Extra usage limit reached")
    end

    if extra.is_enabled == false then
        local line = "Extra usage disabled"
        if extra.disabled_reason then
            line = line .. ": " .. tostring(extra.disabled_reason)
        end
        addRow(items, line)
    end
end

local function buildMenu()
    local state = monitor.state()
    local items = {}

    if not state.hasCredentials then
        addRow(items, state.error or "No credentials found")
        addRow(items, "Keychain service: " .. cfg.keychainService)
        addSeparator(items)
        addRefreshRow(items)
        return items
    end

    if state.error then
        addRow(items, "Error: " .. state.error)
        local wait = formatDuration(state.retryIn)
        if wait then
            addRow(items, "Retrying in " .. wait)
        end
        if state.fetchedAt then
            local age = formatDuration(os.time() - state.fetchedAt)
            addRow(items, "Showing last reading" .. (age and " from " .. age .. " ago" or ""))
        end
        addSeparator(items)
    end

    local data = state.usageData
    if data then
        -- limits[] is the canonical list: it describes scoped per-model limits
        -- that the fixed window keys cannot express, and it carries weekly
        -- entries even when every seven_day* key is null.
        if type(data.limits) == "table" and #data.limits > 0 then
            addLimitRows(items, data.limits)
        else
            addNamedWindowRows(items, data)
        end

        if type(data.spend) == "table" then
            addSeparator(items)
            addSpendRows(items, data.spend)
        end

        if type(data.extra_usage) == "table" then
            addSeparator(items)
            addExtraUsageRows(items, data.extra_usage)
        end

        if state.monthly then
            addSeparator(items)
            addBudgetVelocityRows(items, state.monthly)
        end
    end

    if state.plan then
        addSeparator(items)
        addRow(items, "Plan: " .. state.plan)
    end

    addSeparator(items)
    addRefreshRow(items)

    return items
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function paint(state)
    if not bar then return end

    local icon = clawd.icon(state.level)
    if icon then
        bar:setIcon(icon, false)
    end
    bar:setTitle(state.text)
end

--- ClaudeUsage.menubar.start()
--- Function
--- Create the menubar item and keep it painted from the monitor.
---
--- The item appears unconditionally: credentials are resolved asynchronously, so
--- until they are available the title reads "..." and the menu reports why.
--- Logging in to Claude Code later needs no restart — the next refresh picks the
--- credentials up.
function M.start()
    if bar then return end

    bar = hs.menubar.new()
    bar:setMenu(buildMenu)
    -- subscribe() calls back immediately, which is what paints the initial icon
    -- and title.
    token = monitor.subscribe(paint)
end

--- ClaudeUsage.menubar.stop()
--- Function
--- Remove the menubar item and stop listening.
function M.stop()
    if token then
        monitor.unsubscribe(token)
        token = nil
    end
    if bar then
        bar:delete()
        bar = nil
    end
end

return M

end
