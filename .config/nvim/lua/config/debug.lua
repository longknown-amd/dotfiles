local dap = require("dap")
local dapui = require("dapui")
local widgets = require("dap.ui.widgets")

dapui.setup({})
require("nvim-dap-virtual-text").setup()

dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end

-- Common keymaps for DAP
local map = vim.keymap.set
local opts = { silent = true, noremap = true }

map("n", "<F5>", function() dap.continue() end, opts)          -- Start/continue
map("n", "<F6>", function()
    dap.terminate()
    pcall(require("dapui").close)
end, opts)          -- Start/continue
map("n", "<F10>", function() dap.step_over() end, opts)         -- Step over
map("n", "<F9>", function() dap.step_into() end, opts)         -- Step into
map("n", "<F12>", function() dap.step_out() end, opts)          -- Step out
map("n", "<leader>db", function() dap.toggle_breakpoint() end, opts) -- Toggle breakpoint
map("n", "<leader>dc", function() dap.run_to_cursor() end, opts) -- run to cursor
map("n", "<leader>dB", function()
  dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
end, opts)
map("n", "<leader>dl", function()
  dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
end, opts)
map("n", "<leader>dr", function() dap.repl.open() end, opts)    -- Open REPL
map("n", "<leader>du", function() dapui.toggle() end, opts)     -- Toggle UI
map("n", "<leader>de", function() dap.set_exception_breakpoints({"raised"}) end, opts)

local hover_opts = {
    border = "double",
    winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
}
map("n", "<leader>K", function()
    widgets.hover(nil, hover_opts)
end, { silent = true, noremap = true, })

vim.api.nvim_create_autocmd("FileType", {
    pattern = "dap-float",
    callback = function()
        vim.api.nvim_buf_set_keymap(0, "n", "q", "<cmd>close!<CR>", { noremap = true, silent = true })
    end
})

vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = "*.hip",
    callback = function()
        vim.bo.filetype = "hip"
    end,
})

-- helper to send a GDB command via DAP
local function gdb_exec(cmd)
    local dap = require('dap')
    local sess = dap.session()
    if not sess then
        vim.notify('No active DAP session', vim.log.levels.WARN)
        return
    end
    sess:request('evaluate', { expression = '-exec ' .. cmd, context = 'repl' })
end
