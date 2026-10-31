-- Records the foreground program of every Rex terminal block, so that a
-- restored terminal (same block id, fresh shell, same directory) can
-- resume the coding agent that was running in it before a restart.
-- ~/.config/rex/agent-resume.sh reads the state this writes; the agent
-- self-report hooks write exact session ids to sessions.tsv beside it.
--
-- Runs as:  rex do ~/.config/rex/recorder.lua --all
-- Started by ~/.config/rex/init.lua (best effort) and by
-- ~/.config/rex/ensure-recorder.sh from every terminal shell.

local cache = (os.getenv("XDG_CACHE_HOME") or os.getenv("HOME") .. "/.cache")
    .. "/rex-agent-resume"
local json_file = cache .. "/recorder.json"
local tsv_file = cache .. "/recorder.tsv"

local started = os.time()

local function read_state()
    local fh = io.open(json_file, "r")
    if not fh then return {} end
    local ok, t = pcall(rex.json.decode, fh:read("*a"))
    fh:close()
    if ok and type(t) == "table" then return t end
    return {}
end

local state = read_state()
state._meta = { version = 1, started = started }
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
    write(json_file, rex.json.encode(state))
    local lines = {}
    for block, e in pairs(state) do
        if block ~= "_meta" and type(e) == "table" then
            lines[#lines + 1] = table.concat({
                block, e.agent or "", e.cwd or "", tostring(e.gen or 0),
                tostring(e.ts or 0),
            }, "\t") .. "\n"
        end
    end
    table.sort(lines)
    write(tsv_file, table.concat(lines))
    dirty = false
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

rex.on("terminal.program_status_changed", function(ctx, ev)
    local app = ev.record and ev.record.app and APPS[ev.record.app]
    if not app then return end
    local e = state[ctx.block_id] or {}
    -- A live report outranks everything: drop the generation guard so
    -- foreground changes after this can update the entry again.
    e.agent, e.ts, e.gen = app, os.time(), 0
    state[ctx.block_id] = e
    dirty = true
end)

-- Hybrid resume: the shell hooks only bootstrap this recorder; the
-- resume itself happens here. A block whose pre-restart entry had an
-- agent in the foreground shows a low generation again after a restore
-- (generations restart at 1): type the resume command into it, the way
-- herdr does. Exact refs come from the agents' self-report hooks.
local refs = {}
do
    local tsv = io.open(cache .. "/sessions.tsv", "r")
    if tsv then
        for line in tsv:lines() do
            local b, agent, ref = line:match("^(%S+)\t(%S+)\t(%S+)")
            if b then refs[b] = { agent = agent, ref = ref } end
        end
        tsv:close()
    end
end

local function resume_cmd(agent, ref)
    if agent == "claude" then
        return ref and ("claude --resume " .. ref) or "claude --continue"
    end
    if agent == "codex" then
        return ref and ("codex resume " .. ref) or "codex resume --last"
    end
    if agent == "pi" then return ref and ("pi --session " .. ref) end
end

local function type_into(block_id, cmd)
    local rex_bin = (os.getenv("REX_BIN_DIR") and os.getenv("REX_BIN_DIR") .. "/rex") or "rex"
    pcall(rex.exec.start, { rex_bin, "send", "-b", block_id, cmd })
    pcall(rex.exec.start, { rex_bin, "send-key", "-b", block_id, "enter" })
end

local function maybe_resume(ctx, e, ev)
    -- Only entries older than this script's start are pre-restart, and
    -- only once per block per restore.
    if not e.agent or e.agent == "" then return end
    if e.ts and e.ts >= started then return end
    if state["resumed_" .. ctx.block_id] then return end
    state["resumed_" .. ctx.block_id] = true
    local r = refs[ctx.block_id]
    local cmd = resume_cmd(r and r.agent or e.agent, r and r.ref or nil)
    if not cmd then return end
    -- Adopt the new epoch's generation so later echoes do not re-fire.
    e.gen = ev.generation or e.gen
    dirty = true
    rex.after(2.0, function() type_into(ctx.block_id, cmd) end)
end

rex.on("terminal.process_changed", function(ctx, ev)
    local e = state[ctx.block_id]
    -- A restored block restarts generations from 1, so in the moments
    -- after a restore this hears low generations for blocks whose
    -- pre-crash entries have higher ones. Stale echoes never overwrite;
    -- a genuinely new foreground always has a higher generation.
    if e and e.gen and ev.generation and ev.generation <= e.gen then
        maybe_resume(ctx, e, ev)
        return
    end
    local agent = classify(ev.foreground)
    if agent == nil then return end
    e = e or {}
    e.gen = ev.generation or 0
    e.agent = agent
    if ev.foreground and ev.foreground.cwd then
        e.cwd = ev.foreground.cwd
    end
    e.ts = os.time()
    state[ctx.block_id] = e
    dirty = true
end)

rex.every(2, function()
    if dirty then flush() end
end)
