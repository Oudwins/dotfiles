-- See `:help gitsigns` to understand what the configuration keys do
-- Adds git related signs to the gutter, as well as utilities for managing changes
-- Adds plugin and recommended keymaps

return {
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = function(bufnr)
        local gitsigns = require 'gitsigns'

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map('n', ']c', function()
          if vim.wo.diff then
            vim.cmd.normal { ']c', bang = true }
          else
            gitsigns.nav_hunk 'next'
          end
        end, { desc = 'Jump to next git [c]hange' })

        map('n', '[c', function()
          if vim.wo.diff then
            vim.cmd.normal { '[c', bang = true }
          else
            gitsigns.nav_hunk 'prev'
          end
        end, { desc = 'Jump to previous git [c]hange' })

        -- Actions
        -- visual mode
        map('v', '<leader>hs', function()
          gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [s]tage hunk' })
        map('v', '<leader>hr', function()
          gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [r]eset hunk' })
        -- normal mode
        map('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'git [s]tage hunk' })
        map('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk' })
        map('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'git [S]tage buffer' })
        map('n', '<leader>hu', gitsigns.stage_hunk, { desc = 'git [u]ndo stage hunk' })
        map('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'git [R]eset buffer' })
        map('n', '<leader>hp', gitsigns.preview_hunk, { desc = 'git [p]review hunk' })
        map('n', '<leader>hb', gitsigns.blame_line, { desc = 'git [b]lame line' })
        map('n', '<leader>hd', gitsigns.diffthis, { desc = 'git [d]iff against index' })
        map('n', '<leader>hD', function()
          gitsigns.diffthis '@'
        end, { desc = 'git [D]iff against last commit' })
        -- Toggles
        map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        map('n', '<leader>tD', gitsigns.preview_hunk_inline, { desc = '[T]oggle git show [D]eleted' })
      end,
    },
  },
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles' },
    keys = {
      {
        '<leader>gd',
        function()
          if next(require('diffview.lib').views) == nil then
            vim.cmd 'DiffviewOpen'
          else
            vim.cmd 'DiffviewClose'
          end
        end,
        desc = 'Toggle Diffview',
      },
    },
    opts = {
      -- Would be good to make ]c go to next change in any file (i.e cycly through files)
      -- TODO: Doesn't seem to work. Need to investigate why. What I want here is to not start with folds
      hooks = {
        view_opened = function()
          vim.cmd 'normal! zR'
        end,
      },
      -- This doesn't seem to work either
      -- view = {
      --   file_panel = {
      --     listing_style = 'list',
      --   },
      -- },

      view = {
        -- Configure the layout and behavior of different types of views.
        -- Available layouts:
        --  'diff1_plain'
        --    |'diff2_horizontal'
        --    |'diff2_vertical'
        --    |'diff3_horizontal'
        --    |'diff3_vertical'
        --    |'diff3_mixed'
        --    |'diff4_mixed'
        -- For more info, see |diffview-config-view.x.layout|.
        -- default = {
        --   -- Config for changed files, and staged files in diff views.
        --   layout = "diff2_horizontal",
        --   disable_diagnostics = false,  -- Temporarily disable diagnostics for diff buffers while in the view.
        --   winbar_info = false,          -- See |diffview-config-view.x.winbar_info|
        -- },
        -- merge_tool = {
        --   -- Config for conflicted files in diff views during a merge or rebase.
        --   layout = "diff3_horizontal",
        --   disable_diagnostics = true,   -- Temporarily disable diagnostics for diff buffers while in the view.
        --   winbar_info = true,           -- See |diffview-config-view.x.winbar_info|
        -- },
        -- file_history = {
        --   -- Config for changed files in file history views.
        --   layout = "diff2_horizontal",
        --   disable_diagnostics = false,  -- Temporarily disable diagnostics for diff buffers while in the view.
        --   winbar_info = false,          -- See |diffview-config-view.x.winbar_info|
        -- },
      },
      file_panel = {
        listing_style = 'list', -- One of 'list' or 'tree'
        -- tree_options = {                    -- Only applies when listing_style is 'tree'
        --   flatten_dirs = true,              -- Flatten dirs that only contain one single dir
        --   folder_statuses = "only_folded",  -- One of 'never', 'only_folded' or 'always'.
        -- },
        -- win_config = {                      -- See |diffview-config-win_config|
        --   position = "left",
        --   width = 35,
        --   win_opts = {},
        -- },
      },
      -- file_history_panel = {
      --   log_options = {   -- See |diffview-config-log_options|
      --     git = {
      --       single_file = {
      --         diff_merges = "combined",
      --       },
      --       multi_file = {
      --         diff_merges = "first-parent",
      --       },
      --     },
      --     hg = {
      --       single_file = {},
      --       multi_file = {},
      --     },
      --   },
      --   win_config = {    -- See |diffview-config-win_config|
      --     position = "bottom",
      --     height = 16,
      --     win_opts = {},
      --   },
      -- },
      -- commit_log_panel = {
      --   win_config = {},  -- See |diffview-config-win_config|
      -- },
      -- default_args = {    -- Default args prepended to the arg-list for the listed commands
      --   DiffviewOpen = {},
      --   DiffviewFileHistory = {},
      -- },
    },
  },
}
