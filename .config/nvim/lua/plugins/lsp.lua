return {
    {
        "williamboman/mason.nvim",
        config = function()
            require("mason").setup()
        end
    },
    {
        "williamboman/mason-lspconfig.nvim",
        config = function()
            -- Mason fetches the latest upstream release for each server
            -- (clangd from llvm-project releases, pyright via npm). Run
            -- :MasonUpdate to refresh later.
            require("mason-lspconfig").setup({
                ensure_installed = { "clangd", "pyright" },
            })
        end
    },
    {
        -- Treesitter on `main` (rewrite). Requires Neovim >= 0.11.
        -- Both nvim-treesitter and nvim-treesitter-textobjects are on `main`.
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
        config = function()
            require('config.treesitter')
        end,
    },
    {
        'neovim/nvim-lspconfig',
        dependencies = {
            "hrsh7th/cmp-nvim-lsp"
        },
        config = function()
            local cmp_nvim_lsp = require("cmp_nvim_lsp")
            local capabilities = cmp_nvim_lsp.default_capabilities()

            vim.lsp.log.set_level(vim.log.levels.WARN)

            vim.lsp.config('clangd', {
                cmd = {
                    "clangd",
                    "--background-index",
                    "--clang-tidy",
                    "--header-insertion=never",
                    "--function-arg-placeholders=1",
                    "--fallback-style=llvm",
                    "--malloc-trim",
                    "-j=8",
                    "--query-driver=/opt/rocm/bin/amdclang++,/opt/rocm/llvm/bin/clang++,/usr/local/bin/amdclang++",
                },
                -- NB: "s"/"asm" intentionally excluded — assembly is handled by asm_lsp.
                -- clangd otherwise attaches to .s files and tries to compile them as HIP.
                filetypes = { "c", "cpp", "h", "hpp", "objc", "objcpp", "cuda", "proto", "hip", "hiphpp", "cuh" },
                capabilities = capabilities,
            })

            vim.lsp.enable('clangd')
            vim.lsp.enable('pyright')
        end
    },

    {
        "nvim-telescope/telescope.nvim",
        tag = '0.1.8',
        dependencies = {
            { 'nvim-lua/plenary.nvim', lazy = true },
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" }, -- Faster fuzzy finder
            { "nvim-telescope/telescope-file-browser.nvim" },  -- File browser
        },
        config = function()
            require("config.telescope")
        end
    },

    {
        'linrongbin16/lsp-progress.nvim',
        config = function()
            require('lsp-progress').setup()
        end
    },
}
