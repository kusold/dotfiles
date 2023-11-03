local lsp_formatting = function(bufnr)
  vim.lsp.buf.format({
    filter = function(client)
      return client.supports_method("textDocument/formatting") or client.name == "null-ls"
    end,
    bufnr = bufnr,
  })
end

-- if you want to set up formatting on save, you can use this as a callback
local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

-- TODO(cleanup): Unsure if this is still needed with null-ls
---Common format-on-save for lsp servers that implements formatting
---@param client table
local function lsp_fmt_on_save(client, bufnr)
  if client.supports_method("textDocument/formatting") then
    vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        lsp_formatting(bufnr)
      end,
    })
  end
  -- if client.server_capabilities.documentFormattingProvider then
  --   vim.cmd([[
  --           augroup FORMATTING
  --               autocmd! * <buffer>
  --               autocmd BufWritePre <buffer> lua vim.lsp.buf.format()
  --           augroup END
  --       ]])
  -- end
end

return {
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate", -- :MasonUpdate updates registry contents
    config = function()
      require("mason").setup()
      -- TODO(idea): Enable automatic server setup - https://github.com/williamboman/mason-lspconfig.nvim#automatic-server-setup-advanced-feature
    end,
  },
  {
    "jay-babu/mason-null-ls.nvim",
    opts = {
      formatters = {
        stylua = {},
      },
    },
    --		event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "jose-elias-alvarez/null-ls.nvim",
      "nvim-lua/plenary.nvim",
    },
    config = function(_, opts)
      -- if you want to set up formatting on save, you can use this as a callback
      local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
      local null_ls = require("null-ls")
      require("mason-null-ls").setup({
        automatic_setup = true,
        ensure_installed = GetTableKeys(opts.formatters),
      })
      null_ls.setup({
        sources = { null_ls.builtins.formatting.stylua },
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
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      {
        "b0o/schemastore.nvim",
        "williamboman/mason-lspconfig.nvim",
        dependencies = {
          "williamboman/mason.nvim",
        },
      },
    },
    config = function(_, opts)
      local servers = opts.servers
      local capabilities = require("cmp_nvim_lsp").default_capabilities({
        textDocument = {
          -- used by nvim-ufo
          foldingRange = {
            dynamicRegistration = false,
            lineFoldingOnly = true,
          },
        },
      })

      local function setup(server, server_config)
        local server_opts = vim.tbl_deep_extend("force", {
          capabilities = vim.deepcopy(capabilities),
          on_attach = function(client, bufnr)
            if opts.autoformat then
              lsp_fmt_on_save(client, bufnr)
            end
          end,
        }, server_config or {})

        -- vim.pretty_print(server_opts)
        require("lspconfig")[server].setup(server_opts)
      end

      -- vim.pretty_print(GetTableKeys(servers))
      require("mason-lspconfig").setup({
        ensure_installed = GetTableKeys(servers),
      })
      for server, conf in pairs(servers) do
        if server == "jsonls" then
          conf = {
            settings = {
              json = {
                schemas = require("schemastore").json.schemas(),
                validate = { enable = true },
              },
            },
          }
        elseif server == "yamlls" then
          conf = {
            settings = {
              yaml = {
                schemas = require("schemastore").yaml.schemas(),
              },
            },
          }
        end
        setup(server, conf)
      end
    end,
    opts = {
      autoformat = true, -- autofoormat on save
      servers = {
        ansiblels = {},
        bashls = {},
        diagnosticls = {},
        docker_compose_language_service = {},
        dockerls = {},
        eslint = {},
        gopls = {},
        jdtls = {},
        jsonls = {
          -- Set dynamically
        },
        lua_ls = {
          settings = {
            Lua = {
              runtime = {
                -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
                version = "LuaJIT",
              },
              diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = { "vim" },
              },
              workspace = {
                -- Make the server aware of Neovim runtime files
                library = vim.api.nvim_get_runtime_file("", true),
                checkThirdParty = false,
              },
              telemetry = {
                enable = false,
              },
            },
          },
        },
        marksman = {},
        --  'spectral', -- spectral (openapi) has a few installation issues at the moment
        sqlls = {},
        terraformls = {},
        taplo = {},
        tflint = {},
        tsserver = {},
        yamlls = {
          -- Set dynamically
        },
        -- See https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md for other language servers
      },
    },
  },
}
