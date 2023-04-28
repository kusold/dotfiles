local opts = {}
require("core.ftdetect")
require("core.ensure-plugin-manager")
require("core.options")
require("core.helpers")
require("lazy").setup("core.plugins", opts)
SetColorScheme("tokyonight-storm")
-- require("core.filetypes")
require("core.keymaps")
