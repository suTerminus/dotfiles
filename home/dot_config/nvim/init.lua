-- ~/.config/nvim/init.lua
-- managed by chezmoi via home/dot_config/nvim/init.lua
--
-- Single-file Neovim config inspired by kickstart.nvim. Catppuccin
-- colorscheme follows macOS appearance via f-person/auto-dark-mode.nvim.
-- Plugin manager: lazy.nvim (auto-bootstraps).

-- Leader keys must be set before lazy.nvim loads.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ----- Bootstrap lazy.nvim -------------------------------------------------
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ----- Core options --------------------------------------------------------
local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.signcolumn = 'yes'
opt.cursorline = true
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true
opt.splitright = true
opt.splitbelow = true
opt.termguicolors = true
opt.background = 'dark'
opt.updatetime = 250
opt.timeoutlen = 300
opt.completeopt = 'menuone,noselect'
opt.undofile = true
opt.swapfile = false
opt.backup = false
opt.clipboard = 'unnamedplus'
opt.mouse = 'a'
opt.list = true
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- ----- Keymaps -------------------------------------------------------------
local map = vim.keymap.set
map('n', '<Esc>', '<cmd>nohlsearch<CR>')
map('n', '<leader>e', '<cmd>Neotree toggle<CR>', { desc = 'File explorer' })
map('n', '<leader>w', '<cmd>w<CR>', { desc = 'Save' })
map('n', '<leader>q', '<cmd>qa<CR>', { desc = 'Quit all' })
map('n', '<leader>x', '<cmd>bdelete<CR>', { desc = 'Close buffer' })
-- Window navigation
map('n', '<C-h>', '<C-w>h', { desc = 'Window left' })
map('n', '<C-j>', '<C-w>j', { desc = 'Window down' })
map('n', '<C-k>', '<C-w>k', { desc = 'Window up' })
map('n', '<C-l>', '<C-w>l', { desc = 'Window right' })
-- Move lines (visual)
map('v', 'J', ":m '>+1<CR>gv=gv")
map('v', 'K', ":m '<-2<CR>gv=gv")
-- Keep cursor centred
map('n', '<C-d>', '<C-d>zz')
map('n', '<C-u>', '<C-u>zz')
map('n', 'n', 'nzzzv')
map('n', 'N', 'Nzzzv')

-- ----- Plugins via lazy.nvim ----------------------------------------------
require('lazy').setup({

  -- Catppuccin colorscheme.
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,
    config = function()
      require('catppuccin').setup({
        flavour = 'mocha',
        background = { light = 'latte', dark = 'mocha' },
        transparent_background = false,
        integrations = {
          cmp = true,
          gitsigns = true,
          neotree = true,
          telescope = { enabled = true },
          treesitter = true,
          mason = true,
          which_key = true,
        },
      })
      vim.cmd.colorscheme('catppuccin')
    end,
  },

  -- Auto-switch background based on macOS appearance.
  {
    'f-person/auto-dark-mode.nvim',
    config = function()
      require('auto-dark-mode').setup({
        update_interval = 1000,
        set_dark_mode = function()
          vim.api.nvim_set_option_value('background', 'dark', {})
          vim.cmd.colorscheme('catppuccin-mocha')
        end,
        set_light_mode = function()
          vim.api.nvim_set_option_value('background', 'light', {})
          vim.cmd.colorscheme('catppuccin-latte')
        end,
      })
    end,
  },

  -- Statusline.
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('lualine').setup({
        options = { theme = 'catppuccin', globalstatus = true, section_separators = '', component_separators = '|' },
      })
    end,
  },

  -- File explorer.
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      'MunifTanjim/nui.nvim',
    },
    config = function()
      require('neo-tree').setup({
        close_if_last_window = true,
        filesystem = {
          follow_current_file = { enabled = true },
          use_libuv_file_watcher = true,
        },
        window = {
          mappings = {
            -- Live preview: P toggles a side preview that updates as you
            -- move the cursor through the tree. Esc dismisses.
            ['P']     = { 'toggle_preview', config = { use_float = false, use_image_nvim = false } },
            ['<C-p>'] = { 'toggle_preview', config = { use_float = true } },
          },
        },
      })
    end,
  },

  -- Fuzzy finder.
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      -- C-backed fzf algorithm for telescope (much faster sorting on
      -- large repos). Build step compiles the native lib.
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    keys = {
      { '<leader>ff', '<cmd>Telescope find_files<CR>', desc = 'Find files' },
      { '<leader>FF', function()
          require('telescope.builtin').find_files({ hidden = true, no_ignore = true })
        end, desc = 'Find files (incl. hidden + gitignored)' },
      { '<leader>fg', '<cmd>Telescope live_grep<CR>',  desc = 'Live grep' },
      { '<leader>fb', '<cmd>Telescope buffers<CR>',    desc = 'Buffers' },
      { '<leader>fh', '<cmd>Telescope help_tags<CR>',  desc = 'Help' },
      { '<leader>fr', '<cmd>Telescope oldfiles<CR>',   desc = 'Recent files' },
    },
    config = function()
      require('telescope').setup({
        -- Alternative: make <leader>ff itself show hidden + gitignored files
        -- by uncommenting the block below (and dropping <leader>FF above).
        -- pickers = {
        --   find_files = {
        --     hidden = true,
        --     no_ignore = true,
        --   },
        -- },
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = 'smart_case',
          },
        },
      })
      pcall(require('telescope').load_extension, 'fzf')
    end,
  },

  -- Treesitter (syntax highlighting + structural awareness).
  -- Pinned to `master` because v1.0 restructured the public modules
  -- and `nvim-treesitter.configs` no longer exists at the new path.
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = {
          'bash', 'go', 'json', 'lua', 'markdown', 'markdown_inline',
          'python', 'rust', 'toml', 'tsx', 'typescript', 'vim', 'vimdoc',
          'yaml',
        },
        sync_install = false,
        auto_install = false, -- mid-session fetches race with telescope preview; use the run-once bootstrap instead.
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
          disable = function(_, buf)
            -- Skip very large files; treesitter chokes + slows scroll.
            local max_filesize = 200 * 1024
            local ok, stats = pcall(vim.uv and vim.uv.fs_stat or vim.loop.fs_stat,
              vim.api.nvim_buf_get_name(buf))
            if ok and stats and stats.size > max_filesize then return true end
          end,
        },
        indent = {
          enable = true,
          -- markdown indent module raises "Invalid range" on certain
          -- list/blockquote structures; let nvim's built-in indent
          -- handle .md instead.
          disable = { 'markdown', 'markdown_inline', 'yaml' },
        },
      })
    end,
  },

  -- Git signs in the gutter.
  {
    'lewis6991/gitsigns.nvim',
    config = function() require('gitsigns').setup() end,
  },

  -- Comment toggling: gcc / gc{motion}.
  { 'numToStr/Comment.nvim', config = true },

  -- LSP + Mason. Uses the nvim 0.11+ vim.lsp.config / vim.lsp.enable
  -- API; the old `require('lspconfig').<server>.setup({})` pattern is
  -- deprecated. mason-lspconfig v2+ calls vim.lsp.enable() for every
  -- server in `ensure_installed` automatically (automatic_enable=true
  -- is the default).
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'williamboman/mason.nvim', config = true },
      'williamboman/mason-lspconfig.nvim',
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      -- Global defaults applied to every server.
      vim.lsp.config('*', { capabilities = capabilities })

      -- Per-server overrides.
      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      })

      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls', 'gopls', 'pyright', 'ts_ls', 'rust_analyzer',
          'yamlls', 'jsonls', 'bashls',
        },
        -- automatic_enable defaults to true: mason-lspconfig will call
        -- vim.lsp.enable() for each installed server.
      })

      -- Keymaps when an LSP server attaches to a buffer.
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('user-lsp-attach', { clear = true }),
        callback = function(event)
          local b = { buffer = event.buf, silent = true }
          map('n', 'gd',         vim.lsp.buf.definition,  b)
          map('n', 'gr',         vim.lsp.buf.references,  b)
          map('n', 'K',          vim.lsp.buf.hover,       b)
          map('n', '<leader>rn', vim.lsp.buf.rename,      b)
          map('n', '<leader>ca', vim.lsp.buf.code_action, b)
        end,
      })
    end,
  },

  -- Completion.
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
    },
    config = function()
      local cmp = require('cmp')
      local luasnip = require('luasnip')
      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, { { name = 'buffer' }, { name = 'path' } }),
      })
    end,
  },

  -- Which-key (prompts you with leader-bindings).
  { 'folke/which-key.nvim', config = function() require('which-key').setup() end },

  -- Indent guides.
  { 'lukas-reineke/indent-blankline.nvim', main = 'ibl', config = function()
    require('ibl').setup({ indent = { char = '│' }, scope = { enabled = false } })
  end },
})
