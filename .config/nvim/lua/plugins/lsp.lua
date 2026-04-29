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
            require("mason-lspconfig").setup({
                ensure_installed = {},
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

            vim.lsp.enable('clangd')
            vim.lsp.enable('pyright')
            vim.lsp.log.set_level(vim.log.levels.OFF)
            vim.lsp.config.clangd = {
                cmd = {
                    "clangd",
                    "--background-index",
                    "--clang-tidy",
                    "--header-insertion=never",
                    "--function-arg-placeholders",
                    "--fallback-style=llvm",
                    "--malloc-trim",
                    "-j=8",
                },
                filetypes = { "c", "cpp", "h", "hpp", "objc", "objcpp", "cuda", "proto", "hip", "hiphpp", "cuh", "s", "asm" },
                capabilities = capabilities,
            }
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
