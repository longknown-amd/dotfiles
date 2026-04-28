local M = {}

function M.has_paste()
    return vim.o.paste and 'PASTE MODE  ' or ''
end

return M
