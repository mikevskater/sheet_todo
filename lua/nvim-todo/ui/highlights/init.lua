---@class nvim-todo.ui.highlights
local groups = require('nvim-todo.ui.highlights.groups')
local color = require('nvim-todo.ui.highlights.color')

return {
  setup = groups.setup,
  get_color_hl = color.get_color_hl,
  clear_cache = color.clear_cache,
}
