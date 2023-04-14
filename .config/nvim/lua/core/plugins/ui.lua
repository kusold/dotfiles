return {
  {
    "j-hui/fidget.nvim",
    config = function()
      require("fidget").setup({})
    end,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    config = function()
      vim.opt.list = true
      vim.opt.listchars:append("space:⋅")
      vim.opt.listchars:append("eol:↴")

      require("indent_blankline").setup({
        -- Highlights current indentation level
        show_current_context = true,
        show_current_context_start = true,
        -- Shows characters for whitespace
        show_end_of_line = true,
        space_char_blankline = " ",
      })
    end,
  },
  {
    "norcalli/nvim-colorizer.lua",
    config = function()
      require("colorizer").setup({
        "css",
        "javascript",
      })
    end,
  },
  {
    "kosayoda/nvim-lightbulb",
    dependencies = "antoinemadec/FixCursorHold.nvim",
    config = function()
      require("nvim-lightbulb").setup({ autocmd = { enabled = true } })
    end,
  },
  {
    "folke/trouble.nvim",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
      require("trouble").setup({
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      })
    end,
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>ft", "<cmd>Neotree toggle<cr>", desc = "NeoTree" },
      { "<leader>bt", "<cmd>Neotree float buffers<cr>", desc = "NeoTree" },
      { "<leader>gt", "<cmd>Neotree float git_status<cr>", desc = "NeoTree" },
    },
    branch = "v2.x",
    config = function()
      vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])
      require("neo-tree").setup()
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-file-browser.nvim",
      "nvim-tree/nvim-web-devicons",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    config = function()
      require("telescope").setup({
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
        },
      })
      require("telescope").load_extension("file_browser")
      require("telescope").load_extension("fzf")
    end,
    keys = {
      { "<space>fb", "<cmd>Telescope file_browser<cr>", desc = "Telescope file browser" },
      { "<space>ff", "<cmd>Telescope find_files<cr>", desc = "Telescope file finder" },
      { "<space>fs", "<cmd>Telescope live_grep<cr>", desc = "Telescope find string" },
      { "<space>bf", "<cmd>Telescope buffers<cr>", desc = "Telescope find buffers" },
      { "<space>fh", "<cmd>Telescope help_tags<cr>", desc = "Telescope find help tags" },
    },
  },
  {
    "folke/which-key.nvim",
    config = function(_, opts)
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
        ["<leader>a"] = { name = "+admin" },
      }
      --      if Util.has("noice.nvim") then
      --       keymaps["<leader>sn"] = { name = "+noice" }
      --    end
      wk.register(keymaps)
    end,
  },
}
