local M = {}

function M:peek(job)
	local path = tostring(job.file.url)
	local offset = job.skip

	local output, err = Command("batcat")
		:args({
			"--color=always",
			"--style=numbers,changes",
			"--pager=never",
			"--terminal-width=" .. tostring(job.area.w),
			"--line-range=" .. tostring(offset + 1) .. ":",
			path,
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output then
		ya.err("batcat failed: " .. tostring(err))
		-- Fall back to built-in code previewer
		local e, bound = ya.preview_code(job)
		if bound then
			ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true })
		end
		return
	end

	local text = output.stdout
	-- Count output lines to detect if we've hit the end of the file
	local n = 0
	for _ in text:gmatch("\n") do n = n + 1 end

	if offset > 0 and n < job.area.h then
		ya.emit("peek", { math.max(0, offset - (job.area.h - n)), only_if = job.file.url, upper_bound = true })
		return
	end

	ya.preview_widget(job, ui.Text.parse(text):area(job.area))
end

function M:seek(job)
	local h = cx.active.current.hovered
	if not h or h.url ~= job.file.url then
		return
	end
	ya.emit("peek", {
		math.max(0, cx.active.preview.skip + job.units),
		only_if = job.file.url,
	})
end

function M:spot(job) require("file"):spot(job) end

return M
