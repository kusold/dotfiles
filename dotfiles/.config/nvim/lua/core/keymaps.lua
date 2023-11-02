-- Functional wrapper for mapping custom keybindings
function map(mode, lhs, rhs, opts)
	local options = { noremap = true }
	if opts then
		options = vim.tbl_extend("force", options, opts)
	end
	vim.api.nvim_set_keymap(mode, lhs, rhs, options)
end

-- lazy.nvim doesn't actually support live reloads
-- map("n", "<leader>ar", "<cmd>lua ReloadConfig()<cr>", { desc = "Reload nvim config" })

map("n", "<leader>ca", "<cmd>lua vim.lsp.buf.code_action()<cr>", { desc = "Apply current lsp quickfix" })
