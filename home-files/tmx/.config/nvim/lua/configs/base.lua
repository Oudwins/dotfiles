-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are required (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- [[ Setting options ]]
-- See `:help vim.o`
-- NOTE: For more options, you can see `:help option-list`

-- Make line numbers default
vim.wo.number = true
-- relative line numbers
vim.wo.relativenumber = true

-- Enable mouse mode. So you can use the mouse
vim.o.mouse = 'a'

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.o.clipboard = 'unnamedplus'
end)

-- [[ File type options ]]
-- Disable conceal for help files (otherwise tags are not visible)
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'help',
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})
