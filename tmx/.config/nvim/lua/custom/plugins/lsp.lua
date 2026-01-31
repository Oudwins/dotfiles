return {
  -- NOTE LSP Plugins and Configuration
  --
  {
    'roobert/tailwindcss-colorizer-cmp.nvim',
    ft = { 'html', 'javascriptreact', 'typescriptreact', 'svelte', 'vue' },
    -- optionally, override the default options:
    config = function()
      require('tailwindcss-colorizer-cmp').setup {
        color_square_width = 2,
      }
    end,
  },
  --
  {
    'themaxmarchuk/tailwindcss-colors.nvim',
    ft = { 'html', 'javascriptreact', 'typescriptreact', 'svelte', 'vue' },
    'themaxmarchuk/tailwindcss-colors.nvim',
    config = function()
      require('tailwindcss-colors').setup()
    end,
  },
  {
    -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
    -- used for completion, annotations and signatures of Neovim apis
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
  -- Sets up typescript LSP with plugin (doesn't support import paths)
  -- {
  --   'pmizio/typescript-tools.nvim',
  --   dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  --   opts = {
  --     on_attach = function(client)
  --       -- Disable typescript-tools formatting
  --       client.server_capabilities.documentFormattingProvider = false
  --       client.server_capabilities.documentRangeFormattingProvider = false
  --     end,
  --   },
  -- },
  {
    -- Main LSP Configuration
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      -- Mason must be loaded before its dependents so we need to set it up here.
      -- NOTE: `opts = {}` is the same as calling `require('mason').setup({})`
      { 'mason-org/mason.nvim', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      { 'j-hui/fidget.nvim', opts = {} },

      -- Allows extra capabilities provided by blink.cmp
      'saghen/blink.cmp',
    },
    config = function()
      -- Brief aside: **What is LSP?**
      --
      -- LSP is an initialism you've probably heard, but might not understand what it is.
      --
      -- LSP stands for Language Server Protocol. It's a protocol that helps editors
      -- and language tooling communicate in a standardized fashion.
      --
      -- In general, you have a "server" which is some tool built to understand a particular
      -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
      -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
      -- processes that communicate with some "client" - in this case, Neovim!
      --
      -- LSP provides Neovim with features like:
      --  - Go to definition
      --  - Find references
      --  - Autocompletion
      --  - Symbol Search
      --  - and more!
      --
      -- Thus, Language Servers are external tools that must be installed separately from
      -- Neovim. This is where `mason` and related plugins come into play.
      --
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer and description for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map('grn', vim.lsp.buf.rename, '[G]o [R]e[n]ame')

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })

          -- Find references for the word under your cursor.
          map('grr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- Jump to the implementation of the word under your cursor.
          --  Useful when your language has ways of declaring types without an actual implementation.
          map('gri', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

          -- Jump to the definition of the word under your cursor.
          --  This is where a variable was first declared, or where a function is defined, etc.
          --  To jump back, press <C-t>.
          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- Fuzzy find all the symbols in your current document.
          --  Symbols are things like variables, functions, types, etc.
          map('gO', require('telescope.builtin').lsp_document_symbols, 'Open Document Symbols')

          -- Fuzzy find all the symbols in your current workspace.
          --  Similar to document symbols, except searches over your entire project.
          map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Open Workspace Symbols')

          -- Jump to the type of the word under your cursor.
          --  Useful when you're not sure what type a variable is and you want to see
          --  the definition of its *type*, not where it was *defined*.
          map('grt', require('telescope.builtin').lsp_type_definitions, '[G]oto [T]ype Definition')

          -- TODO make this thing work.
          -- should autocomplete based on path!
          local paths = require 'custom.utils.paths'
          vim.keymap.set('n', '<leader>nf', function()
            vim.notify('ran!', vim.log.levels.INFO)
            require('telescope.builtin').find_files {
              prompt_title = 'New file (Enter creates)',
              attach_mappings = function(prompt_bufnr, _)
                vim.notify('ran!', vim.log.levels.INFO)
                local actions = require 'telescope.actions'
                local action_state = require 'telescope.actions.state'
                actions.select_default:replace(function()
                  local typed = action_state.get_current_line()
                  actions.close(prompt_bufnr)

                  local full = paths.resolve_path(typed)
                  if not full then
                    return
                  end

                  vim.fn.mkdir(vim.fs.dirname(full), 'p')
                  vim.cmd.edit(vim.fn.fnameescape(full))
                end)
                return true
              end,
            }
          end, { desc = '[N]ew [F]ile (type path; . = current file dir, @ = project root)' })

          -- This function resolves a difference between neovim nightly (version 0.11) and stable (version 0.10)
          ---@param client vim.lsp.Client
          ---@param method vim.lsp.protocol.Method
          ---@param bufnr? integer some lsp support methods only in specific files
          ---@return boolean
          local function client_supports_method(client, method, bufnr)
            if vim.fn.has 'nvim-0.11' == 1 then
              return client:supports_method(method, bufnr)
            else
              return client.supports_method(method, { bufnr = bufnr })
            end
          end

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- The following code creates a keymap to toggle inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- Diagnostic Config
      -- See :help vim.diagnostic.Opts
      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '󰅚 ',
            [vim.diagnostic.severity.WARN] = '󰀪 ',
            [vim.diagnostic.severity.INFO] = '󰋽 ',
            [vim.diagnostic.severity.HINT] = '󰌶 ',
          },
        } or {},
        virtual_text = {
          source = 'if_many',
          spacing = 2,
          format = function(diagnostic)
            local diagnostic_message = {
              [vim.diagnostic.severity.ERROR] = diagnostic.message,
              [vim.diagnostic.severity.WARN] = diagnostic.message,
              [vim.diagnostic.severity.INFO] = diagnostic.message,
              [vim.diagnostic.severity.HINT] = diagnostic.message,
            }
            return diagnostic_message[diagnostic.severity]
          end,
        },
      }

      -- LSP servers and clients are able to communicate to each other what features they support.
      --  By default, Neovim doesn't support everything that is in the LSP specification.
      --  When you add blink.cmp, luasnip, etc. Neovim now has *more* capabilities.
      --  So, we create new capabilities with blink.cmp, and then broadcast that to the servers.
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- Enable the following language servers
      --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
      --
      --  Add any additional override configuration in the following tables. Available keys are:
      --  - cmd (table): Override the default command used to start the server
      --  - filetypes (table): Override the default list of associated filetypes for the server
      --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
      --  - settings (table): Override the default settings passed when initializing the server.
      --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
      local util = require 'lspconfig.util'
      local servers = {
        -- NOTE: see `:help lspconfig-all` for a list of all the pre-configured LSP Servers
        gopls = {},
        -- md lsps. Didn't like it so removed for now
        -- marksman = {},
        -- rumdl = {}, -- not really lsp. linter formatter
        -- markdown_oxide = {}, -- inspired by obsidian

        -- nix lsps
        -- nixd = {}, -- not in mason
        nil_ls = {}, -- experimental

        -- NOTE: WEB
        --
        -- tsgo. Works great but doesn't have code actions
        -- tsgo = {
        --   cmd = { 'tsgo', '--lsp', '--stdio' },
        --   filetypes = {
        --     'javascript',
        --     'javascriptreact',
        --     'javascript.jsx',
        --     'typescript',
        --     'typescriptreact',
        --     'typescript.tsx',
        --   },
        --   root_markers = {
        --     'tsconfig.json',
        --     'jsconfig.json',
        --     'package.json',
        --     '.git',
        --     'tsconfig.base.json',
        --   },
        -- },
        -- typescript alternative to ts_ls
        vtsls = {
          -- on_attach = function(client)
          --   client.server_capabilities.documentFormattingProvider = false
          --   client.server_capabilities.documentRangeFormattingProvider = false
          -- end,
          settings = {
            complete_function_calls = true,
            vtsls = {
              enableMoveToFileCodeAction = true,
              autoUseWorkspaceTsdk = true,
              experimental = {
                maxInlayHintLength = 30,
                completion = {
                  enableServerSideFuzzyMatch = true,
                },
              },
            },
            typescript = {
              updateImportsOnFileMove = { enabled = 'always' },
              suggest = {
                completeFunctionCalls = true,
              },
              inlayHints = {
                enumMemberValues = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                parameterNames = { enabled = 'literals' },
                parameterTypes = { enabled = true },
                propertyDeclarationTypes = { enabled = true },
                variableTypes = { enabled = false },
              },
            },
          },
        },
        emmet_language_server = {
          filetypes = { 'html', 'css', 'javascriptreact', 'typescriptreact' },
        },
        -- superhtml = {},
        cssls = {},
        tailwindcss = {
          on_attach = function(client, bufnr)
            -- doesn't work :(
            require('tailwindcss-colors').buf_attach(bufnr)
          end,
          root_dir = util.root_pattern '.git',
          on_new_config = function(new_config, new_root_dir)
            -- Override tailwind config for elevenlabs/marketing-website monorepo
            local handle = io.popen('git -C ' .. vim.fn.shellescape(new_root_dir) .. ' remote get-url origin 2>/dev/null')
            if handle then
              local remote = handle:read('*a'):gsub('%s+$', '')
              handle:close()
              if remote:match 'elevenlabs/marketing%-website' then
                local config_path = new_root_dir .. '/frontend-next/tailwind.v2.config.ts'
                new_config.settings = new_config.settings or {}
                new_config.settings.tailwindCSS = new_config.settings.tailwindCSS or {}
                new_config.settings.tailwindCSS.experimental = new_config.settings.tailwindCSS.experimental or {}
                new_config.settings.tailwindCSS.experimental.configFile = config_path
              end
            end
          end,
        },
        eslint = {
          -- Not sure if this is actually needed
          settings = {
            workingDirectory = { mode = 'auto' },
          },
          on_attach = function(client, bufnr)
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
            vim.api.nvim_buf_create_user_command(bufnr, 'EslintFixAll', function()
              vim.lsp.buf.code_action {
                apply = true,
                context = { only = { 'source.fixAll.eslint' }, diagnostics = {} },
              }
            end, { desc = 'ESLint: fix all' })
            vim.api.nvim_create_autocmd('BufWritePre', {
              buffer = bufnr,
              group = vim.api.nvim_create_augroup('eslint-fix-on-save', { clear = false }),
              callback = function()
                vim.cmd 'EslintFixAll'
              end,
            })
          end,
        },

        -- NOTE: Python
        basedpyright = {},
        ruff = {},
        -- NOTE: terraform
        -- Warning ai generated, might not work
        terraformls = {
          -- avoid formatter conflicts; let efm handle fmt
          on_attach = function(client)
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
          end,
        },
        efm = {
          filetypes = { 'terraform', 'terraform-vars', 'hcl' },
          root_dir = util.root_pattern('.git', '.tflint.hcl', '.terraform'),
          init_options = {
            documentFormatting = true,
            documentRangeFormatting = true,
            documentDiagnostics = true,
          },
          settings = {
            rootMarkers = { '.git/' },
            languages = {
              terraform = {
                { formatCommand = 'terraform fmt -', formatStdin = true },
              },
              ['terraform-vars'] = {
                { formatCommand = 'terraform fmt -', formatStdin = true },
              },
            },
          },
        },
        lua_ls = {
          -- cmd = { ... },
          -- filetypes = { ... },
          -- capabilities = {},
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('custom-lsp-attach', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client then
            return
          end
          local server = servers[client.name]
          if server and server.on_attach then
            server.on_attach(client, event.buf)
          end
        end,
      })

      -- Ensure the servers and tools above are installed
      --
      -- To check the current status of installed tools and/or manually install
      -- other tools, you can run
      --    :Mason
      --
      -- You can press `g?` for help in this menu.
      --
      -- `mason` had to be setup earlier: to configure its options see the
      -- `dependencies` table for `nvim-lspconfig` above.
      --
      -- You can add other tools here that you want Mason to install
      -- for you, so that they are available from within Neovim.

      -- Use mason-tool-installer for non-LSP tools (formatters, linters)
      -- mason-lspconfig handles LSP server installation with proper name translation
      require('mason-tool-installer').setup {
        ensure_installed = {
          -- FORMATTERS
          'stylua', -- Used to format Lua code
          'prettierd',
          -- LINTERS
          'jsonlint',
          'tflint',
          'hadolint',
        },
      }

      -- mason-lspconfig handles lspconfig -> mason name translation internally
      require('mason-lspconfig').setup {
        ensure_installed = vim.tbl_keys(servers or {}),
        automatic_installation = false,
        handlers = {
          function(server_name)
            local server = servers[server_name]
            -- avoid setting up unconfigured servers
            if not server then
              return
            end
            -- This handles overriding only values explicitly passed
            -- by the server configuration above. Useful when disabling
            -- certain features of an LSP (for example, turning off formatting for ts_ls)
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },
}
