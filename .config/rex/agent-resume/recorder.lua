-- Records the foreground program of every Rex terminal block, so that a
-- restored terminal (same block id, fresh shell, same directory) can
-- resume the coding agent that was running in it before a restart.
-- The agent self-report hooks write exact session ids to sessions.tsv
-- beside this state.
--
-- Runs as:  rex do ~/.config/rex/agent-resume/recorder.lua --all
-- Started by ~/.config/rex/agent-resume/init.lua (pulled into
-- ~/.config/rex/init.lua by require) at every server start and on every
-- `rex config reload` — the recovery lever should the recorder ever
-- die. Any recorder named in the pidfile is replaced first, so exactly
-- one runs, the newest. Events are the fast path; the periodic sweep
-- below catches restores whose events fired before this recorder
-- subscribed or while no recorder was running at all. REX_AGENT_RESUME=0
-- (in the server's environment) disables the whole system.
--
-- Environment, read once from the server's at start:
--   REX_AGENT_RESUME_MAX_AGE_DAYS  how old a recording may be and still
--                                  auto-resume (default 7, 0 disables
--                                  resuming entirely)
--   REX_AGENT_RESUME_DEBUG=1       append a timestamped line per
--                                  decision (restore detected and by
--                                  which signal, resume delivered or
--                                  skipped and why, queue drained or
--                                  rejected) to debug.log beside this
--                                  state — the same decisions rex.log
--                                  carries, collected in one place
--   REX_AGENT_RESUME_MODE=prompt   deliver by typing the command without
--                                  the Enter that runs it, so nothing
--                                  resumes without a keystroke; any
--                                  other value (the default, auto)
--                                  resumes as before
--
-- The agent_resume_now / agent_resume_forget actions that init.lua
-- registers never edit this recorder's files; they drop request files
-- into commands/ beside them, and the flush timer below drains the
-- queue. The recorder owns the state, so no other write can race it.

local cache = (os.getenv("XDG_CACHE_HOME") or os.getenv("HOME") .. "/.cache")
    .. "/rex-agent-resume"
local json_file = cache .. "/recorder.json"
local pid_file = cache .. "/recorder.pid"
local consumed_file = cache .. "/consumed.txt"
local commands_dir = cache .. "/commands"

-- Resume only state recorded within this many days: a recorder gap can
-- leave an agent on record long after the user has moved on, and
-- resuming a weeks-old conversation is never wanted. 0 disables
-- resuming entirely.
local max_age_days = tonumber(os.getenv("REX_AGENT_RESUME_MAX_AGE_DAYS") or "") or 7
local max_age_s = max_age_days * 86400

-- The debug log mirrors the decisions rex.log already reports, but with
-- timestamps and in one file beside the state, so a resume that went
-- wrong can be read back after the fact without digging through the
-- server log. A logging failure must never break the behavior it
-- observes, hence the pcall.

-- Prompt mode holds every delivery for one keystroke of consent: the
-- command is typed exactly as before but the Enter is left to the user.
-- A trust lever for the first while after any change to this system —
-- nothing runs by itself, and clearing the line is a skip. While a
-- delivery waits, the block's recording carries a `pending` flag, so
-- the sweep below can tell a pane holding an unrun command from one
-- whose agent was really quit.
local prompt_mode = os.getenv("REX_AGENT_RESUME_MODE") == "prompt"

local debug_on = os.getenv("REX_AGENT_RESUME_DEBUG") == "1"
local function dlog(msg)
    if not debug_on then return end
    pcall(function()
        local fh = io.open(cache .. "/debug.log", "a")
        if fh then
            fh:write(os.date("%Y-%m-%dT%H:%M:%S "), msg, "\n")
            fh:close()
        end
    end)
end

local TERMINAL = "com.superlogical.terminal"

-- Replace any earlier recorder before reading state: init.lua starts
-- one at every server start and config reload, and a recorder that lost
-- its server may linger, timers still running, writing the same state
-- file. The pidfile's process is signalled only when ps confirms it is
-- a recorder, so a recycled pid is never killed.
local replaced
do
    local fh = io.open(pid_file, "r")
    local old = fh and fh:read("*a"):match("%d+")
    if fh then fh:close() end
    old = old and tonumber(old) or nil
    if old then
        local r = rex.exec({ "ps", "-o", "command=", "-p", tostring(old) })
        if r and r.ok and r.stdout and r.stdout:find("recorder%.lua") then
            rex.exec({ "kill", tostring(old) })
            rex.sleep(0.3)
            replaced = old
        end
    end
end

if os.getenv("REX_AGENT_RESUME") == "0" then rex.stop(0) end

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

-- Bootstrap the cache and command-queue directories and claim the
-- pidfile. A rex.exec child's parent is the rex do process itself, so
-- its PPID is this script's pid.
rex.exec({ "mkdir", "-p", cache, commands_dir })
local pid = rex.exec({ "sh", "-c", "echo $PPID" })
if pid and pid.ok then
    local p = pid.stdout and pid.stdout:gsub("%s", "")
    if p and p ~= "" then write(pid_file, p .. "\n") end
end

dlog(replaced and ("recorder started, replacing pid " .. replaced)
    or "recorder started")

-- Session-scoped calls (list_blocks, block.call) work only on a
-- connection attached to that session, and this recorder is born with
-- no session of its own when init.lua starts it — without this, every
-- call, the resume write included, fails with a conflict. Called again
-- by every sweep: a connection that survived a server restart and
-- reconnected starts the new server unattached.
local function reattach()
    rex.call("session.attach_all", { event_scope = "all" })
end
reattach()

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
    -- A live report outranks path matching; the generation and shell on
    -- record stay, so a restore after a crash is still detected by
    -- them.
    e.agent, e.ts = app, os.time()
    state[ctx.block_id] = e
    dirty = true
end)

-- The pid of the terminal's own program: the last of the ancestors
-- while an agent holds the foreground, the foreground itself while the
-- shell has it, or the foreground when the agent is that program (a
-- block started with a command). A restore replaces this process with
-- a fresh one, which is how the sweep tells a restore from an agent
-- the user quit.
local function shell_pid_of(ev)
    local fg = ev.foreground
    if not fg then return nil end
    local agent = classify(fg)
    if agent == nil then return nil end
    if agent == "" then return fg.pid end
    local anc = ev.ancestors
    if anc and #anc > 0 then return anc[#anc].pid end
    return fg.pid
end

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

-- Record a resume command as taken, in memory and in the persisted
-- consumed file, so a recorder restarted mid-restore (a second crash)
-- keeps the protection.
local function mark_consumed(cmd)
    consumed[cmd] = true
    local cfh = io.open(consumed_file, "a")
    if cfh then
        cfh:write(cmd .. "\t" .. os.time() .. "\n")
        cfh:close()
    end
end

-- Type a resume command into a block's own first shell, after a beat
-- that lets a restored shell settle. Shared by the automatic path (a
-- detected restore) and the manual one (a queued request): the guards
-- below apply to both, and so does prompt mode — with the Enter
-- withheld, a manual resume waits for the same keystroke an automatic
-- one does.
local function deliver_resume(session_id, block_id, cmd)
    rex.after(2.0, function()
        -- One native write, addressed to the target block's own
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
            dlog("busy skip: " .. block_id)
            return
        end
        -- Prompt mode withholds the Enter, so the command sits on the
        -- shell's command line until the user runs or clears it. The
        -- delivery is final either way — mark_consumed has already run,
        -- and nothing here auto-fires twice — so clearing the line
        -- (Ctrl-C or Ctrl-U) skips this delivery for good; the recovery
        -- levers are the agent_resume_now / agent_resume_forget palette
        -- actions, and the former re-delivers on demand. Nothing
        -- explanatory may be typed into the pane instead: any extra
        -- bytes reach the pty and become part of the command line, so
        -- the visible command on the prompt is the whole interface.
        local data = cmd .. (prompt_mode and "" or "\r")
        local res, err = rex.block.call(TERMINAL, "write", {
            session_id = session_id,
            block_id = block_id,
            data = data,
        })
        if not res then
            rex.log("warn", "agent-resume: write to " .. block_id
                .. " failed: " .. tostring(err))
            dlog("resume write to " .. block_id .. " failed: "
                .. tostring(err))
        elseif prompt_mode then
            -- Hold the recording while the command waits: until Enter is
            -- pressed the pane looks exactly like one whose agent was
            -- quit, and the sweep must not read it that way and drop the
            -- block, or agent_resume_now would find nothing left to
            -- re-deliver. Cleared as soon as the agent is seen running.
            local e = state[block_id]
            if type(e) == "table" then
                e.pending = true
                dirty = true
            end
            rex.log("info", "agent-resume: typed without Enter into "
                .. block_id .. "; press Enter to resume or clear the line"
                .. " to skip")
            dlog("prompt delivery to " .. block_id .. ": " .. cmd
                .. " — typed without Enter; press Enter to resume, or"
                .. " clear the line to skip")
        else
            dlog("resume delivered to " .. block_id .. ": " .. cmd)
        end
    end)
end

local function schedule_resume(session_id, block_id, e, gen, shell)
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
    -- Adopt the new epoch's generation and shell so later echoes and
    -- sweeps do not re-fire, and flush at once so a crash before the
    -- write lands cannot lose it.
    e.gen = gen or e.gen
    e.shell = shell or e.shell
    e.ts = os.time()
    flush()
    if max_age_s <= 0 or age > max_age_s then
        rex.log("info", "agent-resume: state for " .. block_id
            .. " is stale (or resuming is disabled); leaving it at its shell")
        dlog("stale skip: " .. block_id)
        return
    end
    if not cmd or consumed[cmd] then return end
    mark_consumed(cmd)
    deliver_resume(session_id, block_id, cmd)
end

rex.on("terminal.process_changed", function(ctx, ev)
    local e = state[ctx.block_id]
    local gen = ev.generation
    local agent = classify(ev.foreground)
    if e and type(e) == "table" and e.gen and gen then
        -- A restored block restarts generations from 1, so a generation
        -- lower than the one on record means this block was restored
        -- while an agent had the foreground. An equal one is an echo of
        -- the current foreground and never an update.
        if gen < e.gen then
            if agent == e.agent then
                -- The recorded agent itself is starting in the fresh
                -- epoch — Enter pressed on a delivered command, or the
                -- agent started anew — not a restore to answer. Only a
                -- sweep-detected restore reaches this test with the
                -- agent running: the event path adopts the fresh
                -- generation when it schedules, the sweep cannot, so
                -- the one on record is stale-high. Adopt it here, or
                -- every later change in the block reads as another
                -- reset, and settle any prompt-mode hold — the command
                -- demonstrably ran, and a hold left set would keep the
                -- sweep's quit detection suppressed after it.
                e.gen, e.ts, e.pending = gen, os.time(), nil
                dirty = true
                dlog("agent running again in " .. ctx.block_id
                    .. ": adopting generation " .. tostring(gen)
                    .. ", settling any hold")
                return
            end
            dlog("restore detected: generation reset in " .. ctx.block_id)
            schedule_resume(ctx.session_id, ctx.block_id, e, gen,
                shell_pid_of(ev))
            return
        end
        if gen == e.gen then
            -- An echo can still supply a shell pid nobody had on
            -- record (this recorder started after the last change).
            if not e.shell then
                e.shell = shell_pid_of(ev)
                if e.shell then dirty = true end
            end
            return
        end
    end
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
    e.shell = shell_pid_of(ev) or e.shell
    -- An agent in the foreground again means the typed command was run
    -- (or a new one started): the prompt-mode hold is settled.
    e.pending = nil
    state[ctx.block_id] = e
    dirty = true
end)

-- Reconcile persisted state with every terminal block on this server.
-- The events above are the fast path, but they are one-shot: a restore
-- whose generation-reset events fired before this recorder subscribed
-- (it starts alongside the server, at the same time sessions are being
-- restored) or while an earlier recorder was dead is invisible to them
-- — blocks do not replay past events, and a new subscription brings no
-- echo. A restored block always starts a fresh shell, so a child pid
-- that differs from the shell pid on record is a restore nobody saw.
local function check_block(session_id, block_id)
    local e = state[block_id]
    if type(e) ~= "table" then e = nil end
    local ok, proc = pcall(rex.block.call, TERMINAL, "process", {
        session_id = session_id,
        block_id = block_id,
    })
    if not ok or type(proc) ~= "table" then return end
    local child = proc.child and proc.child.pid or nil
    local fg = classify(proc.foreground)
    if not e then
        -- A block running an agent whose start this recorder never saw
        -- (it was already in the foreground when the recorder first
        -- ran): record it now, with its shell but no generation, so a
        -- later restore is still detected — by the sweep, since no
        -- generation is known for it.
        if fg and fg ~= "" and child then
            state[block_id] = { agent = fg, ts = os.time(), shell = child }
            dirty = true
        end
        return
    end
    if not e.agent or e.agent == "" then return end
    if not child then return end
    if e.shell and child ~= e.shell then
        if fg == e.agent then
            -- The agent is running again (already resumed, or started
            -- anew): adopt the fresh shell so the restore is not
            -- re-fired, and settle any prompt-mode hold.
            e.shell, e.ts = child, os.time()
            e.pending = nil
            dirty = true
        else
            dlog("restore detected: sweep found a fresh shell in " .. block_id)
            schedule_resume(session_id, block_id, e, nil, child)
        end
    elseif not e.shell and fg == e.agent then
        -- No shell on record yet; learn it while the agent
        -- demonstrably runs, for every later comparison.
        e.shell = child
        e.pending = nil
        dirty = true
    elseif e.shell and child == e.shell and fg == "" and not e.pending then
        -- The same shell the agent ran in has the foreground back: the
        -- agent was quit, not cut off by a restart. Nothing to resume.
        -- A pending flag excepts this: in prompt mode the delivered
        -- command is still sitting unrun on that shell's line, and the
        -- pane only looks like a quit.
        state[block_id] = nil
        dirty = true
    end
end

-- Every terminal block on this server, across sessions. Sessions on
-- remote hosts are listed but not addressable from this server; their
-- blocks skip the walk (their events still arrive). Failures stay
-- silent for the same reason. fn returns true to stop the walk early.
local function each_terminal_block(fn)
    local res = rex.call("session.list")
    if type(res) ~= "table" or type(res.sessions) ~= "table" then
        -- Unreachable or restarting; the next sweep retries.
        return
    end
    for _, s in ipairs(res.sessions) do
        local blocks = rex.session.list_blocks{ session_id = s.session_id }
        if type(blocks) == "table" and type(blocks.blocks) == "table" then
            for _, b in ipairs(blocks.blocks) do
                if b.creator_name == TERMINAL
                    and fn(s.session_id, b.block_id) then
                    return
                end
            end
        end
    end
end

local function sweep()
    reattach()
    each_terminal_block(check_block)
end

-- The session that owns a block, for queue commands that name only a
-- block (the CLI can pass one without a session).
local function find_session(block_id)
    local found
    each_terminal_block(function(session_id, bid)
        if bid == block_id then
            found = session_id
            return true
        end
    end)
    return found
end

-- The manual levers. The agent_resume_now / agent_resume_forget actions
-- that init.lua registers never edit this recorder's state: recorder.json
-- is the in-memory table below, flushed whenever dirty, so a direct edit
-- races the next flush and is resurrected by it. They drop request files
-- into commands/ instead, and only this recorder applies them — one file
-- per request, "resume\t<session>\t<block>" (session "-" meaning:
-- locate it) or "forget\t<block>".

-- The same mkdir lock the self-report hooks take around sessions.tsv
-- (see hooks/rex-agent-state.sh): without it, a hook write landing
-- between this read and the rename would be lost. A short, bounded wait
-- rather than a blocking one — the drain shares a timer with the flush —
-- and a lock orphaned by a killed hook is taken over after a minute,
-- exactly as the hooks do.
local sessions_lock = cache .. "/.sessions.lock"
local function with_sessions_lock(fn)
    local took = false
    for i = 1, 20 do
        local r = rex.exec({ "mkdir", sessions_lock })
        if r and r.ok then
            took = true
            break
        end
        if i == 1 then
            local f = rex.exec({ "find", sessions_lock, "-type", "d",
                "-mmin", "+1" })
            if f and f.ok and f.stdout and f.stdout ~= "" then
                rex.exec({ "rmdir", sessions_lock })
            end
        end
        rex.sleep(0.05)
    end
    if not took then return false end
    local ok, err = pcall(fn)
    rex.exec({ "rmdir", sessions_lock })
    if not ok then error(err, 0) end
    return true
end

-- Drop one block's line from sessions.tsv, so no ref is left for an
-- agent this pane no longer has. A plain prefix compare, not a pattern:
-- block ids hold no tabs, and nothing in them should ever be read as a
-- magic character.
local function forget_ref(block_id)
    local tsv = cache .. "/sessions.tsv"
    local fh = io.open(tsv, "r")
    if not fh then return end
    local kept, seen = {}, false
    for line in fh:lines() do
        if line:sub(1, #block_id + 1) == block_id .. "\t" then
            seen = true
        else
            kept[#kept + 1] = line
        end
    end
    fh:close()
    if not seen then return end
    write(tsv, #kept > 0 and table.concat(kept, "\n") .. "\n" or "")
end

local function apply_forget(block_id)
    state[block_id] = nil
    dirty = true
    with_sessions_lock(function() forget_ref(block_id) end)
    flush()
    rex.log("info", "agent-resume: forgot " .. block_id)
    dlog("forgot " .. block_id)
end

-- A resume the user asked for by hand: the freshness window and the
-- consumed check do not apply — they asked explicitly — but the busy
-- check in deliver_resume still guards the pane, and the command is
-- recorded as consumed so a later auto-restore cannot double-fire the
-- same fallback.
local function manual_resume(session_id, block_id)
    local e = state[block_id]
    if type(e) ~= "table" or not e.agent or e.agent == "" then
        rex.log("debug", "agent-resume: no saved agent for " .. block_id
            .. "; dropping manual resume")
        dlog("queue rejected: no saved agent for " .. block_id)
        return
    end
    if not session_id or session_id == "" or session_id == "-" then
        session_id = find_session(block_id)
        if not session_id then
            rex.log("warn", "agent-resume: no session owns " .. block_id
                .. "; dropping manual resume")
            dlog("queue rejected: no session for " .. block_id)
            return
        end
    end
    load_refs()
    local r = refs[block_id]
    local ref = (r and r.agent == e.agent) and r.ref or nil
    local cmd = resume_cmd(e.agent, ref)
    if not cmd then
        rex.log("warn", "agent-resume: no resume command for agent "
            .. tostring(e.agent) .. "; dropping manual resume")
        dlog("queue rejected: no command for agent " .. tostring(e.agent))
        return
    end
    -- Mark the recording fresh so the next flush keeps the entry
    -- through its delivery window.
    e.ts = os.time()
    dirty = true
    mark_consumed(cmd)
    dlog("manual resume for " .. block_id .. ": " .. cmd)
    deliver_resume(session_id, block_id, cmd)
end

local function apply_command(path)
    local fh = io.open(path, "r")
    if not fh then return end
    local line = fh:read("*l") or ""
    fh:close()
    local op = line:match("^%a+")
    if op == "resume" then
        local sid, bid = line:match("^resume\t([^\t]*)\t([^\t]+)$")
        if bid then
            dlog("queue drained: resume " .. bid)
            manual_resume(sid, bid)
            return
        end
    elseif op == "forget" then
        local bid = line:match("^forget\t([^\t]+)$")
        if bid then
            dlog("queue drained: forget " .. bid)
            apply_forget(bid)
            return
        end
    end
    rex.log("warn", "agent-resume: dropping malformed command: " .. line)
    dlog("queue rejected: " .. line)
end

-- Drain the action queue. Each file is claimed by renaming it to
-- .doing before it is read — two overlapping recorders (one being
-- replaced) never apply the same request — and removed after it is
-- applied whatever happened inside, so a request never fires twice.
-- .tmp files are writes still in flight and are left alone.
local function drain_commands()
    local r = rex.exec({ "ls", "-1", commands_dir })
    if not r or not r.ok or not r.stdout or r.stdout == "" then return end
    for name in r.stdout:gmatch("[^\n]+") do
        if not name:match("%.tmp$") and not name:match("%.doing$") then
            local claimed = commands_dir .. "/" .. name .. ".doing"
            if os.rename(commands_dir .. "/" .. name, claimed) then
                local ok, err = pcall(apply_command, claimed)
                if not ok then
                    rex.log("warn", "agent-resume: command " .. name
                        .. " failed: " .. tostring(err))
                    dlog("queue command " .. name .. " failed: "
                        .. tostring(err))
                end
                os.remove(claimed)
            end
        end
    end
end

-- Clear claim files left by a recorder that died mid-command: this
-- recorder replaced it, so anything it had claimed is stale.
rex.exec({ "sh", "-c",
    "rm -f " .. shellq(commands_dir) .. "/*.doing" })

-- The first sweep waits for the restore dust to settle (shells to spawn
-- and the event path to take anything it saw); the rest keep watch over
-- recorder gaps.
rex.after(3, sweep)
rex.every(30, sweep)

-- Flush pending state first, then drain the action queue: a forget's
-- flush is never delayed behind queue work, and the drain — bounded,
-- and pcall-guarded per command — cannot hold the flush up for long.
rex.every(2, function()
    if dirty then flush() end
    drain_commands()
end)
