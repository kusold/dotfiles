return {
  {
    'j-hui/fidget.nvim',
    config = function()
      require"fidget".setup{}
    end
  },
  {
    'norcalli/nvim-colorizer.lua',
    config = function()
      require('colorizer').setup({
        'css';
	'javascript';
      })
    end
  },
  {
    'kosayoda/nvim-lightbulb',
    dependencies = 'antoinemadec/FixCursorHold.nvim',
    config = function()
      require('nvim-lightbulb').setup({autocmd = {enabled = true}})
    end
  },
  {
    "folke/trouble.nvim",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
      require("trouble").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-file-browser.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require('telescope').setup()
      require("telescope").load_extension "file_browser"
    end,
    keys = {
      { "<space>fb", "<cmd>Telescope file_browser<cr>", "Open file browser" }
    },
  },
  {
    "folke/which-key.nvim",
    config = function (_, opts)
      local wk = require("which-key")
      wk.setup(opts)
      local keymaps = {
        mode = { "n", "v" },
        ["g"] = { name = "+goto" },
        ["gz"] = { name = "+surround" },
        ["]"] = { name = "+next" },
        ["["] = { name = "+prev" },
        ["<leader><tab>"] = { name = "+tabs" },
        ["<leader>b"] = { name = "+buffer" },
        ["<leader>c"] = { name = "+code" },
        ["<leader>f"] = { name = "+file/find" },
        ["<leader>g"] = { name = "+git" },
        ["<leader>gh"] = { name = "+hunks" },
        ["<leader>q"] = { name = "+quit/session" },
        ["<leader>s"] = { name = "+search" },
        ["<leader>u"] = { name = "+ui" },
        ["<leader>w"] = { name = "+windows" },
        ["<leader>x"] = { name = "+diagnostics/quickfix" },
      }
--      if Util.has("noice.nvim") then
 --       keymaps["<leader>sn"] = { name = "+noice" }
  --    end
      wk.register(keymaps) 
    end
  }
}
