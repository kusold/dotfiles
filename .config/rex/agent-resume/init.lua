-- agent-resume: resume the coding agent (claude, codex, pi) that was
-- running in a terminal when the Rex server restarted, in the same
-- block, via recorder.lua below and the self-report hooks that
-- install-hooks.sh keeps in the agents' own configs.
--
-- rex.on is invalid in configuration files (handlers are never called),
-- so the block recorder can't live here; start it as a detached process
-- instead. This runs at every server start and on every
-- `rex config reload` — the recovery lever should the recorder ever
-- die — and the recorder replaces any earlier instance it finds in its
-- pidfile, so starting here unconditionally keeps exactly one running.
-- Nothing else bootstraps it: no shell hook of any kind is involved.
--
-- Environment, read from the server's: REX_AGENT_RESUME=0 disables the
-- whole system (the recorder exits at once and the actions below stay
-- unregistered, with no recorder to drain their queue);
-- REX_AGENT_RESUME_MAX_AGE_DAYS bounds what the recorder auto-resumes
-- (default 7); REX_AGENT_RESUME_DEBUG=1 makes the recorder append its
-- decisions to debug.log in the cache; REX_AGENT_RESUME_MODE=prompt has
-- the recorder type each resume command without the Enter that runs it,
-- so nothing resumes without a keystroke (any other value, the default
-- auto, resumes as before).
local dir = os.getenv("REX_BIN_DIR")
local exe = (dir and dir .. "/rex") or "rex"

-- exec.start is one of the calls that works at load time, but it still
-- reports failure as nil + message rather than an error, so catch both.
local function start(argv)
    local ok, handle = pcall(rex.exec.start, argv, { detach = true })
    if not ok or not handle then
        print("rex init: could not start " .. argv[1] .. ": "
            .. tostring(handle))
    end
end

start({ exe, "do",
    os.getenv("HOME") .. "/.config/rex/agent-resume/recorder.lua", "--all" })

-- Keep the agents' self-report hooks installed.
start({ "/bin/sh", "-c",
    os.getenv("HOME")
        .. "/.config/rex/agent-resume/install-hooks.sh --ensure" })

-- Manual levers on the recorder's state, as command-palette actions.
-- recorder.json is the recorder's in-memory table flushed to disk
-- whenever it is dirty, so an action that edited the file directly
-- would race the next flush and have its edit resurrected. Instead each
-- action drops one request file into the command queue (commands/ in
-- the same cache) and the recorder drains it on its 2s flush timer,
-- applying it with the state it already owns. Explicit args override
-- the focused pane, so the CLI and tests can target any block:
--   rex do agent_resume_now block_id=<id> [session_id=<id>]
--   rex do agent_resume_forget block_id=<id>
local cache = (os.getenv("XDG_CACHE_HOME") or os.getenv("HOME") .. "/.cache")
    .. "/rex-agent-resume"
local queue_dir = cache .. "/commands"

-- One request per file, named for what it asks (two requests for the
-- same pane in the same second are the same request twice; anything in
-- an id that a filename cannot hold is flattened). Written whole and
-- renamed into place, so the recorder never reads a half-written
-- command. The recorder makes the queue dir when it starts; the mkdir
-- fallback covers a request arriving before that — or with the recorder
-- dead, whose requests then wait for the next one.
local function queue_command(line)
    local name = (line:gsub("[^%w:%-.]", "_")) .. "." .. os.time()
    local tmp = queue_dir .. "/" .. name .. ".tmp"
    local fh = io.open(tmp, "w")
    if not fh then
        rex.exec({ "mkdir", "-p", queue_dir })
        fh = io.open(tmp, "w")
    end
    if not fh then error("cannot write " .. tmp, 0) end
    fh:write(line, "\n")
    fh:close()
    if not os.rename(tmp, queue_dir .. "/" .. name) then
        error("cannot queue " .. name, 0)
    end
end

-- The pane a request is about: an explicit argument wins over the pane
-- the action was run from, and with neither there is nothing to act on.
local function pane(ctx, args)
    local block_id = (args.block_id and args.block_id ~= ""
        and args.block_id) or ctx.block_id
    if not block_id then error("no pane is focused", 0) end
    return block_id
end

-- REX_AGENT_RESUME=0 leaves no recorder to drain the queue, so the
-- actions stay unregistered rather than accept requests that would sit
-- forever.
if os.getenv("REX_AGENT_RESUME") ~= "0" then
    rex.action({
        name = "agent_resume_now",
        title = "Agent Resume: Resume This Pane Now",
        description = "Resume the agent recorded for this pane now, ignoring "
            .. "the freshness window.",
        category = "Agent Resume",
        keywords = "agent resume claude codex pi chat pane restore now",
        args = { block_id = "string?", session_id = "string?" },
        run = function(ctx, args)
            local block_id = pane(ctx, args)
            -- Peek read-only at the recorder's state to fail fast: a
            -- request the recorder would silently drop (nothing on
            -- record for this pane) should say so, not queue quietly.
            -- Best-effort by design — an unreadable state file still
            -- queues, and the recorder makes the final call.
            local fh = io.open(cache .. "/recorder.json", "r")
            if fh then
                local text = fh:read("*a")
                fh:close()
                local ok, t = pcall(rex.json.decode, text)
                local e = ok and type(t) == "table" and t[block_id] or nil
                if type(e) ~= "table" or not e.agent or e.agent == "" then
                    error("no saved agent for this pane", 0)
                end
            end
            local session_id = (args.session_id and args.session_id ~= ""
                and args.session_id) or ctx.session_id
            queue_command("resume\t" .. (session_id or "-") .. "\t"
                .. block_id)
            return { output = "resume queued for " .. block_id }
        end,
    })

    rex.action({
        name = "agent_resume_forget",
        title = "Agent Resume: Forget This Pane",
        description = "Clear the recorded agent and session ref for this "
            .. "pane, so no future auto-resume fires for it.",
        category = "Agent Resume",
        keywords = "agent resume forget clear remove claude codex pi pane",
        args = { block_id = "string?" },
        run = function(ctx, args)
            local block_id = pane(ctx, args)
            queue_command("forget\t" .. block_id)
            return { output = "forget queued for " .. block_id }
        end,
    })
end
