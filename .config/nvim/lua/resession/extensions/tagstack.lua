local M = {}

M.on_save = function()
    local stacks = {}
    for winnr, winid in ipairs(vim.api.nvim_list_wins()) do
        local stack = vim.fn.gettagstack(winid)
        if stack and stack.length > 0 then
            -- Serialize bufnr -> filename in each item's `from` field
            local serialized_items = {}
            for _, item in ipairs(stack.items) do
                local from_bufnr = item.from[1]
                local fname = vim.api.nvim_buf_get_name(from_bufnr)
                table.insert(serialized_items, {
                    tagname  = item.tagname,
                    matchnr  = item.matchnr,
                    from     = { fname, item.from[2], item.from[3], item.from[4] },
                })
            end
            stacks[winnr] = { curidx = stack.curidx, items = serialized_items }
        end
    end
    return stacks
end

M.on_post_load = function(data)
    local wins = vim.api.nvim_list_wins()
    for winnr_str, stack in pairs(data) do
        local winnr = tonumber(winnr_str)
        local winid = wins[winnr]
        if not winid then break end

        -- Deserialize filename -> bufnr in each item's `from` field
        local items = {}
        for _, item in ipairs(stack.items) do
            local bufnr = vim.fn.bufadd(item.from[1])
            table.insert(items, {
                tagname = item.tagname,
                matchnr = item.matchnr,
                from    = { bufnr, item.from[2], item.from[3], item.from[4] },
            })
        end
        vim.fn.settagstack(winid, { curidx = stack.curidx, items = items }, "r")
    end
end

return M
