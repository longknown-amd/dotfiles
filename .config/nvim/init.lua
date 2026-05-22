vim.g.python3_host_prog = '/home/thomas/miniconda3/envs/default/bin/python'

local opt = vim.opt

opt.history = 100
opt.number = true
opt.autoread = true
opt.cursorline = true
opt.wildmenu = true
opt.wildignore = "*.o,*~,*.pyc"
opt.ruler = true
opt.cmdheight = 2
opt.backspace = "indent,eol,start"
opt.whichwrap = "<,>,h,l"
opt.termguicolors = true
opt.smartcase = true
opt.ignorecase = true
opt.hlsearch = true
opt.incsearch = true
opt.lazyredraw = true
opt.magic = true
opt.showmatch = true
opt.mat = 2
opt.background = "dark"
opt.encoding = "utf-8"
opt.fileformat = "unix"
opt.swapfile = false
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.wrap = false
opt.laststatus = 2
opt.clipboard = "unnamedplus"
vim.g.clipboard = {
    name = "OSC 52",
    copy = {
        ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
        ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
        ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
        ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
}
opt.signcolumn = "yes"
opt.scrolloff = 8

vim.filetype.add({
    extension = {
        s = "asm",
        S = "asm",
        inc = function(path, bufnr)
            local lines = vim.api.nvim_buf_get_lines(
                bufnr, 0, math.min(vim.api.nvim_buf_line_count(bufnr), 200), false
            )
            for _, line in ipairs(lines) do
                local s = vim.trim(line)
                -- Skip blank lines and ambiguous comment styles (both C and GAS use // and /* */)
                if s == "" or s:match("^//") or s:match("^/%*") or s:match("^%*") then
                    goto continue
                end
                -- C/C++ preprocessor: #include, #define, #pragma, #ifndef, ...
                if s:match("^#%s*[a-z]") then return "cpp" end
                -- Lines starting with .<identifier> — the ambiguous zone
                if s:match("^%.[a-z]") then
                    -- C designated initializer: .field = value
                    -- GAS never uses = after a directive; GAS uses comma (.set sym, val)
                    if s:match("^%.[%w_.]+%s*=") then return "cpp" end
                    -- GAS directive (.macro, .set, .globl, .text, .amdhsa_*, ...)
                    return "asm"
                end
                -- GCN/AMDGPU instruction mnemonics
                if s:match("^[sv]_") or s:match("^ds_") or s:match("^buffer_")
                    or s:match("^global_") or s:match("^flat_") then
                    return "asm"
                end
                -- Semicolon comment — asm convention, never valid C/C++
                if s:match("^;") then return "asm" end
                -- C++ keywords at line start
                if s:match("^template%s*<") or s:match("^namespace%s")
                    or s:match("^constexpr%s") or s:match("^static_assert") then
                    return "cpp"
                end
                ::continue::
            end
        end,
    },
})

require('config.lazy')
require('config.keymaps').setup()
require('config.autocmds').setup()
