if vim.g.vscode then
-- VSCode extension
else
-- ordinary Neovim
  lsp_servers = {
    'ansiblels',
    'bashls',
    'diagnosticls',
    'docker_compose_language_service',
    'dockerls',
    'eslint',
    'gopls',
    'jdtls',
    'jsonls',
    'marksman',
  --  'spectral', -- spectral (openapi) has a few installation issues at the moment
    'sqlls',
    'terraformls',
    'taplo',
    'tflint',
    'tsserver',
    'yamlls',
    -- See https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md for other language servers
  }
  require('core')

end

