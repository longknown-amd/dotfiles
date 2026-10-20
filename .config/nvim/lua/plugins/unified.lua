return {
    'axkirillov/unified.nvim',
    -- lazy.nvim's stub is removed before config() runs and the original
    -- invocation is replayed afterwards, so the wrapper below is what runs.
    cmd = "Unified",
    config = function()
        require("unified").setup({})

        local command = require("unified.command")
        local base_suggestions = { "unstaged", "index", "-s", "-t", "HEAD", "HEAD~1", "main", "reset" }

        local function err(msg)
            vim.api.nvim_echo({ { msg, "ErrorMsg" } }, false, {})
        end

        -- Replace the plugin's :Unified. `unstaged`/`index` becomes the tree hash of
        -- the current index (snapshot at call time), so the diff is index vs worktree.
        -- Everything else goes to command.run() unchanged (no recursion: we call the
        -- Lua function, not the user command).
        vim.api.nvim_create_user_command("Unified", function(opts)
            local args = opts.args
            local parts = vim.split(args, "%s+", { trimempty = true })
            for i, p in ipairs(parts) do
                if p == "unstaged" or p == "index" then
                    local name = vim.api.nvim_buf_get_name(0)
                    local dir = vim.fn.fnamemodify(name, ":h")
                    if name == "" or vim.bo.buftype ~= "" or vim.fn.isdirectory(dir) == 0 then
                        dir = vim.fn.getcwd()
                    end
                    local res = vim.system({ "git", "-C", dir, "write-tree" }, { text = true }):wait()
                    local out = vim.trim(res.stdout or "")
                    if res.code ~= 0 or out == "" then
                        local e = vim.trim(res.stderr or "")
                        if e:find("unmerged") or e:find("merge") then
                            err("Unified: cannot diff unstaged changes: index has unmerged entries (resolve conflicts first)")
                        else
                            err("Unified: git write-tree failed: " .. e)
                        end
                        return
                    end
                    parts[i] = out
                    args = table.concat(parts, " ")
                    break
                end
            end
            command.run(args)
        end, {
            nargs = "*",
            complete = function(ArgLead, CmdLine)
                if not CmdLine:match("^%s*Unified%s+") then
                    return {}
                end
                return vim.tbl_filter(function(s)
                    return s:sub(1, #ArgLead) == ArgLead
                end, base_suggestions)
            end,
        })
    end,
}
