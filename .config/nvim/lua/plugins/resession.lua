return {
    "stevearc/resession.nvim",
    lazy = true,
    config = function()
        require("resession").setup({
            extensions = { aerial = {}, tagstack = {} },
        })
    end,
}
