---@class nvim-todo.storage.pantry
local M = {}

local client = require('nvim-todo.storage.pantry.client')
local codec = require('nvim-todo.storage.pantry.codec')
local url = require('nvim-todo.storage.pantry.url')

M.get_raw_data = client.get_raw_data
M.save_raw_data = client.save_raw_data
M.encode_content = codec.encode_content
M.decode_content = codec.decode_content
M.is_configured = url.is_configured
M.get_basket_url = url.get_basket_url

return M
