return {
  {
    -- This plugin also supports the ability to stage hunks via git
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        yadm = {
          enable = true,
        },
      })
    end,
  },
}
