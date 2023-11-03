return {
  {
    "jsecchiero/vim-sops",
    init = function()
      vim.g.sops_files_match = "{*.sops.*,*.sops}"
    end,
  },
}
