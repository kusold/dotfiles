-- Update nvim-cmp capabilities and add them to each language server
local capabilities = require('cmp_nvim_lsp').default_capabilities()

function add_capabilities()
    for _, lsp in ipairs(servers) do
        require('lspconfig')[lsp].setup {
            capabilities = capabilities,
        }
    end
end

add_capabilities()
