-- Rex configuration. rex.on is invalid in configuration files (handlers
-- are never called), so the block recorder can't live here; start it as
-- a detached process instead. ~/.config/rex/ensure-recorder.sh, run from
-- every terminal shell, is the fallback that starts it if this fails.
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
    os.getenv("HOME") .. "/.config/rex/recorder.lua", "--all" })

-- Keep the agents' self-report hooks installed; the shell hooks no
-- longer do this now that resume lives on the Rex side.
start({ "/bin/sh", "-c",
    os.getenv("HOME") .. "/.config/rex/install-hooks.sh --ensure" })
