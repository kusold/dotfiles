---Reload the config and lua scope
---@return nil
function ReloadConfig(ns)
  ns = ns or "core"

  for name, _ in pairs(package.loaded) do
    if name:match("^" .. ns) then
      package.loaded[name] = nil
    end
  end

  dofile(vim.env.MYVIMRC)
end

--
-- Gracefully handle missing colorschemes
function SetColorScheme(scheme)
  local status_ok, _ = pcall(vim.cmd, "colorscheme " .. scheme)
  if not status_ok then
    vim.notify("colorscheme " .. scheme .. " not found!")
  end
end

function GetTableKeys(tab)
  local keyset = {}
  for k, _ in pairs(tab) do
    keyset[#keyset + 1] = k
  end
  return keyset
end
