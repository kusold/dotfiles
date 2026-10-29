--- === MemoryUsage.monitor ===
---
--- The sampler: reads memory in use and memory pressure on a timer, keeps a rolling
--- history of both, and publishes a state snapshot to every subscriber.
---
--- "In use" is Activity Monitor's "Memory Used", so the key and the app it opens agree:
--- app memory (anonymous pages less purgeable ones), plus wired, plus what the
--- compressor occupies. Free, inactive and file-backed cache are left out on purpose —
--- macOS keeps those full by design, and counting them would pin the key near 100%.
---
--- Pressure is the kernel's own verdict on whether that usage is a problem, and is what
--- Activity Monitor colours its pressure graph by. It comes from the
--- kern.memorystatus_vm_pressure_level sysctl, which Hammerspoon has no binding for, so
--- it is read by running sysctl(8) as an hs.task. The sample is taken when that task
--- finishes, not when it starts, so each history entry's usage and pressure are read
--- together.

return function(cfg)

local M = {}

local SYSCTL = "/usr/sbin/sysctl"
local PRESSURE_KEY = "kern.memorystatus_vm_pressure_level"

-- The sysctl reports the dispatch memory-pressure levels, not the kernel's internal
-- ones: DISPATCH_MEMORYPRESSURE_NORMAL, _WARN and _CRITICAL.
local PRESSURE = {[1] = "normal", [2] = "warn", [4] = "critical"}

local timer = nil
local task = nil      -- the sysctl read in flight, if any
local subscribers = {}
local nextToken = 1
local history = {}    -- {fraction = 0-1, pressure = level or nil}, oldest first
local latest = nil    -- {used = bytes, total = bytes, fraction = 0-1}
local pressure = nil  -- "normal", "warn", "critical", or nil when unknown
local lastError = nil

local function sample()
    local ok, vm = pcall(hs.host.vmStat)
    if not ok or type(vm) ~= "table" or not vm.pageSize or not vm.memSize then
        return nil, tostring(vm)
    end

    local app = (vm.anonymousPages or 0) - (vm.pagesPurgeable or 0)
    local pages = app + (vm.pagesWiredDown or 0) + (vm.pagesUsedByVMCompressor or 0)
    local used = pages * vm.pageSize
    local total = vm.memSize
    return {used = used, total = total, fraction = math.max(0, math.min(1, used / total))}
end

--- MemoryUsage.monitor.state() -> table
--- Function
--- Snapshot of memory in use. See MemoryUsage:state() for the fields.
function M.state()
    local copy = {}
    for i, entry in ipairs(history) do
        -- Copied entry by entry, so a subscriber holding on to a snapshot does not see
        -- it shift under them on the next sample.
        copy[i] = {fraction = entry.fraction, pressure = entry.pressure}
    end
    return {
        used = latest and latest.used,
        total = latest and latest.total,
        fraction = latest and latest.fraction,
        pressure = pressure,
        history = copy,
        error = lastError,
    }
end

local function publish()
    local state = M.state()
    for _, fn in pairs(subscribers) do
        local ok, err = pcall(fn, state)
        if not ok then
            hs.printf("[MemoryUsage] subscriber failed: %s", tostring(err))
        end
    end
end

--- MemoryUsage.monitor.subscribe(fn) -> token
--- Function
--- Call fn with a state snapshot after every sample. Returns a token for unsubscribe().
function M.subscribe(fn)
    local token = nextToken
    nextToken = nextToken + 1
    subscribers[token] = fn
    return token
end

--- MemoryUsage.monitor.unsubscribe(token)
--- Function
--- Remove a subscriber registered with subscribe().
function M.unsubscribe(token)
    if token then subscribers[token] = nil end
end

local function record(level)
    pressure = level

    local reading, err = sample()
    if reading then
        latest = reading
        lastError = nil
        table.insert(history, {fraction = reading.fraction, pressure = level})
        while #history > cfg.historyLength do table.remove(history, 1) end
    else
        -- The previous reading and history are kept: a stale graph beats a blank key.
        lastError = err
        hs.printf("[MemoryUsage] sample failed: %s", tostring(err))
    end
    publish()
end

--- MemoryUsage.monitor.refresh()
--- Function
--- Take a sample now and publish it once the pressure read comes back.
---
--- A refresh while a read is still in flight is dropped rather than queued: the one in
--- flight is about to publish a sample just as current.
function M.refresh()
    if task and task:isRunning() then return end

    task = hs.task.new(SYSCTL, function(code, out, errOut)
        task = nil
        local level = nil
        if code == 0 then
            level = PRESSURE[tonumber(out and out:match("%d+"))]
        end
        if not level then
            -- Usage is still sampled without it; only the colour goes to unknown.
            hs.printf("[MemoryUsage] pressure read failed (exit %s): %s %s",
                      tostring(code), tostring(out), tostring(errOut))
        end
        record(level)
    end, {"-n", PRESSURE_KEY})

    if not task:start() then
        task = nil
        record(nil)
    end
end

--- MemoryUsage.monitor.start()
--- Function
--- Begin sampling. Calling it again restarts the timer at the current interval.
function M.start()
    if timer then timer:stop() end
    M.refresh()
    timer = hs.timer.doEvery(cfg.sampleInterval, M.refresh)
end

--- MemoryUsage.monitor.stop()
--- Function
--- Stop sampling. The history is kept, so a restart continues the graph.
function M.stop()
    if timer then
        timer:stop()
        timer = nil
    end
end

return M

end
