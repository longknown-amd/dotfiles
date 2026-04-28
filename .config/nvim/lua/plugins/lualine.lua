return {
    "nvim-lualine/lualine.nvim",
    event = "VimEnter",
    dependencies = { 'nvim-tree/nvim-web-devicons', lazy = true },
    opts = function()
        require("lualine").setup({
            sections = {
                lualine_a = {
                    function()
                        return require('lsp-progress').progress()
                    end,
                }
            }
        })
        vim.api.nvim_create_augroup("lualine_augroup", { clear = true })
        vim.api.nvim_create_autocmd("User", {
            group = "lualine_augroup",
            pattern = "LspProgressStatusUpdated",
            callback = require("lualine").refresh,
        })
    end
}
