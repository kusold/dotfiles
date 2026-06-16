return {
  {
    "saghen/blink.cmp",
    -- Use a release tag so the prebuilt Rust fuzzy-matcher binary is downloaded
    -- automatically (no cargo / build step required).
    version = "1.*",
    -- LuaSnip stays the snippet engine; ensure it loads before blink.
    dependencies = { "L3MON4D3/LuaSnip" },
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      -- Tab to select/accept, Enter to confirm — matches the previous SuperTab setup.
      keymap = { preset = "super-tab" },
      snippets = { preset = "luasnip" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      -- Replaces cmp-nvim-lsp-signature-help.
      signature = { enabled = true },
      completion = {
        -- nvim-cmp showed the docs popup automatically; keep that behaviour.
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      -- Download the prebuilt Rust binary; fall back to the Lua matcher (with a
      -- warning) if it is unavailable, so completion still works without cargo.
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    opts_extend = { "sources.default" },
  },
}
