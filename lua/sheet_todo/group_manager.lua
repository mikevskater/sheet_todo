-- Group manager for multi-panel tabs
-- Pure data logic: group CRUD, data normalization, per-group state
local M = {}

local pantry = require('sheet_todo.pantry')

---@class GroupEntry
---@field name string
---@field content string Decoded content string
---@field cursor_pos { line: number, col: number }

---@class GroupManagerState
---@field groups GroupEntry[]
---@field active_group string?
---@field loaded boolean
local state = {
  groups = {},
  active_group = nil,
  loaded = false,
}

-- ============================================================================
-- DATA NORMALIZATION
-- ============================================================================

---Detect format and normalize to version 2 (groups format).
---Old format: { content = "BASE64", cursor_pos = {...}, last_modified = 123 }
---New format: { version = 2, groups = [...], active_group = "Default", last_modified = 123 }
---@param raw_data table Raw parsed JSON from Pantry
---@return table normalized Always in version 2 format (content still Base64-encoded)
function M.normalize(raw_data)
  if not raw_data then
    return {
      version = 2,
      groups = { { name = "Default", content = "", cursor_pos = { line = 1, col = 0 } } },
      active_group = "Default",
      last_modified = os.time(),
    }
  end

  -- Already new format
  if raw_data.version == 2 then
    return raw_data
  end

  -- Old format: wrap in single Default group
  return {
    version = 2,
    groups = {
      {
        name = "Default",
        content = raw_data.content or "",
        cursor_pos = raw_data.cursor_pos or { line = 1, col = 0 },
      },
    },
    active_group = "Default",
    last_modified = raw_data.last_modified or os.time(),
  }
end

-- ============================================================================
-- LOAD / SERIALIZE
-- ============================================================================

---Load groups from normalized data. Decodes Base64 content for each group.
---@param data table Normalized version 2 data (content is Base64-encoded)
function M.load(data)
  local normalized = M.normalize(data)

  state.groups = {}
  for _, g in ipairs(normalized.groups) do
    local decoded = pantry.decode_content(g.content)
    table.insert(state.groups, {
      name = g.name,
      content = decoded,
      cursor_pos = g.cursor_pos or { line = 1, col = 0 },
    })
  end

  state.active_group = normalized.active_group
  -- Ensure active_group points to a valid group
  if not M._find_group(state.active_group) then
    state.active_group = state.groups[1] and state.groups[1].name or nil
  end

  state.loaded = true
end

---Serialize state to version 2 format ready for Pantry (Base64-encodes content).
---@return table data Ready for JSON encoding and Pantry save
function M.serialize()
  local groups = {}
  for _, g in ipairs(state.groups) do
    table.insert(groups, {
      name = g.name,
      content = pantry.encode_content(g.content),
      cursor_pos = g.cursor_pos,
    })
  end

  return {
    version = 2,
    groups = groups,
    active_group = state.active_group,
    last_modified = os.time(),
  }
end

-- ============================================================================
-- GROUP QUERIES
-- ============================================================================

---Find a group entry by name (internal helper)
---@param name string?
---@return GroupEntry?, number?
function M._find_group(name)
  if not name then return nil, nil end
  for i, g in ipairs(state.groups) do
    if g.name == name then
      return g, i
    end
  end
  return nil, nil
end

---Get ordered list of groups with active indicator.
---@return { name: string, is_active: boolean }[]
function M.get_groups()
  local result = {}
  for _, g in ipairs(state.groups) do
    table.insert(result, {
      name = g.name,
      is_active = (g.name == state.active_group),
    })
  end
  return result
end

---Get the active group name.
---@return string?
function M.get_active_group()
  return state.active_group
end

---Get the active group's decoded content string.
---@return string
function M.get_active_content()
  local g = M._find_group(state.active_group)
  if g then
    return g.content or ""
  end
  return ""
end

---Update the active group's content in memory.
---@param content string
function M.set_active_content(content)
  local g = M._find_group(state.active_group)
  if g then
    g.content = content
  end
end

---Get the active group's cursor position.
---@return { line: number, col: number }
function M.get_active_cursor()
  local g = M._find_group(state.active_group)
  if g then
    return g.cursor_pos or { line = 1, col = 0 }
  end
  return { line = 1, col = 0 }
end

---Set the active group's cursor position.
---@param pos { line: number, col: number }
function M.set_active_cursor(pos)
  local g = M._find_group(state.active_group)
  if g then
    g.cursor_pos = pos
  end
end

-- ============================================================================
-- GROUP MUTATIONS
-- ============================================================================

---Switch active group. Caller should save current content first.
---@param name string
---@return boolean success
function M.set_active_group(name)
  local g = M._find_group(name)
  if not g then
    return false
  end
  state.active_group = name
  return true
end

---Add a new empty group. Returns false if name already exists or is empty.
---@param name string
---@return boolean success
function M.add_group(name)
  if not name or name == "" then
    return false
  end
  if M._find_group(name) then
    return false
  end
  table.insert(state.groups, {
    name = name,
    content = "",
    cursor_pos = { line = 1, col = 0 },
  })
  return true
end

---Remove a group by name. Cannot remove the last group.
---If removing the active group, switches to the first remaining group.
---@param name string
---@return boolean success
function M.remove_group(name)
  if #state.groups <= 1 then
    return false
  end

  local _, idx = M._find_group(name)
  if not idx then
    return false
  end

  table.remove(state.groups, idx)

  -- If we removed the active group, switch to first remaining
  if state.active_group == name then
    state.active_group = state.groups[1] and state.groups[1].name or nil
  end

  return true
end

---Rename a group. Returns false if new_name already exists or old_name not found.
---@param old_name string
---@param new_name string
---@return boolean success
function M.rename_group(old_name, new_name)
  if not new_name or new_name == "" then
    return false
  end
  if M._find_group(new_name) then
    return false
  end

  local g = M._find_group(old_name)
  if not g then
    return false
  end

  g.name = new_name

  -- Update active_group reference
  if state.active_group == old_name then
    state.active_group = new_name
  end

  return true
end

---Reorder a group up (swap with previous neighbor).
---@param name string
---@return boolean success
function M.reorder_up(name)
  local _, idx = M._find_group(name)
  if not idx or idx <= 1 then
    return false
  end
  state.groups[idx], state.groups[idx - 1] = state.groups[idx - 1], state.groups[idx]
  return true
end

---Reorder a group down (swap with next neighbor).
---@param name string
---@return boolean success
function M.reorder_down(name)
  local _, idx = M._find_group(name)
  if not idx or idx >= #state.groups then
    return false
  end
  state.groups[idx], state.groups[idx + 1] = state.groups[idx + 1], state.groups[idx]
  return true
end

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

---Check if groups are loaded.
---@return boolean
function M.is_loaded()
  return state.loaded
end

---Get the group name at a given 1-indexed position in the list.
---@param index number 1-indexed
---@return string?
function M.get_group_at(index)
  local g = state.groups[index]
  return g and g.name or nil
end

---Get total number of groups.
---@return number
function M.get_group_count()
  return #state.groups
end

---Reset all state (on close).
function M.reset()
  state.groups = {}
  state.active_group = nil
  state.loaded = false
end

return M
