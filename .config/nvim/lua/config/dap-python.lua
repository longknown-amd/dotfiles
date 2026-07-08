-- lua/config/dap-python.lua

local dap = require("dap")
local dap_python = require("dap-python")

-- Find the project root by walking up from the current buffer's file (falling
-- back to cwd) until we hit a marker. This is what makes launches independent
-- of *where* you started nvim: opening src/web/api.py still resolves the repo
-- root, so ${workspaceFolder}-style paths point at the right place.
local function find_project_root()
  local markers = { ".venv", "venv", ".git", "requirements.txt", "pyproject.toml" }
  local start = vim.api.nvim_buf_get_name(0)
  if start == nil or start == "" then
    start = vim.fn.getcwd()
  end
  local dir = vim.fn.fnamemodify(start, ":p")
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  while dir and dir ~= "/" do
    for _, m in ipairs(markers) do
      local p = dir .. "/" .. m
      if vim.fn.isdirectory(p) == 1 or vim.fn.filereadable(p) == 1 then
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
  return vim.fn.getcwd()
end

-- Resolve the Python interpreter for BOTH the debug adapter (debugpy.adapter)
-- and the debuggee. Priority:
--   1. An active virtualenv ($VIRTUAL_ENV)
--   2. A project-local .venv/ or venv/ at the detected project root
--   3. System python3
-- The adapter needs debugpy and the debuggee needs the project deps — both live
-- in the venv, not in system python3.
local function get_python_path()
  local venv = os.getenv("VIRTUAL_ENV")
  if venv and venv ~= "" then
    return venv .. "/bin/python"
  end
  local root = find_project_root()
  for _, dir in ipairs({ ".venv", "venv" }) do
    local candidate = root .. "/" .. dir .. "/bin/python"
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  return "python3"
end

-- dap-python still wants an interpreter for its test-runner helpers.
dap_python.setup(get_python_path())

-- Adapter: resolve the interpreter lazily (as a function) so it picks up the
-- venv of whatever project you're in when a session starts, not at load time.
dap.adapters.python = function(callback, _config)
  callback({
    type = "executable",
    command = get_python_path(),
    args = { "-m", "debugpy.adapter" },
  })
end

-- Configurations shown in the <F5> picker. Paths are resolved against the
-- detected project root so they work regardless of nvim's cwd.
--
-- IMPORTANT: to debug the dashboard, launch start_dashboard.py (repo root) —
-- the direct single-process Flask server. Do NOT use scripts/start_dashboard.sh:
-- that is a bash script that runs nginx + gunicorn (multi-worker) and cannot be
-- run by debugpy (you'd get a SyntaxError trying to exec bash as Python).
--
-- Return the current buffer's file only if it is a Python file, otherwise abort
-- with a clear message. Prevents feeding a non-.py buffer (e.g. a shell script)
-- to Python, which produces a confusing SyntaxError.
local function current_python_file()
  local f = vim.api.nvim_buf_get_name(0)
  if not f:match("%.py$") then
    error("Current buffer is not a .py file (" .. vim.fn.fnamemodify(f, ":t")
      .. "). Open a Python file, or pick the 'SONAR Dashboard' config instead.")
  end
  return f
end

-- "SONAR Dashboard" is first so it is the default pick for debugging submit_job.
dap.configurations.python = {
  {
    type = "python",
    request = "launch",
    name = "SONAR Dashboard (start_dashboard.py)",
    program = function() return find_project_root() .. "/start_dashboard.py" end,
    args = { "--host", "0.0.0.0", "--port", "5000" },
    console = "integratedTerminal",
    cwd = find_project_root,
    justMyCode = false,
    pythonPath = get_python_path,
  },
  {
    type = "python",
    request = "launch",
    name = "Launch file (venv)",
    program = current_python_file,
    console = "integratedTerminal",
    cwd = find_project_root,
    justMyCode = false,
    pythonPath = get_python_path,
  },
  {
    type = "python",
    request = "launch",
    name = "SONAR run_test.py (dummy mode)",
    program = function() return find_project_root() .. "/src/core/run_test.py" end,
    args = {
      "--test-suite", "tests/test-suites/gfx1250/gfx1250_unit_test.json",
      "--model", "AM",
      "--gpu-arch", "gfx1250",
      "--dummy-mode",
    },
    console = "integratedTerminal",
    cwd = find_project_root,
    justMyCode = false,
    pythonPath = get_python_path,
  },
  {
    type = "python",
    request = "attach",
    name = "Attach (remote debugpy :5678)",
    connect = { host = "127.0.0.1", port = 5678 },
    justMyCode = false,
    pathMappings = {
      {
        localRoot = find_project_root,
        remoteRoot = ".",
      },
    },
  },
}
