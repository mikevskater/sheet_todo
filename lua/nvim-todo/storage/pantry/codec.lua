---@class nvim-todo.storage.pantry.codec
local M = {}

---Base64-encode content for safe JSON transport.
---@param content string? Raw content string
---@return string encoded Base64-encoded string, or "" if nil/empty
function M.encode_content(content)
  if not content or content == "" then
    return ""
  end
  return vim.base64.encode(content)
end

---Base64-decode content back to original string.
---Strips whitespace injected by JSON formatting. Returns raw string on decode failure.
---@param encoded string? Base64-encoded string
---@return string decoded Original content, or "" if nil/empty
function M.decode_content(encoded)
  if not encoded or encoded == "" then
    return ""
  end
  encoded = encoded:gsub('%s', '')
  local ok, decoded = pcall(vim.base64.decode, encoded)
  if not ok then
    return encoded
  end
  return decoded
end

return M
