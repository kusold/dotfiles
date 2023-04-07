-- Update nvim-cmp capabilities and add them to each language server
local capabilities = require('cmp_nvim_lsp').default_capabilities()

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
    for _, lsp in ipairs(servers) do
        require('lspconfig')[lsp].setup {
            capabilities = capabilities,
	    on_attach = function (client, bufnr) 
              lsp_fmt_on_save(client)
	    end
        }
    end
end

add_capabilities()
