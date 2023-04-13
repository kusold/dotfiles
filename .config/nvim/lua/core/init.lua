lsp_servers = {
  "ansiblels",
  "bashls",
  "diagnosticls",
  "docker_compose_language_service",
  "dockerls",
  "eslint",
  "gopls",
  "jdtls",
  "jsonls",
  "lua_ls",
  "marksman",
  --  'spectral', -- spectral (openapi) has a few installation issues at the moment
  "sqlls",
  "terraformls",
  "taplo",
  "tflint",
  "tsserver",
  "yamlls",
  -- See https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md for other language servers
}
formatters = {
  "stylua",
}

require("core.ensure-plugin-manager")
require("core.options")
require("core.helpers")
require("lazy").setup("core.plugins", opts)
require("core.filetypes")
require("core.mappings")
