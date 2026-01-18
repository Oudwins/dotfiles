-- lua/custom/utils/path.lua
local M = {}

function M.project_root()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local start = (file ~= '' and vim.fs.dirname(file)) or vim.uv.cwd()
  local root = vim.fs.root(start, { '.git' })
  return root or vim.uv.cwd()
end

function M.resolve_path(input, opts)
  opts = opts or {}
  input = vim.trim(input or '')
  if input == '' then
    return nil
  end

  local curdir = opts.curdir or vim.fn.expand '%:p:h'
  local root = opts.root or M.project_root()
  local cwd = opts.cwd or vim.uv.cwd()

  if vim.startswith(input, './') or input == '.' then
    return vim.fs.normalize(vim.fs.joinpath(curdir, input))
  elseif vim.startswith(input, '.') then
    return vim.fs.normalize(vim.fs.joinpath(curdir, input:sub(2)))
  end

  if vim.startswith(input, '@/') then
    return vim.fs.normalize(vim.fs.joinpath(root, input:sub(3)))
  elseif vim.startswith(input, '@') then
    return vim.fs.normalize(vim.fs.joinpath(root, input:sub(2)))
  end

  if vim.fs.is_absolute(input) then
    return vim.fs.normalize(input)
  end
  return vim.fs.normalize(vim.fs.joinpath(cwd, input))
end

return M
