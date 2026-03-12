---@class nvim-todo.utils.table
local M = {}

---Remap path prefixes in an array of path strings.
---Used when renaming/reparenting groups to update expanded_paths references.
---@param paths string[] Array of dot-separated paths
---@param old_prefix string The old path prefix to replace
---@param new_prefix string The new path prefix
---@return string[] remapped New array with updated prefixes
function M.remap_path_prefixes_array(paths, old_prefix, new_prefix)
  local result = {}
  local pattern = "^" .. vim.pesc(old_prefix) .. "%."
  for _, p in ipairs(paths) do
    if p == old_prefix then
      table.insert(result, new_prefix)
    elseif p:find(pattern) then
      table.insert(result, new_prefix .. p:sub(#old_prefix + 1))
    else
      table.insert(result, p)
    end
  end
  return result
end

---Remap path prefixes in a set (table<string, boolean>).
---Used when renaming/reparenting groups to update tree_state.expanded.
---@param set table<string, boolean> Set of dot-separated paths
---@param old_prefix string The old path prefix to replace
---@param new_prefix string The new path prefix
---@return table<string, boolean> remapped New set with updated prefixes
function M.remap_path_prefixes_set(set, old_prefix, new_prefix)
  local result = {}
  local pattern = "^" .. vim.pesc(old_prefix) .. "%."
  for p, v in pairs(set) do
    if p == old_prefix then
      result[new_prefix] = v
    elseif p:find(pattern) then
      result[new_prefix .. p:sub(#old_prefix + 1)] = v
    else
      result[p] = v
    end
  end
  return result
end

return M
