-- Collapsible markdown headers via native foldmethod=expr
local M = {}

local cfg = require('sheet_todo.config')

---Fold expression for markdown headers.
---Returns '>N' for header lines, '=' for everything else.
---@param lnum number
---@return string
function M.fold_expr(lnum)
  local line = vim.fn.getline(lnum)
  local hashes = line:match('^(#+)')
  if hashes then
    return '>' .. #hashes
  end
  return '='
end

---Custom fold text: shows the header line + folded line count.
---@return string
function M.fold_text()
  local line = vim.fn.getline(vim.v.foldstart)
  local count = vim.v.foldend - vim.v.foldstart
  return line .. '  (' .. count .. ' lines)'
end

---Configure folding on the notepad window.
---@param winid number
---@param bufnr number
function M.setup(winid, bufnr)
  if not cfg.get('collapsible_headers') then
    return
  end

  local win_opts = {
    foldenable = true,
    foldmethod = 'expr',
    foldexpr = "v:lua.require'sheet_todo.features.folding'.fold_expr(v:lnum)",
    foldtext = "v:lua.require'sheet_todo.features.folding'.fold_text()",
    foldlevel = 99,
  }

  for opt, val in pairs(win_opts) do
    vim.api.nvim_set_option_value(opt, val, { win = winid })
  end
end

return M
