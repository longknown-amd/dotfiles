local M = {}
local keymap = vim.keymap

function M.setup()
    keymap.set('n', '<BS>', '<C-W><Left>')
    keymap.set('n', '<c-y>', ':tag<CR>')
    keymap.set('n', '0', '^')
    local resize = {
        ['<C-Up>']    = 'resize -2',
        ['<C-Down>']  = 'resize +2',
        ['<C-Left>']  = 'vertical resize +2',
        ['<C-Right>'] = 'vertical resize -2'
    }

    for keys, cmd in pairs(resize) do
        keymap.set('n', keys, '<cmd>' .. cmd .. '<CR>')
    end

    --local cscope_maps = {
    --['<Leader>t'] = 'f t',
    --['<Leader>c'] = 'f c',
    --['<Leader><Leader>t'] = 'f t',
    --['<Leader><Leader>c'] = 'f c'
    --}

    --for keys, cmd in pairs(cscope_maps) do
    --keymap.set('n', keys, function()
    --return ':cscope ' .. cmd .. ' ' .. vim.fn.expand('<cword>') .. '<CR>'
    --end, { expr = true })
    --end

    -- session management
    keymap.set("n", "<leader>ss", function() require("resession").save() end, { desc = "Save session" })
    keymap.set("n", "<leader>sl", function() require("resession").load() end, { desc = "Load session" })
    keymap.set("n", "<leader>sd", function() require("resession").delete() end, { desc = "Delete session" })

    -- toggle quickfix window
    keymap.set("n", "<leader>q", function()
        local qf_open = false
        for _, win in ipairs(vim.fn.getwininfo()) do
            if win.quickfix == 1 then qf_open = true; break end
        end
        if qf_open then vim.cmd("cclose") else vim.cmd("copen") end
    end, { desc = "Toggle quickfix window" })

    -- Switch asm-lsp instruction set for the current directory
    vim.api.nvim_create_user_command("AsmISA", function()
        local bin = vim.fn.stdpath("data") .. "/lazy/asm-lsp/target/release/asm-lsp"
        local opcodes_dir = vim.fn.stdpath("data") .. "/lazy/asm-lsp/asm-lsp/serialized/opcodes"

        -- Map opcode filenames to TOML instruction_set values
        -- Filenames use underscores (x86_64), TOML uses hyphens (x86-64)
        local filename_to_toml = { x86_64 = "x86-64" }
        -- "mars" is an assembler, not an architecture
        local skip = { mars = true }

        local entries_list = {}

        -- Try the new list-targets subcommand for AMDGPU entries
        local amdgpu_ok = false
        local ok, result = pcall(function()
            return vim.system({ bin, "list-targets" }, { text = true }):wait()
        end)
        if ok and result and result.code == 0 and result.stdout and result.stdout ~= "" then
            for line in result.stdout:gmatch("[^\r\n]+") do
                local gfx, label, isa = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
                if isa and isa ~= "" then
                    local display
                    local mcpu
                    if gfx ~= "" then
                        display = gfx .. " — " .. label
                        mcpu = gfx
                    else
                        display = label
                        mcpu = nil
                    end
                    table.insert(entries_list, { display = display, isa = isa, mcpu = mcpu })
                    amdgpu_ok = true
                end
            end
        end

        if not amdgpu_ok then
            vim.notify(
                "asm-lsp: list-targets unavailable, falling back to opcode directory listing",
                vim.log.levels.WARN
            )
            local entries = vim.fn.readdir(opcodes_dir)
            if not entries or #entries == 0 then
                vim.notify("asm-lsp: no opcodes found in " .. opcodes_dir, vim.log.levels.ERROR)
                return
            end
            local isa_list = {}
            for _, name in ipairs(entries) do
                if not skip[name] then
                    local toml_name = filename_to_toml[name] or name
                    table.insert(isa_list, toml_name)
                end
            end
            table.sort(isa_list)
            for _, isa in ipairs(isa_list) do
                table.insert(entries_list, { display = isa, isa = isa, mcpu = nil })
            end
        else
            -- Non-AMDGPU ISAs from the opcode directory, sorted alphabetically
            local entries = vim.fn.readdir(opcodes_dir) or {}
            local non_amdgpu = {}
            for _, name in ipairs(entries) do
                if not skip[name] and not name:match("^amdgpu%-") then
                    local toml_name = filename_to_toml[name] or name
                    table.insert(non_amdgpu, toml_name)
                end
            end
            table.sort(non_amdgpu)
            for _, isa in ipairs(non_amdgpu) do
                table.insert(entries_list, { display = isa, isa = isa, mcpu = nil })
            end
        end

        vim.ui.select(entries_list, {
            prompt = "Select instruction set:",
            format_item = function(e) return e.display end,
        }, function(choice)
            if not choice then return end
            local isa = choice.isa
            local mcpu = choice.mcpu
            local dir = vim.fn.expand("%:p:h")
            local toml_path = dir .. "/.asm-lsp.toml"

            -- Read existing file if present
            local existing = {}
            if vim.fn.filereadable(toml_path) == 1 then
                existing = vim.fn.readfile(toml_path)
            end

            -- Try to patch instruction_set in-place
            local patched = false
            for i, line in ipairs(existing) do
                if line:match('^%s*instruction_set%s*=') then
                    existing[i] = ('instruction_set = "%s"'):format(isa)
                    patched = true
                    break
                end
            end

            if patched then
                -- Also update compile_flags_txt mcpu if switching AMDGPU targets
                if mcpu then
                    for i, line in ipairs(existing) do
                        if line:match('^%s*compile_flags_txt%s*=') then
                            existing[i] = ('compile_flags_txt = ["--triple=amdgcn-amd-amdhsa", "--mcpu=%s", "--filetype=asm"]'):format(mcpu)
                            break
                        end
                    end
                end
                vim.fn.writefile(existing, toml_path)
            else
                -- No existing file or no instruction_set line — write fresh
                local lines = {
                    '[default_config]',
                    'assembler = "gas"',
                    ('instruction_set = "%s"'):format(isa),
                    '',
                }
                if mcpu then
                    vim.list_extend(lines, {
                        '[default_config.opts]',
                        'compiler = "/opt/rocm/llvm/bin/llvm-mc"',
                        ('compile_flags_txt = ["--triple=amdgcn-amd-amdhsa", "--mcpu=%s", "--filetype=asm"]'):format(mcpu),
                        '',
                    })
                end
                vim.fn.writefile(lines, toml_path)
            end

            local restarted = false
            local clients = vim.lsp.get_clients({ name = "asm_lsp" })

            if #clients > 0 then
                if vim.fn.exists(":lsp") == 2 then
                    -- Neovim 0.12+ built-in
                    vim.cmd("lsp restart asm_lsp")
                    restarted = true
                elseif vim.fn.exists(":LspRestart") == 2 then
                    -- nvim-lspconfig on Neovim <= 0.11
                    vim.cmd("LspRestart asm_lsp")
                    restarted = true
                else
                    for _, c in ipairs(clients) do
                        vim.lsp.stop_client(c.id)
                    end
                    vim.defer_fn(function() vim.cmd("edit") end, 150)
                    restarted = true
                end
            else
                if vim.lsp.enable then
                    vim.lsp.enable("asm_lsp")
                    restarted = true
                elseif vim.fn.exists(":LspStart") == 2 then
                    vim.cmd("LspStart asm_lsp")
                    restarted = true
                else
                    local cfg = vim.lsp.config and vim.lsp.config["asm_lsp"]
                    if cfg and vim.lsp.start then
                        local start_opts = vim.tbl_deep_extend("force", {}, cfg, {
                            name = "asm_lsp",
                            bufnr = vim.api.nvim_get_current_buf(),
                        })
                        vim.lsp.start(start_opts)
                        restarted = true
                    end
                end
                if restarted then
                    vim.defer_fn(function() vim.cmd("edit") end, 150)
                end
            end

            if restarted then
                vim.notify("asm-lsp: switched to " .. isa, vim.log.levels.INFO)
            else
                vim.notify(
                    "asm-lsp: wrote config for " .. isa .. " but could not start asm_lsp client",
                    vim.log.levels.WARN
                )
            end
        end)
    end, {})

    -- set keymap for symbol outlines
    keymap.set("n", "<F3>", "<cmd>AerialToggle!<CR>", { desc = "Toggle Outline From Aerial" })

    -- keymap to show diagnostic
    keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Show diagnostic" })

    -- set keymap for treesitter
    local project_root = require("config.telescope").project_root

    keymap.set("n", "<leader>ff", function()
        require("telescope.builtin").find_files({ cwd = project_root() })
    end, { desc = "Find file (project root)" })

    keymap.set("n", "<leader>fg", function()
        require("telescope.builtin").grep_string({ cwd = project_root(), additional_args = { "-w" } })
    end, { desc = "Grep word under cursor (project root)" })

    keymap.set("n", "<leader>fl", function()
        require("telescope.builtin").live_grep({ cwd = project_root() })
    end, { desc = "Live grep (project root)" })

    keymap.set("n", "<leader>fs", function()
        require("telescope.builtin").lsp_dynamic_workspace_symbols()
    end, { desc = "Find symbol (workspace)" })

    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(args)
        local bufnr = args.buf
        local opts = { buffer = bufnr }

        -- Navigation with tagstack support
        local function lsp_navigate(lsp_fn)
            return function()
                local origin_win = vim.fn.win_getid()
                lsp_fn({
                    on_list = function(options)
                        local from = {vim.fn.bufnr('%'), vim.fn.line('.'), vim.fn.col('.'), 0}
                        vim.fn.settagstack(origin_win, {items = {{from = from, tagname = vim.fn.expand('<cword>')}}}, 't')
                        vim.fn.setqflist({}, ' ', options)
                        if #options.items > 1 then
                            vim.cmd("copen")
                            local qf_buf = vim.api.nvim_get_current_buf()
                            local function cleanup()
                                pcall(vim.keymap.del, "n", "<CR>", { buffer = qf_buf })
                                pcall(vim.keymap.del, "n", "<2-LeftMouse>", { buffer = qf_buf })
                            end
                            local function qf_select()
                                local idx = vim.fn.line('.')
                                cleanup()
                                vim.cmd("cclose")
                                vim.fn.win_gotoid(origin_win)
                                vim.cmd("cc " .. idx)
                            end
                            vim.keymap.set("n", "<CR>", qf_select, { buffer = qf_buf })
                            vim.keymap.set("n", "<2-LeftMouse>", qf_select, { buffer = qf_buf })
                            vim.api.nvim_create_autocmd("BufHidden", {
                                buffer = qf_buf,
                                once = true,
                                callback = cleanup,
                            })
                        else
                            vim.cmd("cfirst")
                        end
                    end
                })
            end
        end
        keymap.set("n", "gd", lsp_navigate(vim.lsp.buf.definition), opts)
        keymap.set("n", "gD", lsp_navigate(vim.lsp.buf.declaration), opts)
        keymap.set("n", "gI", lsp_navigate(vim.lsp.buf.implementation), opts)
        keymap.set("n", "gy", lsp_navigate(vim.lsp.buf.type_definition), opts)
        -- Documentation
        local float_opts = {
            buffer = bufnr,
            border = "rounded",
            winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel,Search:None",
        }
        keymap.set("n", "K", function()
            vim.lsp.buf.hover(float_opts)
            end, opts)
        keymap.set("n", "gK", function()
            vim.lsp.buf.signature_help(float_opts)
            end, opts)

        -- References
        keymap.set("n", "gr", vim.lsp.buf.references, opts)

        -- Code actions
        keymap.set({"n", "v"}, "<leader>ca", vim.lsp.buf.code_action, opts)
        keymap.set("n", "<leader>cc", vim.lsp.codelens.run, opts)
        keymap.set("n", "<leader>cC", function()
          vim.lsp.codelens.refresh()
          vim.lsp.codelens.display()
        end, opts)

        -- Renaming
        keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)

        -- LSP info
        keymap.set("n", "<leader>cl", "<cmd>checkhealth vim.lsp<CR>", opts)

        -- Call hierarchy
        keymap.set("n", "<leader>ci", "<cmd>Lspsaga incoming_calls<CR>", { buffer = bufnr, desc = "Incoming calls" })
        keymap.set("n", "<leader>co", "<cmd>Lspsaga outgoing_calls<CR>", { buffer = bufnr, desc = "Outgoing calls" })
      end
})
end

return M
