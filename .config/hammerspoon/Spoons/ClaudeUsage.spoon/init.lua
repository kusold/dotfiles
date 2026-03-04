--- === ClaudeUsage ===
---
--- Menubar item showing Claude Code session usage with animated Clawd mascot.
--- Eyes change expression based on rate limit utilization (anime-style).

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ClaudeUsage"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- ClaudeUsage.refreshInterval
--- Variable
--- How often (in seconds) to refresh usage data. Default 30.
obj.refreshInterval = 30

--- ClaudeUsage.credentialsPath
--- Variable
--- Path to Claude credentials file.
obj.credentialsPath = os.getenv("HOME") .. "/.claude/.credentials.json"

-- Internal state
local menubar = nil
local timer = nil
local usageData = nil
local lastError = nil
local credentials = nil
local iconCache = {}

-- ---------------------------------------------------------------------------
-- Clawd pixel art renderer
-- ---------------------------------------------------------------------------

-- Colors matched from the Clawd mascot
local BODY  = {red=0.76, green=0.48, blue=0.35, alpha=1}  -- warm terracotta
local DARK  = {red=0.36, green=0.22, blue=0.16, alpha=1}  -- dark brown (eyes/nose)
local CREAM = {red=0.95, green=0.90, blue=0.85, alpha=1}  -- eye whites (dizzy/panic)
local SWEAT = {red=0.55, green=0.78, blue=0.98, alpha=1}  -- sweat drop blue
local RED   = {red=0.85, green=0.18, blue=0.18, alpha=1}  -- panic red eyes

-- Pixel size (each game-pixel = 2 canvas points)
local PX = 2

-- Body pixel map: 11 cols x 8 rows
-- 0=empty, 1=body
-- Clawd is a flat rectangle block with arms poking out the sides
local BODY_MAP = {
    {0,1,1,1,1,1,1,1,1,1,0},  -- row 0: flat top (9 wide)
    {1,1,1,1,1,1,1,1,1,1,1},  -- row 1: arms extend (11 wide), eye row top
    {1,1,1,1,1,1,1,1,1,1,1},  -- row 2: arms extend (11 wide), eye row mid
    {1,1,1,1,1,1,1,1,1,1,1},  -- row 3: arms extend (11 wide), eye row bottom
    {0,1,1,1,1,1,1,1,1,1,0},  -- row 4: body (9 wide)
    {0,1,1,1,1,1,1,1,1,1,0},  -- row 5: flat bottom (9 wide)
    {0,0,1,0,1,0,1,0,1,0,0},  -- row 6: four little legs
    {0,0,1,0,1,0,1,0,1,0,0},  -- row 7: four little legs
}

-- Eye positions (top-left corner of each 2x3 eye)
local LEFT_EYE  = {3, 1}   -- cols 3-4, rows 1-3
local RIGHT_EYE = {6, 1}   -- cols 6-7, rows 1-3

-- Eye expression overlays for each level
-- Each entry: {col, row, color_table}
-- Drawn ON TOP of body pixels
local function getEyeOverlay(level)
    local le, re = LEFT_EYE, RIGHT_EYE  -- shortcuts

    -- Eyes are 2 wide x 3 tall. Rows: top=le[2], mid=le[2]+1, bot=le[2]+2
    local overlays = {
        -- Level 1 (0-40%): Normal - full 2x3 dark eyes
        {
            {le[1],le[2],DARK}, {le[1]+1,le[2],DARK},
            {le[1],le[2]+1,DARK}, {le[1]+1,le[2]+1,DARK},
            {le[1],le[2]+2,DARK}, {le[1]+1,le[2]+2,DARK},
            {re[1],re[2],DARK}, {re[1]+1,re[2],DARK},
            {re[1],re[2]+1,DARK}, {re[1]+1,re[2]+1,DARK},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,DARK},
        },
        -- Level 2 (40-65%): Normal eyes + sweat drop
        {
            {le[1],le[2],DARK}, {le[1]+1,le[2],DARK},
            {le[1],le[2]+1,DARK}, {le[1]+1,le[2]+1,DARK},
            {le[1],le[2]+2,DARK}, {le[1]+1,le[2]+2,DARK},
            {re[1],re[2],DARK}, {re[1]+1,re[2],DARK},
            {re[1],re[2]+1,DARK}, {re[1]+1,re[2]+1,DARK},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,DARK},
            {9, 0, SWEAT},  -- sweat drop
        },
        -- Level 3 (65-85%): Half-lidded (bottom 2 rows only) + sweat
        {
            {le[1],le[2]+1,DARK}, {le[1]+1,le[2]+1,DARK},
            {le[1],le[2]+2,DARK}, {le[1]+1,le[2]+2,DARK},
            {re[1],re[2]+1,DARK}, {re[1]+1,re[2]+1,DARK},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,DARK},
            {9, 0, SWEAT},
        },
        -- Level 4 (85-95%): X eyes (3 tall gives proper X) + big sweat
        {
            {le[1],le[2],DARK},   {le[1]+1,le[2],CREAM},   -- left X
            {le[1],le[2]+1,CREAM},{le[1]+1,le[2]+1,CREAM},
            {le[1],le[2]+2,CREAM},{le[1]+1,le[2]+2,DARK},
            {re[1],re[2],CREAM},  {re[1]+1,re[2],DARK},    -- right X (mirrored)
            {re[1],re[2]+1,CREAM},{re[1]+1,re[2]+1,CREAM},
            {re[1],re[2]+2,DARK}, {re[1]+1,re[2]+2,CREAM},
            {9, 0, SWEAT}, {9, 1, SWEAT},
        },
        -- Level 5 (95-100%): Red panic eyes
        {
            {le[1],le[2],RED}, {le[1]+1,le[2],RED},
            {le[1],le[2]+1,RED}, {le[1]+1,le[2]+1,RED},
            {le[1],le[2]+2,RED}, {le[1]+1,le[2]+2,RED},
            {re[1],re[2],RED}, {re[1]+1,re[2],RED},
            {re[1],re[2]+1,RED}, {re[1]+1,re[2]+1,RED},
            {re[1],re[2]+2,RED}, {re[1]+1,re[2]+2,RED},
        },
    }
    return overlays[level]
end

local function getEyeLevel(utilization)
    if not utilization then return 1 end
    if utilization < 40 then return 1 end
    if utilization < 65 then return 2 end
    if utilization < 85 then return 3 end
    if utilization < 95 then return 4 end
    return 5
end

local function drawClawdIcon(level)
    local cols, rows = 11, 8
    local w, h = cols * PX, rows * PX  -- 22 x 16 points

    local elements = {}

    -- Draw body from pixel map
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local val = BODY_MAP[row + 1][col + 1]
            if val > 0 then
                table.insert(elements, {
                    type = "rectangle",
                    frame = {x = col * PX, y = row * PX, w = PX, h = PX},
                    fillColor = val == 1 and BODY or DARK,
                    action = "fill",
                })
            end
        end
    end

    -- Draw eye expression overlay
    local overlay = getEyeOverlay(level)
    for _, p in ipairs(overlay) do
        table.insert(elements, {
            type = "rectangle",
            frame = {x = p[1] * PX, y = p[2] * PX, w = PX, h = PX},
            fillColor = p[3],
            action = "fill",
        })
    end

    local c = hs.canvas.new({x = 0, y = 0, w = w, h = h})
    c:appendElements(elements)
    local img = c:imageFromCanvas()
    c:delete()
    return img
end

local function initIconCache()
    for level = 1, 5 do
        iconCache[level] = drawClawdIcon(level)
    end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function readCredentials()
    local path = obj.credentialsPath
    local f = io.open(path, "r")
    if not f then
        return nil, "Credentials file not found"
    end
    local raw = f:read("*a")
    f:close()

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

local function parseISO8601(str)
    if not str then return nil end
    local y, m, d, H, M, S = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return nil end
    return os.time({
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(H), min = tonumber(M), sec = tonumber(S),
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

-- ---------------------------------------------------------------------------
-- Menubar update
-- ---------------------------------------------------------------------------

local function updateMenubar()
    if not menubar then return end

    local utilization = nil
    local titleText = "?"

    if not credentials then
        titleText = "?"
    elseif lastError then
        titleText = "--"
    elseif usageData and usageData.five_hour then
        utilization = usageData.five_hour.utilization or 0
        titleText = string.format("%.0f%%", utilization)
    else
        titleText = "--"
    end

    local level = getEyeLevel(utilization)
    if iconCache[level] then
        menubar:setIcon(iconCache[level], false)
    end
    menubar:setTitle(titleText)
end

-- ---------------------------------------------------------------------------
-- Menu builder (called dynamically on each click)
-- ---------------------------------------------------------------------------

local function buildMenu()
    local items = {}

    if not credentials then
        table.insert(items, { title = "No credentials found", disabled = true })
        table.insert(items, { title = obj.credentialsPath, disabled = true })
        table.insert(items, { title = "-" })
        table.insert(items, { title = "Refresh Now", fn = function() obj:fetchUsage() end })
        return items
    end

    if lastError then
        table.insert(items, { title = "Error: " .. lastError, disabled = true })
        table.insert(items, { title = "-" })
    end

    if usageData then
        if usageData.five_hour then
            local fh = usageData.five_hour
            local line = "Session (5h): " .. formatPercent(fh.utilization)
            local countdown = formatCountdown(parseISO8601(fh.resets_at))
            if countdown then
                line = line .. "  (resets in " .. countdown .. ")"
            end
            table.insert(items, { title = line, disabled = true })
        end

        if usageData.seven_day and usageData.seven_day.utilization then
            local sd = usageData.seven_day
            local line = "Weekly (7d): " .. formatPercent(sd.utilization)
            local countdown = formatCountdown(parseISO8601(sd.resets_at))
            if countdown then
                line = line .. "  (resets in " .. countdown .. ")"
            end
            table.insert(items, { title = line, disabled = true })
        end

        if usageData.seven_day_opus and usageData.seven_day_opus.utilization then
            local line = "Weekly Opus: " .. formatPercent(usageData.seven_day_opus.utilization)
            table.insert(items, { title = line, disabled = true })
        end

        if usageData.seven_day_sonnet and usageData.seven_day_sonnet.utilization then
            local line = "Weekly Sonnet: " .. formatPercent(usageData.seven_day_sonnet.utilization)
            table.insert(items, { title = line, disabled = true })
        end

        if usageData.extra_usage and usageData.extra_usage.total_spend then
            local spend = usageData.extra_usage.total_spend
            if spend > 0 then
                table.insert(items, { title = string.format("Extra spend: $%.2f", spend), disabled = true })
            end
        end
    end

    if credentials and credentials.planType then
        table.insert(items, { title = "-" })
        table.insert(items, { title = "Plan: " .. credentials.planType, disabled = true })
    end

    table.insert(items, { title = "-" })
    table.insert(items, { title = "Refresh Now", fn = function() obj:fetchUsage() end })

    return items
end

-- ---------------------------------------------------------------------------
-- API fetch
-- ---------------------------------------------------------------------------

function obj:fetchUsage()
    local creds, err = readCredentials()
    credentials = creds
    if not creds then
        lastError = err
        usageData = nil
        updateMenubar()
        return
    end

    local url = "https://api.anthropic.com/api/oauth/usage"
    local headers = {
        ["Authorization"] = "Bearer " .. creds.accessToken,
        ["anthropic-beta"] = "oauth-2025-04-20",
    }

    hs.http.asyncGet(url, headers, function(status, body, _responseHeaders)
        if status ~= 200 then
            lastError = "HTTP " .. tostring(status)
            usageData = nil
            updateMenubar()
            return
        end

        local ok, parsed = pcall(hs.json.decode, body)
        if not ok or not parsed then
            lastError = "Invalid JSON response"
            usageData = nil
            updateMenubar()
            return
        end

        lastError = nil
        usageData = parsed
        updateMenubar()
    end)
end

-- ---------------------------------------------------------------------------
-- Spoon lifecycle
-- ---------------------------------------------------------------------------

--- ClaudeUsage:start()
--- Method
--- Start the menubar item and begin polling.
--- Only creates the menubar if credentials exist; otherwise watches for
--- the file to appear and starts automatically.
function obj:start()
    local path = self.credentialsPath
    local f = io.open(path, "r")
    if f then
        f:close()
    else
        -- No credentials yet — watch for the file to appear
        self._pathwatcher = hs.pathwatcher.new(
            path:match("(.*/)")  ,  -- watch the parent directory
            function(paths, flagTables)
                for _, p in ipairs(paths) do
                    if p == path then
                        local check = io.open(path, "r")
                        if check then
                            check:close()
                            self._pathwatcher:stop()
                            self._pathwatcher = nil
                            self:start()  -- retry now that file exists
                            return
                        end
                    end
                end
            end
        ):start()
        return self
    end

    initIconCache()

    menubar = hs.menubar.new()
    menubar:setMenu(buildMenu)
    if iconCache[1] then
        menubar:setIcon(iconCache[1], false)
    end
    menubar:setTitle("...")

    self:fetchUsage()

    timer = hs.timer.doEvery(self.refreshInterval, function()
        self:fetchUsage()
    end)

    return self
end

--- ClaudeUsage:stop()
--- Method
--- Remove the menubar item and stop polling.
function obj:stop()
    if self._pathwatcher then
        self._pathwatcher:stop()
        self._pathwatcher = nil
    end
    if timer then
        timer:stop()
        timer = nil
    end
    if menubar then
        menubar:delete()
        menubar = nil
    end
    usageData = nil
    lastError = nil
    credentials = nil
    return self
end

return obj
