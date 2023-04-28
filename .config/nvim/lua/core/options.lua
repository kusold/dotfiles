vim.g.mapleader = " "

vim.opt.foldcolumn = "1"     -- '0' is not bad
vim.opt.foldenable = true
vim.opt.foldlevel = 99       -- Using ufo provider need a large value
vim.opt.foldlevelstart = 99
vim.opt.ignorecase = true    -- Ignore case
vim.opt.smartcase = true     -- Don't ignore case with capitals
vim.opt.splitbelow = true    -- Put new windows below current
vim.opt.splitkeep = "screen" -- Stabalize cursor when windows open
vim.opt.splitright = true    -- Put new windows right of current
vim.opt.termguicolors = true -- True color support
