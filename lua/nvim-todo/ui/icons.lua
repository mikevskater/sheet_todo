---@class nvim-todo.ui.icons
local M = {}

---Get the display icon for a group node
---@param group GroupEntry
---@param is_expanded boolean
---@param has_children boolean
---@return string
function M.get_group_icon(group, is_expanded, has_children)
  if group.icon and group.icon ~= '' then return group.icon end
  if has_children then
    return is_expanded and '\u{25bc}' or '\u{25b6}'
  end
  return '\u{2022}'
end

return M
