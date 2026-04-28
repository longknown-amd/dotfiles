local telescope = require("telescope")

local function project_root()
    local markers = { "compile_commands.json", ".git" }
    for _, marker in ipairs(markers) do
        local match = vim.fs.find(marker, {
            upward = true,
            path = vim.fn.expand("%:p:h"),
        })
        if match[1] then
            return vim.fn.fnamemodify(match[1], ":h")
        end
    end
    return vim.fn.getcwd()
end

-- Monkey-patch Previewer:title to append selection index
local Previewer = require("telescope.previewers.previewer")
function Previewer:title(entry, dynamic)
    local base = self._title_fn and self:_title_fn() or "Preview"
    local state = require("telescope.state")
    for _, bufnr in ipairs(state.get_existing_prompt_bufnrs()) do
        local status = state.get_status(bufnr)
        local picker = status.picker
        if picker and picker.previewer == self
            and picker.manager and type(picker.manager) ~= "boolean" then
            local total = picker.manager:num_results()
            local idx = picker:get_index(picker:get_selection_row())
            idx = math.max(1, math.min(idx, total))
            return string.format("%s [%d/%d]", base, idx, total)
        end
    end
    return base
end

telescope.setup {
    extensions = {
        fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
        },
    }
}

telescope.load_extension("fzf")
telescope.load_extension("file_browser")

return { project_root = project_root }
