-- nvim-treesitter `main` branch API (Neovim >= 0.11).
-- The legacy `configs.setup{ ensure_installed=..., highlight=..., indent=... }`
-- API is gone; install parsers explicitly and start highlight/indent via
-- a FileType autocmd.
local parsers = { "vim", "vimdoc", "bash", "c", "cpp", "javascript", "python", "lua", "json" }
require('nvim-treesitter').install(parsers)

vim.api.nvim_create_autocmd('FileType', {
    pattern = parsers,
    callback = function(args)
        vim.treesitter.start(args.buf)
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
})

-- configure select options (lookahead)
require("nvim-treesitter-textobjects").setup {
    select = { lookahead = true },
    move = { set_jumps = true },
}

-- select keymaps
local select = require("nvim-treesitter-textobjects.select")
vim.keymap.set({ "x", "o" }, "af", function() select.select_textobject("@function.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "if", function() select.select_textobject("@function.inner", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ac", function() select.select_textobject("@class.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ic", function() select.select_textobject("@class.inner", "textobjects") end)
vim.keymap.set({ "x", "o" }, "aa", function() select.select_textobject("@parameter.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ia", function() select.select_textobject("@parameter.inner", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ab", function() select.select_textobject("@block.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ib", function() select.select_textobject("@block.inner", "textobjects") end)

-- move keymaps
local move = require("nvim-treesitter-textobjects.move")
vim.keymap.set({ "n", "x", "o" }, "]m", function() move.goto_next_start("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]]", function() move.goto_next_start("@class.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]a", function() move.goto_next_start("@parameter.inner", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]M", function() move.goto_next_end("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "][", function() move.goto_next_end("@class.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[m", function() move.goto_previous_start("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[[", function() move.goto_previous_start("@class.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[a", function() move.goto_previous_start("@parameter.inner", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[M", function() move.goto_previous_end("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[]", function() move.goto_previous_end("@class.outer", "textobjects") end)

-- repeat keymaps
local ts_repeat_move = require("nvim-treesitter-textobjects.repeatable_move")
vim.keymap.set({ "n", "x", "o" }, ";", ts_repeat_move.repeat_last_move_next)
vim.keymap.set({ "n", "x", "o" }, ",", ts_repeat_move.repeat_last_move_previous)
vim.keymap.set({ "n", "x", "o" }, "f", ts_repeat_move.builtin_f_expr, { expr = true })
vim.keymap.set({ "n", "x", "o" }, "F", ts_repeat_move.builtin_F_expr, { expr = true })
vim.keymap.set({ "n", "x", "o" }, "t", ts_repeat_move.builtin_t_expr, { expr = true })
vim.keymap.set({ "n", "x", "o" }, "T", ts_repeat_move.builtin_T_expr, { expr = true })
