return {
  {
    -- lazy.nvim calls require("mason").setup(opts) for us; the registry now
    -- downloads automatically, so no `config`, `build`, or `:MasonUpdate` needed.
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- Toggle via vim.g.use_mason_tools (lua/core/options.lua). Disable to let
    -- home-manager provide these tools instead of Mason.
    enabled = function()
      return vim.g.use_mason_tools ~= false
    end,
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      -- Mason package names. stylua backs conform's Lua formatting; add more
      -- CLI tools / formatters / linters here as you adopt them.
      ensure_installed = { "stylua" },
    },
  },
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      -- stylua is installed via mason and found on PATH (mason prepends its bin).
      formatters_by_ft = {
        lua = { "stylua" },
      },
      -- Format on save. Filetypes without a formatter above fall back to the
      -- attached LSP's formatting (e.g. gopls), preserving the previous behaviour.
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
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
      local capabilities = require("blink.cmp").get_lsp_capabilities({
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
