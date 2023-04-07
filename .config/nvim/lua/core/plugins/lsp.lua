-- TODO(cleanup): Unsure if this is still needed with null-ls
---Common format-on-save for lsp servers that implements formatting
---@param client table
local function lsp_fmt_on_save(client)
  if client.server_capabilities.documentFormattingProvider then
    vim.cmd([[
            augroup FORMATTING
                autocmd! * <buffer>
                autocmd BufWritePre <buffer> lua vim.lsp.buf.format()
            augroup END
        ]])
  end
end

local function null_ls_config()
  -- if you want to set up formatting on save, you can use this as a callback
  local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
  local null_ls = require("null-ls")
  require("mason-null-ls").setup({
    automatic_setup = true,
    ensure_installed = formatters,
  })
  null_ls.setup({
    -- sources = { null_ls.builtins.formatting.stylua, },
    -- you can reuse a shared lspconfig on_attach callback here
    on_attach = function(client, bufnr)
      if client.supports_method("textDocument/formatting") then
        vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
        vim.api.nvim_create_autocmd("BufWritePre", {
          group = augroup,
          buffer = bufnr,
          callback = function()
            vim.lsp.buf.format({ bufnr = bufnr })
          end,
        })
      end
    end,
  })
  require("mason-null-ls").setup_handlers()
end

function add_capabilities(capabilities)
  for _, lsp in ipairs(lsp_servers) do
    require("lspconfig")[lsp].setup({
      capabilities = capabilities,
      on_attach = function(client, bufnr)
        lsp_fmt_on_save(client)
      end,
    })
  end
end

local function cmp_config()
  -- Set up nvim-cmp.
  local cmp = require("cmp")

  cmp.setup({
    window = {
      -- completion = cmp.config.window.bordered(),
      -- documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      ["<C-b>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.abort(),
      ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
      -- SuperTab Behaivor
      ["<Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
          -- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
          -- they way you will only jump inside the snippet region
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        elseif has_words_before() then
          cmp.complete()
        else
          fallback()
        end
      end, { "i", "s" }),
      -- SuperTab Behaivor
      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { "i", "s" }),
    }),
  })

  -- Set configuration for specific filetype.
  cmp.setup.filetype("gitcommit", {
    sources = cmp.config.sources({
      { name = "cmp_git" }, -- You can specify the `cmp_git` source if you were installed it.
    }, {
      { name = "buffer" },
    }),
  })

  -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline({ "/", "?" }, {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
      { name = "buffer" },
    },
  })

  -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline(":", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      { name = "path" },
    }, {
      { name = "cmdline" },
    }),
  })
end

return {
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate", -- :MasonUpdate updates registry contents
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = lsp_servers,
      })
      -- TODO(idea): Enable automatic server setup - https://github.com/williamboman/mason-lspconfig.nvim#automatic-server-setup-advanced-feature
    end,
  },
  {
    "jay-babu/mason-null-ls.nvim",
    --		event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "jose-elias-alvarez/null-ls.nvim",
      "nvim-lua/plenary.nvim",
    },
    config = function()
      --require("your.null-ls.config") -- require your null-ls config here (example below)
      null_ls_config()
    end,
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      add_capabilities(capabilities)
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-nvim-lsp-signature-help",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-nvim-lua",
      {
        "saadparwaiz1/cmp_luasnip",
        dependencies = { "L3MON4D3/LuaSnip" },
      },
    },
    config = function()
      cmp_config()
    end,
  },
}
