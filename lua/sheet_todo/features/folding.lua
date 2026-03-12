-- Collapsible markdown headers via manual fold management
-- Custom za/zM/zR that find the enclosing header and compute section ranges
local M = {}

local cfg = require('sheet_todo.config')

---@class FoldingState
---@field winid number?
---@field bufnr number?
local state = {
  winid = nil,
  bufnr = nil,
}

-- ============================================================================
-- HEADER SCANNING
-- ============================================================================

---Find the nearest markdown header at or above a line number.
---@param bufnr number
---@param lnum number 1-indexed line number
---@return number? header_lnum, number? header_level
local function find_enclosing_header(bufnr, lnum)
  for l = lnum, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1]
    if line then
      local hashes = line:match('^(#+)')
      if hashes then
        return l, #hashes
      end
    end
  end
  return nil, nil
end

---Find the last line of a header's section.
---Section ends at the line before the next header of equal or lesser depth, or at EOF.
---@param bufnr number
---@param header_lnum number 1-indexed header line
---@param header_level number Header depth (number of #)
---@return number end_lnum 1-indexed last line of section
local function find_section_end(bufnr, header_lnum, header_level)
  local total = vim.api.nvim_buf_line_count(bufnr)
  for l = header_lnum + 1, total do
    local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1]
    if line then
      local hashes = line:match('^(#+)')
      if hashes and #hashes <= header_level then
        return l - 1
      end
    end
  end
  return total
end

-- ============================================================================
-- FOLD TEXT
-- ============================================================================

---Custom fold text: shows the header line + folded line count.
---@return string
function M.fold_text()
  local line = vim.fn.getline(vim.v.foldstart)
  local count = vim.v.foldend - vim.v.foldstart
  return line .. '  (' .. count .. ' lines)'
end

-- ============================================================================
-- FOLD ACTIONS
-- ============================================================================

---Toggle fold for the header section enclosing the cursor.
---Finds the nearest header above (or at) cursor, computes its section range,
---and toggles the fold open/closed. Creates the fold if none exists.
function M.toggle_fold()
  local winid = state.winid
  local bufnr = state.bufnr
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local lnum = cursor[1]

  local header_lnum, header_level = find_enclosing_header(bufnr, lnum)
  if not header_lnum then return end

  local section_end = find_section_end(bufnr, header_lnum, header_level)
  if section_end <= header_lnum then return end

  vim.api.nvim_win_call(winid, function()
    local fold_closed = vim.fn.foldclosed(header_lnum)
    if fold_closed ~= -1 then
      -- Fold is closed, open it
      pcall(vim.cmd, header_lnum .. 'foldopen')
    elseif vim.fn.foldlevel(header_lnum) > 0 then
      -- Fold exists and is open, close it
      pcall(vim.cmd, header_lnum .. 'foldclose')
    else
      -- No fold exists, create one (creates it closed)
      pcall(vim.cmd, header_lnum .. ',' .. section_end .. 'fold')
    end
  end)
end

---Close all folds: create folds for every header section.
---Creates innermost (deepest) folds first so nesting works correctly.
function M.close_all_folds()
  local winid = state.winid
  local bufnr = state.bufnr
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local total = vim.api.nvim_buf_line_count(bufnr)

  vim.api.nvim_win_call(winid, function()
    -- Clear all existing folds
    pcall(vim.cmd, 'normal! zE')

    -- Collect all headers with their section ranges
    local headers = {}
    for l = 1, total do
      local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1]
      if line then
        local hashes = line:match('^(#+)')
        if hashes then
          local section_end = find_section_end(bufnr, l, #hashes)
          if section_end > l then
            table.insert(headers, { lnum = l, level = #hashes, section_end = section_end })
          end
        end
      end
    end

    -- Sort by level descending (create deepest folds first)
    table.sort(headers, function(a, b) return a.level > b.level end)

    for _, h in ipairs(headers) do
      pcall(vim.cmd, h.lnum .. ',' .. h.section_end .. 'fold')
    end
  end)
end

---Open all folds by deleting all manual folds.
function M.open_all_folds()
  local winid = state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  vim.api.nvim_win_call(winid, function()
    pcall(vim.cmd, 'normal! zE')
  end)
end

-- ============================================================================
-- SETUP
-- ============================================================================

---Configure folding on the notepad window.
---Uses foldmethod=manual with custom toggle/close-all/open-all actions.
---@param winid number
---@param bufnr number
function M.setup(winid, bufnr)
  if not cfg.get('collapsible_headers') then
    return
  end

  state.winid = winid
  state.bufnr = bufnr

  local win_opts = {
    foldenable = true,
    foldmethod = 'manual',
    foldtext = "v:lua.require'sheet_todo.features.folding'.fold_text()",
    foldlevel = 99,
  }

  for opt, val in pairs(win_opts) do
    vim.api.nvim_set_option_value(opt, val, { win = winid })
  end
end

return M
