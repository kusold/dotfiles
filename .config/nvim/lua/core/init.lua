-- Need to set a custom lockfile location since NixOS symlinks the lockfile as read-only
local lockfile_path = os.getenv("LAZY_LOCKFILE") or vim.fn.stdpath("config") .. "/lazy-lock.json"

local lazyopts = {
    lockfile = lockfile_path,
}
require("core.ftdetect")
require("core.ensure-plugin-manager")
require("core.options")
require("core.helpers")
require("lazy").setup("core.plugins", lazyopts)
SetColorScheme("tokyonight-storm")
-- require("core.filetypes")
require("core.keymaps")
