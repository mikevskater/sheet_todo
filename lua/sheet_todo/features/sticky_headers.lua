-- Sticky header overlay for markdown documents
-- Shows ancestor headers at the top of the notepad when scrolled past them
local M = {}

local cfg = require('sheet_todo.config')

---@class StickyHeaderState
---@field overlay_win number?
---@field overlay_buf number?
---@field augroup number?
---@field notepad_win number?
---@field notepad_buf number?
---@field _adjusting boolean Guard against recursive CursorMoved triggers
---@field _overlay_height number Current overlay height (0 when hidden)
local state = {
  overlay_win = nil,
  overlay_buf = nil,
  augroup = nil,
  notepad_win = nil,
  notepad_buf = nil,
  _adjusting = false,
  _overlay_height = 0,
}

---Check if a line is a separator (3+ dashes)
---@param line string
---@return boolean
local function is_separator(line)
  return line:match('^%-%-%-+%s*$') ~= nil
end

---Get header level from a line, or nil if not a header
---@param line string
---@return number?
local function get_header_level(line)
  local hashes = line:match('^(#+)')
  if hashes then
    return #hashes
  end
  return nil
end

---Build the header stack by scanning upward from the first truly visible line.
---Headers within the overlay zone (behind the overlay) are included in the stack.
---@param bufnr number
---@param first_visible number 1-indexed first visible line
---@param overlay_height number Current overlay height (lines covered by overlay)
---@return {level: number, text: string}[]
local function build_header_stack(bufnr, first_visible, overlay_height)
  local stack = {}
  local min_level = math.huge

  -- The first line NOT covered by the overlay
  local first_uncovered = first_visible + overlay_height

  -- If the first uncovered line is a header, set min_level so we don't duplicate it
  local lines = vim.api.nvim_buf_get_lines(bufnr, first_uncovered - 1, first_uncovered, false)
  if lines[1] then
    local level = get_header_level(lines[1])
    if level then
      min_level = level
    end
  end

  -- Scan upward from the line above the first uncovered line
  -- This includes lines behind the overlay AND lines above first_visible
  for lnum = first_uncovered - 1, 1, -1 do
    local line_tbl = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)
    local line = line_tbl[1]
    if not line then break end

    -- Separator resets the stack
    if is_separator(line) then
      break
    end

    local level = get_header_level(line)
    if level and level < min_level then
      table.insert(stack, 1, { level = level, text = line })
      min_level = level
      if min_level <= 1 then break end
    end
  end

  return stack
end

---Check how many overlay lines we can show without covering a separator.
---@param bufnr number
---@param first_visible number
---@param desired_height number
---@return number
local function get_max_overlay_height(bufnr, first_visible, desired_height)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first_visible - 1, first_visible - 1 + desired_height, false)
  for i, line in ipairs(lines) do
    if is_separator(line) then
      return i - 1
    end
  end
  return desired_height
end

---Close the overlay window if open
local function close_overlay()
  if state.overlay_win and vim.api.nvim_win_is_valid(state.overlay_win) then
    vim.api.nvim_win_close(state.overlay_win, true)
  end
  state.overlay_win = nil
  if state.overlay_buf and vim.api.nvim_buf_is_valid(state.overlay_buf) then
    vim.api.nvim_buf_delete(state.overlay_buf, { force = true })
  end
  state.overlay_buf = nil
  state._overlay_height = 0
end

---Create or update the overlay window with the given header lines
---@param header_lines string[]
local function show_overlay(header_lines)
  local notepad_win = state.notepad_win
  if not notepad_win or not vim.api.nvim_win_is_valid(notepad_win) then
    close_overlay()
    return
  end

  local width = vim.api.nvim_win_get_width(notepad_win)
  local height = #header_lines

  -- Update existing overlay
  if state.overlay_win and vim.api.nvim_win_is_valid(state.overlay_win) then
    if state.overlay_buf and vim.api.nvim_buf_is_valid(state.overlay_buf) then
      vim.api.nvim_buf_set_lines(state.overlay_buf, 0, -1, false, header_lines)
      vim.api.nvim_win_set_config(state.overlay_win, {
        relative = 'win',
        win = notepad_win,
        row = 0,
        col = 0,
        width = width,
        height = height,
      })
    end
    return
  end

  -- Create new overlay
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, header_lines)
  vim.bo[buf].filetype = 'markdown'

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'win',
    win = notepad_win,
    row = 0,
    col = 0,
    width = width,
    height = height,
    focusable = false,
    zindex = 200,
    style = 'minimal',
    noautocmd = true,
  })

  state.overlay_buf = buf
  state.overlay_win = win
end

---Recalculate and update the sticky header overlay
local function update()
  local notepad_win = state.notepad_win
  local notepad_buf = state.notepad_buf
  if not notepad_win or not vim.api.nvim_win_is_valid(notepad_win) then
    close_overlay()
    return
  end
  if not notepad_buf or not vim.api.nvim_buf_is_valid(notepad_buf) then
    close_overlay()
    return
  end

  -- Get first visible line in the notepad window
  local first_visible = vim.api.nvim_win_call(notepad_win, function()
    return vim.fn.line('w0')
  end)

  -- No headers can be off-screen if we're at line 1
  if first_visible <= 1 then
    close_overlay()
    return
  end

  -- Build header stack using previous overlay height so headers behind
  -- the overlay aren't prematurely removed
  local stack = build_header_stack(notepad_buf, first_visible, state._overlay_height)
  if #stack == 0 then
    close_overlay()
    return
  end

  -- Truncate to avoid covering separator lines
  local max_height = get_max_overlay_height(notepad_buf, first_visible, #stack)
  if max_height <= 0 then
    close_overlay()
    return
  end

  -- Compute effective height
  local height = math.min(#stack, max_height)

  -- If height changed from previous, rebuild once to stabilize
  if height ~= state._overlay_height then
    stack = build_header_stack(notepad_buf, first_visible, height)
    if #stack == 0 then
      close_overlay()
      return
    end
    max_height = get_max_overlay_height(notepad_buf, first_visible, #stack)
    if max_height <= 0 then
      close_overlay()
      return
    end
    height = math.min(#stack, max_height)
  end

  -- Trim stack from the front (remove deepest ancestors) to fit
  local header_lines = {}
  local start_idx = #stack - height + 1
  if start_idx < 1 then start_idx = 1 end
  for i = start_idx, #stack do
    table.insert(header_lines, stack[i].text)
  end

  show_overlay(header_lines)
  state._overlay_height = #header_lines

  -- Scroll view so cursor appears below the overlay (don't move the cursor itself)
  if not state._adjusting and notepad_win == vim.api.nvim_get_current_win() then
    -- winline() returns 1-based visual row accounting for word wrap
    local visual_row = vim.api.nvim_win_call(notepad_win, function()
      return vim.fn.winline()
    end)
    if visual_row <= #header_lines then
      state._adjusting = true
      -- Scroll viewport so cursor line starts just below the overlay
      local cursor_line = vim.api.nvim_win_get_cursor(notepad_win)[1]
      local new_topline = cursor_line - #header_lines
      if new_topline < 1 then new_topline = 1 end
      vim.api.nvim_win_call(notepad_win, function()
        vim.fn.winrestview({ topline = new_topline })
      end)
      -- Clear on next schedule so the WinScrolled-triggered update
      -- recalculates the overlay but skips cursor adjustment
      vim.schedule(function()
        state._adjusting = false
      end)
    end
  end
end

---Set up sticky headers for the notepad window.
---@param winid number
---@param bufnr number
function M.setup(winid, bufnr)
  if not cfg.get('sticky_headers') then
    return
  end

  state.notepad_win = winid
  state.notepad_buf = bufnr

  -- Create autocmd group for cleanup
  state.augroup = vim.api.nvim_create_augroup('SheetTodoStickyHeaders', { clear = true })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'WinScrolled' }, {
    group = state.augroup,
    buffer = bufnr,
    callback = function()
      vim.schedule(update)
    end,
  })

  -- VimResized is global (not buffer-specific), so guard the callback
  vim.api.nvim_create_autocmd('VimResized', {
    group = state.augroup,
    callback = function()
      if state.notepad_win and vim.api.nvim_win_is_valid(state.notepad_win) then
        vim.schedule(update)
      end
    end,
  })
end

---Clean up overlay and autocmds.
function M.cleanup()
  close_overlay()
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end
  state.augroup = nil
  state.notepad_win = nil
  state.notepad_buf = nil
  state._adjusting = false
  state._overlay_height = 0
end

return M
