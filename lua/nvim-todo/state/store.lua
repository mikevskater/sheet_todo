---@class nvim-todo.state.store
---@field loading boolean Whether data is currently being fetched
---@field saving boolean Whether data is currently being saved
---@field last_error string|nil Last error message, nil if no error
local store = {
  loading = false,
  saving = false,
  last_error = nil,
}

return store
