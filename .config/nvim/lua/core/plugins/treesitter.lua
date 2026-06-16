return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- The `main` branch is a full, incompatible rewrite (requires Neovim 0.12+).
    -- It does not support lazy-loading, so load it at startup.
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      -- Parser list (replaces the old `ensure_installed`). `install` is
      -- idempotent and only fetches parsers that are missing.
      require("nvim-treesitter").install({
        "bash",
        "dockerfile",
        "go",
        "hcl",
        "java",
        "javascript",
        "json",
        "lua",
        "typescript",
        "vim",
        "vimdoc",
        "yaml",
      })

      -- The rewrite no longer enables highlighting via a config table; start
      -- tree-sitter per buffer for any filetype whose parser is installed.
      -- pcall keeps it quiet for filetypes without a parser.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },
}
