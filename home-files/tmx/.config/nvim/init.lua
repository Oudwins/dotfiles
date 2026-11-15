-- VS CODE CONFIG
if vim.g.vscode then
	require('configs.base')
	require('configs.vscode')
else
	require('configs.base')
	require('configs.kickstart')
end
