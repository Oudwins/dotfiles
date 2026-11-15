-- NVIM CONFIG
--   local vscode = require('vscode-neovim')
--   
-- vim.keymap.set({ 'n' }, '<Space>sf', function() vscode.call("workbench.action.quickOpen") end, { silent = true })
local vscode = require('vscode')

vim.keymap.set('n', "]d", function() vscode.call("editor.action.marker.next") end, { silent = true })
vim.keymap.set('n', "[d", function() vscode.call("editor.action.marker.prev") end, { silent = true })
-- [p]roject [s]earch
vim.keymap.set('n', "<leader>ps", function() vscode.call("workbench.action.findInFiles") end, { silent = true })
-- [v]ariable [r]e[n]ame
vim.keymap.set("n", "<leader>vrn", function() vscode.call("editor.action.rename") end, { silent = true })
-- [v]ariable [r]e[f]erences
vim.keymap.set("n", "<leader>vrf", function() vscode.call("references-view.findReferences") end, { silent = true })
