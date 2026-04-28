return {
    "FriedrichWilken/molokai.nvim",
    lazy = false,
    priority = 1000,
    opts = function()
        require("monokai").setup({
            require("monokai").pro
        })
    end
}
