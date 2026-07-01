return {
    'stevearc/aerial.nvim',
    lazy = true,
    -- Optional dependencies
    dependencies = {
       "nvim-treesitter/nvim-treesitter",
       "nvim-tree/nvim-web-devicons"
    },
    init = function()
        vim.api.nvim_create_user_command("AerialToggle",
            function(params)
                require("lazy").load({ plugins = { "aerial.nvim" } })
                vim.schedule(function()
                    vim.cmd("AerialToggle" .. (params.bang and "!" or ""))
                end)
            end, {
                bang = true,
            })
    end,
    config = function()
        require("aerial").setup({
            layout = { default_direction = "prefer_left" },
            disable_max_lines = 0,
        })
    end
}
