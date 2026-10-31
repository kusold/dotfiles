-- Rex configuration. rex.on is invalid in configuration files (handlers
-- are never called), so the block recorder can't live here; start it as
-- a detached process instead. ~/.config/rex/ensure-recorder.sh, run from
-- every terminal shell, is the fallback that starts it if this fails.
local dir = os.getenv("REX_BIN_DIR")
local exe = (dir and dir .. "/rex") or "rex"
local ok, err = pcall(function()
    rex.exec.start(
        { exe, "do", os.getenv("HOME") .. "/.config/rex/recorder.lua", "--all" },
        { detach = true })
end)
if not ok then
    print("rex init: could not start the agent recorder: " .. tostring(err))
end

-- Keep the agents' self-report hooks installed; the shell hooks no
-- longer do this now that resume lives on the Rex side.
pcall(function()
    rex.exec.start(
        { "/bin/sh", "-c",
          os.getenv("HOME") .. "/.config/rex/install-hooks.sh --ensure" },
        { detach = true })
end)
