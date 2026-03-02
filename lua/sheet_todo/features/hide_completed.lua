-- Hide completed tasks feature
-- Toggles visibility of checked-off items (- [x] lines through to next - [ ])
local M = {}

---@class HideCompletedState
---@field active boolean Whether completed tasks are currently hidden
---@field hidden_ranges { start: number, lines: string[] }[] Ranges of hidden lines
---@field original_lines string[]? Full buffer snapshot before hiding
local state = {
  active = false,
  hidden_ranges = {},
  original_lines = nil,
}

---Check if a line is a checked (completed) todo
---@param line string
---@return boolean
local function is_checked(line)
  return line:match('^%s*%- %[x%]') ~= nil or line:match('^%s*%- %[X%]') ~= nil
end

---Check if a line is an unchecked (pending) todo
---@param line string
---@return boolean
local function is_unchecked(line)
  return line:match('^%s*%- %[ %]') ~= nil
end

---Compute visible lines and hidden ranges from a set of lines
---@param lines string[]
---@return string[] visible_lines, { start: number, lines: string[] }[] hidden_ranges
local function compute_ranges(lines)
  local visible = {}
  local ranges = {}
  local hiding = false
  local current_hidden = {}
  local current_start = nil

  for _, line in ipairs(lines) do
    if hiding then
      if is_unchecked(line) then
        -- End of hidden range
        table.insert(ranges, { start = current_start, lines = current_hidden })
        current_hidden = {}
        hiding = false
        table.insert(visible, line)
      else
        table.insert(current_hidden, line)
      end
    else
      if is_checked(line) then
        hiding = true
        current_start = #visible + 1
        current_hidden = { line }
      else
        table.insert(visible, line)
      end
    end
  end

  -- Handle trailing hidden range (completed tasks at end of file)
  if hiding and #current_hidden > 0 then
    table.insert(ranges, { start = #visible + 1, lines = current_hidden })
  end

  return visible, ranges
end

---Hide completed tasks in the buffer
---@param bufnr number
function M.hide(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  state.original_lines = lines

  local visible, ranges = compute_ranges(lines)
  state.hidden_ranges = ranges

  if #ranges == 0 then
    vim.notify("No completed tasks to hide", vim.log.levels.INFO)
    state.original_lines = nil
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, visible)
  state.active = true

  local hidden_count = 0
  for _, range in ipairs(ranges) do
    hidden_count = hidden_count + #range.lines
  end
  vim.notify("Hidden " .. hidden_count .. " completed line(s)", vim.log.levels.INFO)
end

---Show (restore) completed tasks in the buffer
---@param bufnr number
function M.show(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local full = M.get_full_lines(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, full)

  state.active = false
  state.hidden_ranges = {}
  state.original_lines = nil

  vim.notify("Showing all tasks", vim.log.levels.INFO)
end

---Toggle hide/show completed tasks
---@param bufnr number
function M.toggle(bufnr)
  if state.active then
    M.show(bufnr)
  else
    M.hide(bufnr)
  end
end

---Check if hide mode is active
---@return boolean
function M.is_active()
  return state.active
end

---Get full lines including hidden ranges, merging any edits made while hidden
---@param bufnr number
---@return string[]
function M.get_full_lines(bufnr)
  if not state.active or not state.original_lines then
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
    return {}
  end

  -- Current visible lines (may have been edited by user)
  local visible = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Re-interleave hidden ranges into visible lines at their original positions
  -- Ranges are stored with `start` = the position in visible lines where they were removed
  -- We insert them back in reverse order to preserve indices
  local result = {}
  for _, line in ipairs(visible) do
    table.insert(result, line)
  end

  -- Sort ranges by start position (ascending), then insert in reverse
  local sorted = {}
  for _, range in ipairs(state.hidden_ranges) do
    table.insert(sorted, range)
  end
  table.sort(sorted, function(a, b) return a.start > b.start end)

  for _, range in ipairs(sorted) do
    local pos = math.min(range.start, #result + 1)
    for i = #range.lines, 1, -1 do
      table.insert(result, pos, range.lines[i])
    end
  end

  return result
end

---Get full content as a string including hidden lines (for saving)
---@param bufnr number
---@return string
function M.get_full_content(bufnr)
  local lines = M.get_full_lines(bufnr)
  return table.concat(lines, "\n")
end

---Reset state (called on window close)
function M.reset()
  state.active = false
  state.hidden_ranges = {}
  state.original_lines = nil
end

return M
