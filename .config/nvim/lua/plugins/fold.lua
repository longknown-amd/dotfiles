return {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    event = "VeryLazy",
    keys = {
        {
            '<leader><leader>f',
            function()
                local ufo = require("ufo")
                if vim.o.foldenable then
                    vim.wo.foldenable = false
                    vim.wo.foldcolumn = '0'
                    ufo.closeAllFolds()
                else
                    vim.wo.foldcolumn = '1' -- '0' is not bad
                    vim.wo.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
                    vim.o.foldlevelstart = 99
                    vim.wo.foldenable = true
                    vim.o.mouse = "a"
                    vim.cmd('silent! normal! zx')
                    vim.schedule(function()
                        ufo.openFoldsExceptKinds()
                    end)
                end
            end,
            desc = "Enable UFO folding",
        },
    },
    config = function()
        vim.o.foldcolumn = '0' -- '0' is not bad
        vim.o.foldlevel = 0
        vim.o.foldlevelstart = 0
        vim.o.foldenable = false
        vim.o.fillchars = 'eob: ,fold: ,foldopen:,foldsep: ,foldinner: ,foldclose:'
        vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
        vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)

        require('ufo').setup({
            provider_selector = function(bufnr, filetype, buftype)
                if filetype == 'aerial' or buftype == 'nofile' or buftype == 'prompt' then
                    return nil
                end
                return { 'lsp', 'indent' }
            end,
        })
    end
}
