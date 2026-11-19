return {
    "nvimdev/lspsaga.nvim",
    event = "LspAttach",
    config = function()
        -- lspsaga's call/type hierarchy still calls vim.lsp.util.jump_to_location (deprecated in 0.11, unfixed
        -- upstream as of cf6fc94). Same body as core's wrapper, without the deprecation warning.
        if vim.fn.has("nvim-0.11") == 1 then
            vim.lsp.util.jump_to_location = function(location, position_encoding, reuse_win)
                return vim.lsp.util.show_document(location, position_encoding,
                    { reuse_win = reuse_win, focus = true })
            end
        end
        require("lspsaga").setup({
            -- Disable all UI components except call hierarchy
            ui = { border = "rounded" },
            hover = { enable = false },
            diagnostic = { enable = false },
            code_action = { enable = false },
            lightbulb = { enable = false },
            rename = { enable = false },
            outline = { enable = false },
            finder = { enable = false },
            implement = { enable = false },
            symbol_in_winbar = { enable = false },
            breadcrumbs = { enable = false },
            callhierarchy = { enable = true },
        })

        -- lspsaga bug (unfixed upstream as of cf6fc94): the call/type hierarchy spinner timer is stopped only when
        -- the LSP reply still finds its node. Jumping (e/s/i/t) or closing while a request is pending wipes the
        -- window and the timer then errors every 50 ms on vim.bo[nil] ("Invalid 'name': Expected Lua string").
        -- Same spinner, but it stops itself once the hierarchy buffer is gone.
        local api = vim.api
        local frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
        local function patch_spinner(modname, nsname)
            local ok, mod = pcall(require, modname)
            local ch = ok and getmetatable(mod) or nil
            if type(ch) ~= "table" or type(ch.spinner) ~= "function" then
                return
            end
            local ns = api.nvim_create_namespace(nsname) -- same id the plugin uses
            ch.spinner = function(self, node)
                if not node or not (self.left_bufnr and api.nvim_buf_is_loaded(self.left_bufnr)) then
                    return function() end
                end
                local col = node.value.winline == 1 and 0 or node.value.inlevel - 4
                local timer, frame, done = vim.uv.new_timer(), 1, false
                local function stop()
                    if done then
                        return false
                    end
                    done = true
                    timer:stop()
                    timer:close()
                    return true
                end
                timer:start(0, 50, vim.schedule_wrap(function()
                    if done then
                        return
                    end
                    local buf = self.left_bufnr
                    if not (buf and api.nvim_buf_is_valid(buf)) then
                        return stop()
                    end
                    vim.bo[buf].modifiable = true
                    pcall(api.nvim_buf_set_extmark, buf, ns, node.value.winline - 1, col, {
                        id = node.value.virtid,
                        virt_text = { { frames[frame], "SagaSpinner" } },
                        virt_text_pos = "overlay",
                        hl_mode = "combine",
                    })
                    frame = frame % #frames + 1
                end))
                return function()
                    if stop() and self.left_bufnr and api.nvim_buf_is_valid(self.left_bufnr) then
                        self:set_toggle_icon(require("lspsaga").config.ui.expand, node.value.winline - 1, col,
                            node.value.virtid)
                    end
                end
            end
        end
        -- Same race, second half: a reply that lands after clean() hits find_node(nil) in slist.lua ("attempt to
        -- index local 'tmp'"), or would reopen the window / graft stale results into a newer hierarchy. Each
        -- request remembers the session it was sent in; clean() and opening a new hierarchy start a new session,
        -- and replies from an older one are dropped (clean() already reset pending_request).
        local function drop_stale_replies(modname, prepare_fn, request_fn)
            local ok, mod = pcall(require, modname)
            local ch = ok and getmetatable(mod) or nil
            if type(ch) ~= "table" then
                return
            end
            local util = require("lspsaga.util")
            local gen = 0
            local function guarded(fn, starts_session)
                return function(self, ...)
                    if starts_session and not self.pending_request then -- a pending send returns early
                        gen = gen + 1
                    end
                    local sent_in, orig_request = gen, util.client_request
                    util.client_request = function(client, method, params, handler, ...)
                        return orig_request(client, method, params, function(...)
                            if sent_in == gen then
                                return handler(...)
                            end
                        end, ...)
                    end
                    local res = vim.F.pack_len(pcall(fn, self, ...))
                    util.client_request = orig_request
                    if not res[1] then
                        error(res[2], 0)
                    end
                    return vim.F.unpack_len(res, 2)
                end
            end
            local orig_clean = ch.clean
            if type(orig_clean) == "function" then
                ch.clean = function(self, ...)
                    gen = gen + 1
                    return orig_clean(self, ...)
                end
            end
            if type(ch[prepare_fn]) == "function" then
                ch[prepare_fn] = guarded(ch[prepare_fn], true)
            end
            if type(ch[request_fn]) == "function" then
                ch[request_fn] = guarded(ch[request_fn], false)
            end
        end

        patch_spinner("lspsaga.callhierarchy", "SagaCallhierarchy")
        patch_spinner("lspsaga.typehierarchy", "SagaTypehierarchy")
        drop_stale_replies("lspsaga.callhierarchy", "send_prepare_call", "call_hierarchy")
        drop_stale_replies("lspsaga.typehierarchy", "send_prepare_type", "type_hierarchy")
    end,
}
