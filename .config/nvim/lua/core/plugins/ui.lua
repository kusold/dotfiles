-- Custom lualine components. The worktree name is resolved asynchronously
-- (one `git` call per buffer) and cached in a buffer variable, so the
-- statusline render path itself never shells out.
local lualine_icons = {
  worktree = vim.fn.nr2char(0xf126, 1), -- nf-fa-code_fork
  lsp = vim.fn.nr2char(0xf085, 1), -- nf-fa-cogs
  recording = vim.fn.nr2char(0xf111, 1), -- nf-fa-circle (record dot)
}

local function worktree_name()
  return vim.b.lualine_worktree or ""
end

local function has_worktree()
  return (vim.b.lualine_worktree or "") ~= ""
end

-- Show the worktree only when the buffer lives in a *linked* worktree
-- (`git worktree add`), not the primary checkout. Detected by comparing the
-- per-worktree git-dir against the shared common-dir: they differ only in a
-- linked worktree. Label is the worktree's top-level directory name.
local function update_worktree(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.fn.executable("git") == 0 or not vim.system then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local fname = vim.api.nvim_buf_get_name(buf)
  local dir = fname ~= "" and vim.fn.fnamemodify(fname, ":h") or vim.fn.getcwd()
  vim.system(
    { "git", "-C", dir, "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir", "--show-toplevel" },
    { text = true },
    function(res)
      local wt = ""
      if res.code == 0 then
        local out = vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
        local gitdir, common, top = out[1], out[2], out[3]
        if gitdir and common and top and gitdir ~= common then
          wt = vim.fn.fnamemodify(top, ":t")
        end
      end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].lualine_worktree ~= wt then
          vim.b[buf].lualine_worktree = wt
          pcall(require("lualine").refresh)
        end
      end)
    end
  )
end

local function lsp_clients()
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    names[#names + 1] = client.name
  end
  return table.concat(names, ", ")
end

local function lsp_attached()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end

-- Macro recording indicator, e.g. "REC @q". Native cmdline shows this too, but
-- not when 'cmdheight' is 0, and the statusline keeps it visible regardless.
local function macro_recording()
  local reg = vim.fn.reg_recording()
  return reg ~= "" and ("REC @" .. reg) or ""
end

local function is_recording()
  return vim.fn.reg_recording() ~= ""
end

return {
  {
    "j-hui/fidget.nvim",
    config = function()
      require("fidget").setup({})
    end,
  },
  {
    -- Statusline. Branch/diff come from gitsigns and diagnostics from the LSP
    -- automatically; mini.icons (mocked as nvim-web-devicons) supplies the icons.
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    config = function()
      require("lualine").setup({
        options = {
          theme = "auto", -- follows the active colorscheme (tokyonight, catppuccin, ...)
          globalstatus = true, -- one statusline shared across all splits (laststatus=3)
        },
        sections = {
          lualine_a = { "mode" },
          -- Git context: branch, the worktree (only inside a linked worktree),
          -- working-tree diff stats, and per-file diagnostics (error/warn/etc.).
          lualine_b = {
            "branch",
            { worktree_name, icon = lualine_icons.worktree, cond = has_worktree },
            "diff",
            { "diagnostics", sources = { "nvim_diagnostic" } },
          },
          lualine_c = {
            { "filename", path = 1 }, -- path relative to cwd
            { macro_recording, icon = lualine_icons.recording, cond = is_recording, color = "DiagnosticError" },
          },
          -- Attached LSP server names + filetype.
          lualine_x = {
            { lsp_clients, icon = lualine_icons.lsp, cond = lsp_attached },
            "filetype",
          },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      })

      local group = vim.api.nvim_create_augroup("Lualine", { clear = true })

      -- Resolve the worktree off the render path on buffer/dir changes, plus
      -- once now for the buffer that's already open when lualine loads.
      vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
        group = group,
        callback = function(args)
          update_worktree(args.buf)
        end,
      })
      update_worktree(0)

      -- Refresh immediately when macro recording starts/stops so the indicator
      -- doesn't lag a redraw behind (scheduled so reg_recording() is settled).
      vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
        group = group,
        callback = function()
          vim.schedule(require("lualine").refresh)
        end,
      })
    end,
  },
  {
    -- Icon provider (replaces nvim-web-devicons). The package.preload shim makes
    -- any plugin that does `require("nvim-web-devicons")` transparently receive
    -- mini.icons, so neo-tree / telescope / trouble keep working without listing
    -- an icon plugin as a dependency. `init` runs at startup even though the
    -- plugin itself stays lazy until first required.
    "nvim-mini/mini.icons",
    lazy = true,
    opts = {},
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },
  {
    -- Indentation guides + scope (replaces indent-blankline.nvim). Only the
    -- indent module is enabled; snacks.nvim ships many others, all off by default.
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      indent = { enabled = true },
    },
  },
  {
    "brenoprata10/nvim-highlight-colors",
    config = function()
      require("nvim-highlight-colors").setup({
        render = "virtual",
        virtual_symbol = "■",
        virtual_symbol_prefix = "",
        virtual_symbol_suffix = " ",
        virtual_symbol_position = "inline",
      })
    end,
  },
  {
    "kosayoda/nvim-lightbulb",
    config = function()
      require("nvim-lightbulb").setup({ autocmd = { enabled = true } })
    end,
  },
  {
    "folke/trouble.nvim",
    config = function()
      require("trouble").setup({
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      })
    end,
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>ft", "<cmd>Neotree toggle<cr>", desc = "NeoTree" },
      { "<leader>bt", "<cmd>Neotree float buffers<cr>", desc = "NeoTree" },
      { "<leader>gt", "<cmd>Neotree float git_status<cr>", desc = "NeoTree" },
    },
    branch = "v3.x",
    config = function()
      -- vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])
      require("neo-tree").setup()
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-file-browser.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    config = function()
      require("telescope").setup({
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
        },
        defaults = {
          mappings = {
            i = {
              -- map actions.which_key to <C-h> (default: <C-/>)
              -- actions.which_key shows the mappings for your picker,
              -- e.g. git_{create, delete, ...}_branch for the git_branches picker
              ["<C-h>"] = "which_key",
            },
          },
        },
      })
      require("telescope").load_extension("file_browser")
      require("telescope").load_extension("fzf")
    end,
    keys = {
      { "<leader>fb", "<cmd>Telescope file_browser<cr>", desc = "Telescope file browser" },
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Telescope file finder" },
      { "<leader>fs", "<cmd>Telescope live_grep<cr>", desc = "Telescope find string" },
      { "<leader>bf", "<cmd>Telescope buffers<cr>", desc = "Telescope find buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Telescope find help tags" },
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        mode = { "n", "v" },
        { "g", group = "goto" },
        { "gz", group = "surround" },
        { "]", group = "next" },
        { "[", group = "prev" },
        { "<leader><tab>", group = "tabs" },
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "file/find" },
        { "<leader>g", group = "git" },
        { "<leader>gh", group = "hunks" },
        { "<leader>q", group = "quit/session" },
        { "<leader>s", group = "search" },
        { "<leader>u", group = "ui" },
        { "<leader>w", group = "windows" },
        { "<leader>x", group = "diagnostics/quickfix" },
        { "<leader>a", group = "admin" },
      },
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)
      local keymaps = {}
      --      if Util.has("noice.nvim") then
      --       keymaps{"<leader>sn", group = "noice" }
      --    end
      wk.add(keymaps)
    end,
  },
}
