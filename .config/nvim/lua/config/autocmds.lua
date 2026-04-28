local M = {}

function M.setup()
    vim.api.nvim_create_autocmd('BufReadPost', {
        pattern = '*',
        callback = function()
            if vim.fn.line("'\"") > 0 and vim.fn.line("'\"") <= vim.fn.line("$") then
                vim.cmd('normal! g`"')
            end
        end
    })
    local function set_floating_colors()
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#1f2335", fg = "#c0caf5", force = true })
        vim.api.nvim_set_hl(0, "FloatBorder", { bg = "#1f2335", fg = "#7aa2f7", force = true })
        vim.api.nvim_set_hl(0, "DapUIFloatNormal", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "DapUIFloatBorder", { link = "FloatBorder" })
    end
    vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "*",
        callback = set_floating_colors,
    })
    set_floating_colors()

    -- Make gf and CTRL-W f resolve GAS .include directives in asm files
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "asm",
        callback = function()
            vim.opt_local.path:append(vim.fn.expand("%:p:h"))
            vim.opt_local.include = '\\.include\\s\\+"'
            vim.opt_local.includeexpr = "substitute(v:fname, '\"', '', 'g')"
        end,
    })

    -- Remember which window was active when quickfix opens, restore it on close.
    local qf_origin_win = nil

    vim.api.nvim_create_autocmd("BufWinEnter", {
        callback = function()
            if vim.bo.buftype == "quickfix" then
                qf_origin_win = vim.fn.win_getid(vim.fn.winnr("#"))
            end
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(ev)
            local closed_win = tonumber(ev.match)
            local info = vim.fn.getwininfo(closed_win)
            if not info or not info[1] or info[1].quickfix ~= 1 then return end
            local target = qf_origin_win
            qf_origin_win = nil
            if target and vim.api.nvim_win_is_valid(target) then
                vim.api.nvim_set_current_win(target)
            end
        end,
    })
end

return M
