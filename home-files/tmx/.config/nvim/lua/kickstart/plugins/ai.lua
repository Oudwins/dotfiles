return {
  {
    'supermaven-inc/supermaven-nvim',
    config = function()
      require('supermaven-nvim').setup {
        disable_inline_completion = true, -- blink.cmp handles the completion UI
        disable_keymaps = true, -- blink.cmp handles keymaps
      }
    end,
  },
}
