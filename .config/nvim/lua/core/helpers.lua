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
