return {
  {
    -- lazy.nvim calls require("mason").setup(opts) for us; the registry now
    -- downloads automatically, so no `config`, `build`, or `:MasonUpdate` needed.
    "mason-org/mason.nvim",
    opts = {},
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
      "mason-org/mason.nvim",
      "nvimtools/none-ls.nvim",
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
          if client:supports_method("textDocument/formatting") then
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
        "mason-org/mason-lspconfig.nvim",
        dependencies = {
          "mason-org/mason.nvim",
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

      -- Neovim 0.11+ native LSP: apply shared capabilities to every server.
      -- lspconfig ships per-server defaults in its `lsp/<name>.lua` files; these
      -- overrides are merged on top by `vim.lsp.config`.
      vim.lsp.config("*", {
        capabilities = capabilities,
      })

      -- Format on save for any attached client that supports it.
      if opts.autoformat then
        local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
        vim.api.nvim_create_autocmd("LspAttach", {
          callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client and client:supports_method("textDocument/formatting") then
              vim.api.nvim_clear_autocmds({ group = augroup, buffer = args.buf })
              vim.api.nvim_create_autocmd("BufWritePre", {
                group = augroup,
                buffer = args.buf,
                callback = function()
                  vim.lsp.buf.format({ bufnr = args.buf })
                end,
              })
            end
          end,
        })
      end

      -- Per-server overrides layered on top of lspconfig's shipped defaults.
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
        if conf and next(conf) ~= nil then
          vim.lsp.config(server, conf)
        end
      end

      -- Install missing servers and auto-enable them via `vim.lsp.enable()`
      -- (mason-lspconfig's `automatic_enable` defaults to true).
      require("mason-lspconfig").setup({
        ensure_installed = GetTableKeys(servers),
      })
    end,
    opts = {
      autoformat = true, -- autoformat on save
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
        ts_ls = {},
        yamlls = {
          -- Set dynamically
        },
        -- See https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md for other language servers
      },
    },
  },
}
