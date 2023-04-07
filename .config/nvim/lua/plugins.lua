-- Auto install packer if it isn't present
local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
    vim.cmd [[packadd packer.nvim]]
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

--vim.cmd [[packadd packer.nvim]]

-- Autorun PackerCompile whenever plugins.lua is updated
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerCompile
  augroup end
]])

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'
  -- mason installs packages such as language servers
  use {
   'williamboman/mason.nvim',
    run = ":MasonUpdate",
  }
  use 'williamboman/mason-lspconfig.nvim'

  --lsp
  use 'neovim/nvim-lspconfig'
  use 'hrsh7th/cmp-nvim-lsp'
  use 'hrsh7th/cmp-nvim-lsp-signature-help'
  use 'hrsh7th/cmp-buffer'
  use 'hrsh7th/cmp-path'
  use 'hrsh7th/cmp-cmdline'
  use 'hrsh7th/cmp-nvim-lua'
  use 'hrsh7th/nvim-cmp'
  -- comments
  use {
    'numToStr/Comment.nvim',
    config = function()
        require('Comment').setup()
    end
  }
  -- snippets
  use {
    'L3MON4D3/LuaSnip',
    -- follow latest release.
    tag = 'v1.*',
    -- install jsregexp (optional!:).
    run = "make install_jsregexp",
  }
  use 'saadparwaiz1/cmp_luasnip'
  -- tree-sitter - https://github.com/nvim-treesitter/nvim-treesitter/wiki/Installation#packernvim
  use {
    'nvim-treesitter/nvim-treesitter',
     run = function()
       local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
       ts_update()
     end,
  }
  -- git
  use {
    'lewis6991/gitsigns.nvim',
    config = function()
      require('gitsigns').setup({
        yadm = {
          enable = true
        }
      })
    end
  }
  -- UI
  use {
    'j-hui/fidget.nvim',
    config = function()
      require"fidget".setup{}
    end
  }
  use {
    'norcalli/nvim-colorizer.lua',
    config = function()
      require('colorizer').setup({
        'css';
	'javascript';
      })
    end
  }
  use {
    'kosayoda/nvim-lightbulb',
    requires = 'antoinemadec/FixCursorHold.nvim',
    config = function()
      require('nvim-lightbulb').setup({autocmd = {enabled = true}})
    end
  }
  -- Lua
  use {
    "folke/trouble.nvim",
    requires = "nvim-tree/nvim-web-devicons",
    config = function()
      require("trouble").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
  }
  use {
    "nvim-telescope/telescope-file-browser.nvim",
    requires = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    config = function()
      require('telescope').setup()
      require("telescope").load_extension "file_browser"

      vim.api.nvim_set_keymap(
        "n",
        "<space>fb",
        ":Telescope file_browser",
        { noremap = true }
      )
    end
  }
  -- themes
  use { 'folke/tokyonight.nvim' }
  use { 'morhetz/gruvbox' }
  use { 'catppuccin/nvim' }
  use { 'projekt0n/github-nvim-theme' }
  use { 'ray-x/aurora' }
  use { 'Mofiqul/dracula.nvim' }


  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if packer_bootstrap then
    require('packer').sync()
  end
end)

