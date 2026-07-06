-- Resolve a GFX codename (from .amdgcn_target) to an asm-lsp instruction_set
-- string by querying the asm-lsp binary's `resolve-target` subcommand. The
-- mapping lives in the asm-lsp plugin (built from source), not in this repo.
local isa_cache = {}
local function gfx_to_instruction_set(gfx)
    local cached = isa_cache[gfx]
    if cached ~= nil then
        return cached or nil
    end
    local bin = vim.fn.stdpath("data") .. "/lazy/asm-lsp/target/release/asm-lsp"
    local isa
    if vim.fn.executable(bin) == 1 then
        local res = vim.system({ bin, "resolve-target", gfx }, { text = true }):wait()
        if res.code == 0 then
            local out = vim.trim(res.stdout or "")
            if out ~= "" then
                isa = out
            end
        end
    end
    isa_cache[gfx] = isa or false
    return isa
end

-- Scan the first 50 lines of a buffer for .amdgcn_target and return the GFX
-- codename (e.g. "gfx950", "gfx11-generic"), or nil if not found.
local function detect_amdgcn_target(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 50, false)
    for _, line in ipairs(lines) do
        -- Pattern handles both plain (gfx1100) and generic (gfx11-generic) names.
        local gfx = line:match('%.amdgcn_target%s+"amdgcn%-amd%-amdhsa%-%-(gfx[%w%-]+)"')
        if gfx then return gfx end
    end
end

-- Read instruction_set value from an existing .asm-lsp.toml (simple line scan).
local function read_toml_instruction_set(toml_path)
    local lines = vim.fn.readfile(toml_path)
    for _, line in ipairs(lines) do
        local isa = line:match('^%s*instruction_set%s*=%s*"([^"]+)"')
        if isa then return isa end
    end
end

-- asm-lsp's fork lives in a bare repo on hjbog-srdc-38
-- (/home/thohuang/project/asm-lsp.git). That box's own SSH-registered key
-- lives on client laptops, not on the box itself, so it can never SSH to
-- itself -- use a local filesystem path there, and ssh:// everywhere else.
local ASM_LSP_HOST_PATTERN = "^hjbog%-srdc%-38"
local asm_lsp_url
do
    local hostname = (vim.uv or vim.loop).os_gethostname()
    if hostname:match(ASM_LSP_HOST_PATTERN) then
        asm_lsp_url = "/home/thohuang/project/asm-lsp.git"
    else
        asm_lsp_url = "ssh://thohuang@hjbog-srdc-38.amd.com/home/thohuang/project/asm-lsp.git"
    end
end

return {
    {
        -- AMD GCN syntax plugin. Now hosted on GitHub so destination boxes
        -- can fetch it via lazy.nvim like any other plugin (was previously
        -- a `dir = ...` pointing into a local asm-lsp fork checkout, which
        -- only existed on the source machine).
        -- lazy = false ensures Lazy adds it to rtp at startup, before any
        -- FileType events fire, so runtime! syntax/amdgpu_gcn.vim works.
        url = "https://github.com/longknown-amd/vim-amdgpu-syntax.git",
        name = "vim-amdgpu-syntax",
        lazy = false,
    },
    {
        "bergercookie/asm-lsp",
        -- Fork hosted on hjbog-srdc-38 (bare repo at
        -- /home/thohuang/project/asm-lsp.git) with AMD GPU ISA support added.
        -- See asm_lsp_url above for why the URL is chosen per-host.
        url = asm_lsp_url,
        branch = "main",
        build = "cargo build --release",
        ft = { "asm", "s", "S" },
        config = function()
            local bin = vim.fn.stdpath("data") .. "/lazy/asm-lsp/target/release/asm-lsp"
            local capabilities = require("cmp_nvim_lsp").default_capabilities()
            vim.lsp.config["asm_lsp"] = {
                cmd = { bin },
                filetypes = { "asm", "s", "S" },
                capabilities = capabilities,
                -- root_dir runs inside the LSP start sequence, before the server
                -- process launches and reads its config. Writing .asm-lsp.toml here
                -- ensures asm-lsp sees the correct instruction_set on first start.
                root_dir = function(bufnr, on_dir)
                    local fname = vim.api.nvim_buf_get_name(bufnr)
                    local dir = vim.fn.fnamemodify(fname, ":h")

                    local gfx = detect_amdgcn_target(bufnr)
                    if gfx then
                        local isa = gfx_to_instruction_set(gfx)
                        if isa then
                            local toml_path = dir .. "/.asm-lsp.toml"
                            if vim.fn.filereadable(toml_path) == 1 then
                                local toml_isa = read_toml_instruction_set(toml_path)
                                if toml_isa and toml_isa ~= isa then
                                    vim.notify(
                                        string.format(
                                            "asm-lsp: .amdgcn_target is %s (%s) but .asm-lsp.toml has instruction_set = %q",
                                            gfx, isa, toml_isa
                                        ),
                                        vim.log.levels.WARN
                                    )
                                end
                            else
                                -- Use ROCm's llvm-mc for diagnostics: it understands all
                                -- AMDGPU instructions and .set symbolic register names,
                                -- unlike the system gcc/gas which has no AMDGPU backend.
                                local mcpu = gfx  -- e.g. "gfx950", "gfx1200"
                                vim.fn.writefile({
                                    '[default_config]',
                                    'assembler = "gas"',
                                    string.format('instruction_set = "%s"', isa),
                                    '',
                                    '[default_config.opts]',
                                    'compiler = "/opt/rocm/llvm/bin/llvm-mc"',
                                    string.format(
                                        'compile_flags_txt = ["--triple=amdgcn-amd-amdhsa", "--mcpu=%s", "--filetype=asm"]',
                                        mcpu
                                    ),
                                    '',
                                }, toml_path)
                                vim.notify(
                                    string.format(
                                        "asm-lsp: detected %s → wrote .asm-lsp.toml (instruction_set = %s)",
                                        gfx, isa
                                    ),
                                    vim.log.levels.INFO
                                )
                            end
                        else
                            vim.notify(
                                string.format("asm-lsp: unsupported GFX target %q, no ISA mapped", gfx),
                                vim.log.levels.WARN
                            )
                        end
                    end

                    local root = vim.fs.dirname(vim.fs.find(
                        { ".asm-lsp.toml", ".git" },
                        { path = fname, upward = true }
                    )[1]) or dir
                    on_dir(root)
                end,
            }
            vim.lsp.enable("asm_lsp")
        end,
    },
}
