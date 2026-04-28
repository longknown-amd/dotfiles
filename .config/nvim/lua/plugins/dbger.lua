return {
    {
        "mfussenegger/nvim-dap",
        config = function()
            require("config.debug")
        end,
        event = "VeryLazy",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "nvim-neotest/nvim-nio",
            "jay-babu/mason-nvim-dap.nvim",
            "theHamsta/nvim-dap-virtual-text",
        },
    },
    {
        "mfussenegger/nvim-dap-python",
        config = function()
            require("config.dap-python")
            require("config.dap-c-cpp")
        end,
        dependencies = {"mfussenegger/nvim-dap"},
    },
}
