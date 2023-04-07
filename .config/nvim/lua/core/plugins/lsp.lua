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

function add_capabilities()
    for _, lsp in ipairs(lsp_servers) do
        require('lspconfig')[lsp].setup {
            capabilities = capabilities,
	    on_attach = function (client, bufnr) 
              lsp_fmt_on_save(client)
	    end
        }
    end
end

local function cmp_config()
  -- Set up nvim-cmp.
  local cmp = require'cmp'
  
  cmp.setup({
    window = {
      -- completion = cmp.config.window.bordered(),
      -- documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<C-e>'] = cmp.mapping.abort(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
      
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
  cmp.setup.filetype('gitcommit', {
    sources = cmp.config.sources({
      { name = 'cmp_git' }, -- You can specify the `cmp_git` source if you were installed it.
    }, {
      { name = 'buffer' },
    })
  })
  
  -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline({ '/', '?' }, {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
      { name = 'buffer' }
    }
  })
  
  -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline(':', {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      { name = 'path' }
    }, {
      { name = 'cmdline' }
    })
  })
end

return {
 {
   "williamboman/mason.nvim",
   build = ":MasonUpdate", -- :MasonUpdate updates registry contents
   dependencies = {
     'williamboman/mason-lspconfig.nvim',
   },
   config = function()
     require("mason").setup()
     require("mason-lspconfig").setup({
       ensure_installed = lsp_servers
     })
-- TODO(idea): Enable automatic server setup - https://github.com/williamboman/mason-lspconfig.nvim#automatic-server-setup-advanced-feature
    end
  },
  {
    'neovim/nvim-lspconfig',
    config = function()
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
      add_capabilities()
    end,
  },
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-nvim-lsp-signature-help',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
      'hrsh7th/cmp-nvim-lua',
      {
        'saadparwaiz1/cmp_luasnip',
        dependencies = {'L3MON4D3/LuaSnip'}
      }
    },
    config = function ()
      cmp_config()
    end
  },
}

