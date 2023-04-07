return {
  {
    'lewis6991/gitsigns.nvim',
    config = function()
      require('gitsigns').setup({
        yadm = {
          enable = true
        }
      })
    end
  }
}