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
local consumed_file = cache .. "/consumed.txt"

-- Resume only state recorded within this many days: a recorder gap can
-- leave an agent on record long after the user has moved on, and
-- resuming a weeks-old conversation is never wanted. 0 disables
-- resuming entirely. (The knob the old shell-side hook used.)
local max_age_days = tonumber(os.getenv("REX_AGENT_RESUME_MAX_AGE_DAYS") or "") or 7
local max_age_s = max_age_days * 86400

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
    -- Drop entries that could never resume again — no agent, or one
    -- recorded further back than the freshness window — so the state
    -- file does not grow without bound.
    local now = os.time()
    for k, v in pairs(state) do
        if type(v) ~= "table" or not v.agent or v.agent == ""
            or (max_age_s > 0 and now - (v.ts or 0) > max_age_s) then
            state[k] = nil
        end
    end
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
-- as env or node, so every name field is checked, by basename first, and
-- the script a node/python interpreter runs last.
-- Returns "" for a plain foreground (shell, vim, ...) meaning: no resume.
local function classify(f)
    if not f then return nil end
    local fields = { f.name, f.argv0, f.invoked_path, f.path, f.script }
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

-- Quote a ref for the shell that will read the typed command; a pi ref
-- is a session file path, and paths can hold spaces.
local function shellq(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function resume_cmd(agent, ref)
    if agent == "claude" then
        return ref and ("claude --resume " .. shellq(ref)) or "claude --continue"
    end
    if agent == "codex" then
        return ref and ("codex resume " .. shellq(ref)) or "codex resume --last"
    end
    if agent == "pi" then return ref and ("pi --session " .. shellq(ref)) end
end

-- Resume commands already taken. An exact ref makes a command unique,
-- so this only bites on the fallbacks (--continue, resume --last): two
-- restored blocks in one directory must not both fork the newest
-- conversation there; the second stays at its shell. Persisted with a
-- timestamp, so a recorder restarted mid-restore (a second crash) keeps
-- the protection, and entries expire with the freshness window instead
-- of blocking a later genuine fallback forever.
local consumed = {}
do
    local fh = io.open(consumed_file, "r")
    if fh then
        for line in fh:lines() do
            local c, t = line:match("^([^\t]+)\t(%d+)$")
            if c and max_age_s > 0 and os.time() - tonumber(t) <= max_age_s then
                consumed[c] = true
            end
        end
        fh:close()
    end
end

local function schedule_resume(session_id, block_id, e, gen)
    if not e.agent or e.agent == "" then return end
    -- Check staleness against the ts on record, before it is refreshed.
    local age = os.time() - (e.ts or os.time())
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
    if max_age_s <= 0 or age > max_age_s then
        rex.log("info", "agent-resume: state for " .. block_id
            .. " is stale (or resuming is disabled); leaving it at its shell")
        return
    end
    if not cmd or consumed[cmd] then return end
    consumed[cmd] = true
    local cfh = io.open(consumed_file, "a")
    if cfh then
        cfh:write(cmd .. "\t" .. os.time() .. "\n")
        cfh:close()
    end
    rex.after(2.0, function()
        -- One native write, addressed to the restored block's own
        -- session: no CLI process that must outlive the timer, and no
        -- text-then-Enter race. Write only into the terminal's own
        -- first shell: a foreground the user has since started (a
        -- nested shell, an editor) would read the typed command
        -- instead of the shell.
        local ok, proc = pcall(rex.block.call, TERMINAL, "process", {
            session_id = session_id,
            block_id = block_id,
        })
        local fg = ok and proc and proc.foreground or nil
        local child = ok and proc and proc.child or nil
        if fg and child and fg.pid ~= child.pid then
            rex.log("info", "agent-resume: " .. block_id
                .. " is busy; not typing a resume into it")
            return
        end
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
    if agent == "" then
        -- A plain foreground (shell, vim, ...) means no resume; keep no
        -- entry at all rather than growing the state file with blocks
        -- that have nothing to resume.
        if state[ctx.block_id] then
            state[ctx.block_id] = nil
            dirty = true
        end
        return
    end
    e = e or {}
    e.gen = gen or 0
    e.agent = agent
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
        -- shell, or a query that could not run) means restored. A
        -- nested shell the user opened also lands here, so the write
        -- re-checks the foreground before typing.
        if classify(fg) ~= e.agent then
            schedule_resume(s, b, e, 1)
        end
    end
end

rex.every(2, function()
    if dirty then flush() end
end)
