require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = servers
})
-- TODO(idea): Enable automatic server setup - https://github.com/williamboman/mason-lspconfig.nvim#automatic-server-setup-advanced-feature
