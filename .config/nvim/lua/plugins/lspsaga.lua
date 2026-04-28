return {
    "nvimdev/lspsaga.nvim",
    event = "LspAttach",
    config = function()
        require("lspsaga").setup({
            -- Disable all UI components except call hierarchy
            ui = { border = "rounded" },
            hover = { enable = false },
            diagnostic = { enable = false },
            code_action = { enable = false },
            lightbulb = { enable = false },
            rename = { enable = false },
            outline = { enable = false },
            finder = { enable = false },
            implement = { enable = false },
            symbol_in_winbar = { enable = false },
            breadcrumbs = { enable = false },
            callhierarchy = { enable = true },
        })
    end,
}
