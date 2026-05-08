-- Compatibility shims for nvim-treesitter `main` (the API rewrite).
-- telescope.nvim's previewer still expects the legacy modules:
--   - parsers.ft_to_lang(ft)               (removed)
--   - parsers.get_parser(bufnr, lang)      (removed)
--   - nvim-treesitter.configs              (whole module gone)
-- Re-implement them on top of core nvim's vim.treesitter.* API.
do
    -- Patch nvim-treesitter.parsers (still ships, but slimmer).
    local ok, parsers = pcall(require, "nvim-treesitter.parsers")
    if ok and parsers then
        if not parsers.ft_to_lang then
            parsers.ft_to_lang = function(ft)
                return vim.treesitter.language.get_lang(ft) or ft
            end
        end
        if not parsers.get_parser then
            parsers.get_parser = function(bufnr, lang)
                local pok, parser = pcall(vim.treesitter.get_parser, bufnr or 0, lang)
                return pok and parser or nil
            end
        end
    end

    -- Fake nvim-treesitter.configs so Telescope's pcall-require returns a
    -- usable table. is_enabled tells Telescope whether to attempt TS
    -- highlighting; we say yes iff the parser for `lang` is installed.
    if not package.loaded["nvim-treesitter.configs"] then
        package.loaded["nvim-treesitter.configs"] = {
            is_enabled = function(_module, lang, _bufnr)
                if not lang or lang == "" then return false end
                return pcall(vim.treesitter.language.add, lang)
            end,
            get_module = function(_name)
                return {}
            end,
        }
    end
end

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
