return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      -- load the colorscheme here
      vim.cmd([[colorscheme tokyonight-storm]])
    end,
  },
  { "morhetz/gruvbox", lazy = true },
  { "catppuccin/nvim", lazy = true },
  { "projekt0n/github-nvim-theme", lazy = true },
  { "ray-x/aurora", lazy = true },
  { "Mofiqul/dracula.nvim", lazy = true },
}
