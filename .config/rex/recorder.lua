-- Records the foreground program of every Rex terminal block, so that a
-- restored terminal (same block id, fresh shell, same directory) can
-- resume the coding agent that was running in it before a restart.
-- The agent self-report hooks write exact session ids to sessions.tsv
-- beside this state.
--
-- Runs as:  rex do ~/.config/rex/recorder.lua --all
-- Started by ~/.config/rex/init.lua at server start (best effort) and by
-- ~/.config/rex/ensure-recorder.sh from every terminal shell.

local cache = (os.getenv("XDG_CACHE_HOME") or os.getenv("HOME") .. "/.cache")
    .. "/rex-agent-resume"
local json_file = cache .. "/recorder.json"
local pid_file = cache .. "/recorder.pid"

local TERMINAL = "com.superlogical.terminal"

local function read_state()
    local fh = io.open(json_file, "r")
    if not fh then return {} end
    local ok, t = pcall(rex.json.decode, fh:read("*a"))
    fh:close()
    if ok and type(t) == "table" then return t end
    return {}
end

local state = read_state()
for k, v in pairs(state) do
    -- Drop the resume markers and metadata an earlier version wrote: a
    -- persisted marker would block every future resume of its block.
    if type(v) ~= "table" or k == "_meta" then state[k] = nil end
end
local dirty = false

local function write(path, contents)
    local tmp = path .. ".tmp"
    local fh = io.open(tmp, "w")
    if not fh then return end
    fh:write(contents)
    fh:close()
    os.rename(tmp, path)
end

local function flush()
    local text = rex.json.encode(state)
    if text then write(json_file, text) end
    dirty = false
end

-- Bootstrap the cache directory and tell ~/.config/rex/ensure-recorder.sh
-- this recorder is alive, however it was started: at server start no
-- shell or hook has made the directory yet, and without the pidfile
-- every restored shell would spawn its own duplicate recorder. A
-- rex.exec child's parent is the rex do process itself, so its PPID is
-- this script's pid.
rex.exec({ "mkdir", "-p", cache })
local pid = rex.exec({ "sh", "-c", "echo $PPID" })
if pid and pid.ok then
    local p = pid.stdout and pid.stdout:gsub("%s", "")
    if p and p ~= "" then write(pid_file, p .. "\n") end
end

-- Match a foreground process to an agent name. Node-shimmed CLIs report
-- as env or node, so every name field is checked, by basename first.
-- Returns "" for a plain foreground (shell, vim, ...) meaning: no resume.
local function classify(f)
    if not f then return nil end
    local fields = { f.name, f.argv0, f.invoked_path, f.path }
    for _, s in ipairs(fields) do
        if s then
            local b = s:match("[^/]+$") or s
            if b == "pi" then return "pi" end
            if b:sub(1, 6) == "claude" then return "claude" end
            if b:sub(1, 5) == "codex" then return "codex" end
        end
    end
    return ""
end

-- Program Status Protocol records name the app outright, which beats
-- path matching when the agent supports it.
local APPS = { ["claude-code"] = "claude", ["codex"] = "codex", ["pi"] = "pi" }
-- Only states tied to a live process say an agent has the foreground:
-- done and error records survive process exit by design, and an agent
-- reporting done as it exits must not re-classify a block the
-- foreground has already given back to the shell.
local LIVE = { idle = true, working = true, blocked = true }

rex.on("terminal.program_status_changed", function(ctx, ev)
    local rec = ev.record
    local app = rec and rec.app and APPS[rec.app]
    if not app then return end
    if not LIVE[rec.state or ""] then return end
    local e = state[ctx.block_id] or {}
    -- A live report outranks path matching; the generation on record
    -- stays, so a restore after a crash is still detected by it.
    e.agent, e.ts = app, os.time()
    state[ctx.block_id] = e
    dirty = true
end)

-- Exact refs from the agents' self-report hooks. Re-read before every
-- resume: this recorder outlives the sessions the hooks report.
local refs = {}
local function load_refs()
    refs = {}
    local tsv = io.open(cache .. "/sessions.tsv", "r")
    if not tsv then return end
    for line in tsv:lines() do
        -- Block ids and agents hold no tabs; the ref (a pi session path
        -- may hold spaces) runs to the next tab, before the timestamp.
        local b, agent, ref = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)")
        if b then refs[b] = { agent = agent, ref = ref } end
    end
    tsv:close()
end
load_refs()

local function resume_cmd(agent, ref)
    if agent == "claude" then
        return ref and ("claude --resume " .. ref) or "claude --continue"
    end
    if agent == "codex" then
        return ref and ("codex resume " .. ref) or "codex resume --last"
    end
    if agent == "pi" then return ref and ("pi --session " .. ref) end
end

-- Resume commands already scheduled by this recorder. An exact ref
-- makes a command unique, so this only bites on the fallbacks
-- (--continue, resume --last): two restored blocks in one directory
-- must not both fork the newest conversation there; the second stays at
-- its shell.
local consumed = {}

local function schedule_resume(session_id, block_id, e, gen)
    if not e.agent or e.agent == "" then return end
    load_refs()
    local r = refs[block_id]
    -- Trust the hook's ref only when its agent is the one this recorder
    -- saw in the foreground; a ref left by an earlier agent in the same
    -- block would resume the wrong conversation.
    local ref = (r and r.agent == e.agent) and r.ref or nil
    local cmd = resume_cmd(e.agent, ref)
    -- Adopt the new epoch's generation so later echoes do not re-fire,
    -- and flush at once so a crash before the write lands cannot lose it.
    e.gen = gen or e.gen
    e.ts = os.time()
    flush()
    if not cmd or consumed[cmd] then return end
    consumed[cmd] = true
    rex.after(2.0, function()
        -- One native write, addressed to the restored block's own
        -- session: no CLI process that must outlive the timer, and no
        -- text-then-Enter race.
        local res, err = rex.block.call(TERMINAL, "write", {
            session_id = session_id,
            block_id = block_id,
            data = cmd .. "\r",
        })
        if not res then
            rex.log("warn", "agent-resume: write to " .. block_id
                .. " failed: " .. tostring(err))
        end
    end)
end

rex.on("terminal.process_changed", function(ctx, ev)
    local e = state[ctx.block_id]
    local gen = ev.generation
    if e and type(e) == "table" and e.gen and gen then
        -- A restored block restarts generations from 1, so a generation
        -- lower than the one on record means this block was restored
        -- while an agent had the foreground. An equal one is an echo of
        -- the current foreground and never an update.
        if gen < e.gen then
            schedule_resume(ctx.session_id, ctx.block_id, e, gen)
            return
        end
        if gen == e.gen then return end
    end
    local agent = classify(ev.foreground)
    if agent == nil then return end
    e = e or {}
    e.gen = gen or 0
    e.agent = agent
    if ev.foreground and ev.foreground.cwd then
        e.cwd = ev.foreground.cwd
    end
    e.ts = os.time()
    state[ctx.block_id] = e
    dirty = true
end)

-- A recorder spawned by a restored shell inherits that shell's
-- REX_SESSION and REX_BLOCK, and its own block's generation-reset event
-- fired before this script could subscribe: nothing replays past
-- events. If the persisted entry for that block shows an agent with
-- generations past a fresh shell's first, and that agent is not in the
-- foreground now, the block was restored while no recorder was
-- watching: resume it from here.
do
    local s, b = os.getenv("REX_SESSION"), os.getenv("REX_BLOCK")
    local e = b and state[b]
    if s and type(e) == "table" and e.agent and e.agent ~= ""
        and (e.gen or 0) > 1 then
        local ok, proc = pcall(rex.block.call, TERMINAL, "process",
            { session_id = s, block_id = b })
        local fg = ok and proc and proc.foreground or nil
        -- Anything but the recorded agent still in the foreground (a
        -- shell, or a query that could not run) means restored.
        if classify(fg) ~= e.agent then
            schedule_resume(s, b, e, 1)
        end
    end
end

rex.every(2, function()
    if dirty then flush() end
end)
