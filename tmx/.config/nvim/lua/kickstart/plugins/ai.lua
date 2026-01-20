return {
  {
    'supermaven-inc/supermaven-nvim',
    config = function()
      require('supermaven-nvim').setup {
        -- keymaps = {
        --   accept_suggestion = '<C-y>',
        --   -- clear_suggestion = '<C-]>',
        --   -- accept_word = '<C-j>',
        --   clear_suggestion = '',
        --   accept_word = '',
        -- },
        disable_keymaps = false,
      }
    end,
  },
}
