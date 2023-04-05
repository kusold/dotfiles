"│-v-1 │ load plugins
"└─┬───┴─┬────────────────
  "│-v-2 │ vim-plug                    - junegunn/vim-plug (init vim-plug)
  "└─────┴─────────
    " Install vim-plug
    runtime ./install-vim-plug.vim
    
    " Load vim-plug
    call plug#begin()

  "│-v-2 │ mason                    - williamboman/mason.nvim (install lsp)
  "└─────┴─────────
    Plug 'williamboman/mason.nvim', { 'do': ':MasonUpdate' }
    Plug 'williamboman/mason-lspconfig.nvim',
    
  "│-v-2 │ nvim-cmp                    - hrsh7th/nvim-cmp (autocomplete)
  "└─────┴─────────
    Plug 'neovim/nvim-lspconfig'
    Plug 'hrsh7th/cmp-nvim-lsp'
    Plug 'hrsh7th/cmp-buffer'
    Plug 'hrsh7th/cmp-path'
    Plug 'hrsh7th/cmp-cmdline'
    Plug 'hrsh7th/nvim-cmp'
    " --
    " For luasnip users.
    Plug 'L3MON4D3/LuaSnip'
    Plug 'saadparwaiz1/cmp_luasnip'


  "│-v-2 │ vim-plug                    - junegunn/vim-plug (load plugins)
  "└─────┴─────────
    call plug#end()
    
"│-v-1 │ configure plugins
"└─────┴──────────────────
""" Core plugin configuration (lua)
lua << EOF
servers = {
  'ansiblels',
  'bashls',
  'diagnosticls',
  'docker_compose_language_service',
  'dockerls',
  'gopls',
  'lspconfig',
  'sqlls',
  'terraformls',
  'tflint',
  'tsserver',
  'yamlls',
  -- See https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md for other language servers
}
require('mason-config')
require('nvim-cmp-config')
require('lspconfig-config')
EOF

