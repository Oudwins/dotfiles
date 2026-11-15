return {

  { -- Linting
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      -- To allow other plugins to add linters to require('lint').linters_by_ft,
      -- instead set linters_by_ft like this:
      -- lint.linters_by_ft = lint.linters_by_ft or {}
      -- lint.linters_by_ft['markdown'] = { 'markdownlint' }
      -- However, note that this will enable a set of default linters,
      -- which will cause errors unless these tools are available:
      -- {
      --   clojure = { "clj-kondo" },
      --   dockerfile = { "hadolint" },
      --   inko = { "inko" },
      --   janet = { "janet" },
      --   json = { "jsonlint" },
      --   markdown = { "vale" },
      --   rst = { "vale" },
      --   ruby = { "ruby" },
      --   terraform = { "tflint" },
      --   text = { "vale" }
      -- }
      --
      -- You can disable the default linters by setting their filetypes to nil:
      -- lint.linters_by_ft['clojure'] = nil
      -- lint.linters_by_ft['dockerfile'] = nil
      -- lint.linters_by_ft['inko'] = nil
      -- lint.linters_by_ft['janet'] = nil
      -- lint.linters_by_ft['json'] = nil
      -- lint.linters_by_ft['markdown'] = nil
      -- lint.linters_by_ft['rst'] = nil
      -- lint.linters_by_ft['ruby'] = nil
      -- lint.linters_by_ft['terraform'] = nil
      -- lint.linters_by_ft['text'] = nil
      local lint = require 'lint'
      lint.linters_by_ft = lint.linters_by_ft or {}

      lint.linters_by_ft['clojure'] = nil
      lint.linters_by_ft['inko'] = nil
      lint.linters_by_ft['janet'] = nil
      lint.linters_by_ft['rst'] = nil
      lint.linters_by_ft['ruby'] = nil
      lint.linters_by_ft['text'] = nil
      lint.linters_by_ft['markdown'] = nil
      -- Avoid ENOENT errors when external linters aren't installed.
      local function enable_linter(key, value)
        if vim.fn.executable(value) == 1 then
          lint.linters_by_ft[key] = { value }
        else
          lint.linters_by_ft[key] = nil
        end
      end

      -- enable_linter('markdown', 'markdownlint')
      enable_linter('dockerfile', 'hadolint')
      enable_linter('json', 'jsonlint')
      enable_linter('terraform', 'tflint')
      -- web
      enable_linter('javascript', 'eslint_d')
      enable_linter('typescript', 'eslint_d')
      enable_linter('javascriptreact', 'eslint_d')
      enable_linter('typescriptreact', 'eslint_d')

      -- python
      enable_linter('python', 'ruff')
      -- Create autocommand which carries out the actual linting
      -- on the specified events.
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only run the linter in buffers that you can modify in order to
          -- avoid superfluous noise, notably within the handy LSP pop-ups that
          -- describe the hovered symbol using Markdown.
          if vim.bo.modifiable then
            pcall(lint.try_lint)
          end
        end,
      })
    end,
  },
}
