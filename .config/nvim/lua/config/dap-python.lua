-- after/plugin/dap.lua or lua/config/dap.lua

local dap = require("dap")
local dap_python = require("dap-python")

dap_python.setup("python")

-- Adapter and Python helpers
dap.adapters.python = {
  type = "executable",
  command = "python",                 -- or path to your global python
  args = { "-m", "debugpy.adapter" },
}

-- Global default configurations for Python
dap.configurations.python = {
  {
    type = "python",
    request = "launch",
    name = "Launch file",
    program = "${file}",
    console = "integratedTerminal",
    cwd = "${workspaceFolder}",
    justMyCode = false,
  },
}
