local dap = require("dap")

dap.adapters.lldb = {
    type = "executable",
    command = "/usr/bin/lldb-dap",
    name = "lldb",
}

dap.configurations.cpp = {
    {
        name = "HIP (rocgdb) Launch",
        type = "cppdbg",
        request = "launch", 
        program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd(), "file")
        end,
        args = {
        },
        cwd = "${workspaceFolder}",
        MIMode = "gdb",
        miDebuggerPath = "/usr/bin/rocgdb",
        stopOnEntry = true,
        env = {},
        setupCommands = {
            { text = "-enable-pretty-printing", description = "pretty printing", ignoreFailures = true },
        },
    },
    {
        name = "launch (LLDB)",
        type = "lldb",
        request = "launch",
        program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd(), "file")
        end,
        args = {
            "--batch_count", "1", "-m", "1", "-n", "2", "-k", "1", "--stride_a", "0", "--stride_b", "0", "--stride_c", "0", "--stride_d", "0", "--alpha", "1", "--beta", "0", "--transA", "N", "--transB", "N", "--scaleA", "0", "--scaleB", "0", "--bias_source", "d", "--flush", "--rotating", "512", "--initialization", "trig_float", "--print_kernel_info", "--any_stride", "-i", "10000", "-j", "24000", "--a_type", "bf16_r", "--b_type", "bf16_r", "--c_type", "bf16_r", "--d_type", "bf16_r", "--compute_type", "f32_r", "--verify"
        },
        cwd = "${workspaceFolder}",
        stopOnEntry = true,
        env = {},
    },
}

dap.adapters.cppdbg = {
    id = "cppdbg",
    type = "executable",
    command = "/home/thomas/bin/cpptools/OpenDebugAD7",
}

dap.configurations.hip = {
    {
        name = "HIP (rocgdb) Launch",
        type = "cppdbg",
        request = "launch", 
        program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd(), "file")
        end,
        args = { "2"},
        cwd = "${workspaceFolder}",
        MIMode = "gdb",
        miDebuggerPath = "/usr/bin/rocgdb",
        stopOnEntry = true,
        env = {},
        setupCommands = {
            { text = "-enable-pretty-printing", description = "pretty printing", ignoreFailures = true },
        },
    },
}
