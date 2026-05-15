-- Muttlook marker visibility: show reply-to context as virtual text
local M = {}

M.ns = vim.api.nvim_create_namespace('mail_muttlook_marker')

-- Pattern for the muttlook markers
M.reply_pattern = '%[//%]: # %(muttlook%-reply%-to:(.+)%)'
M.references_pattern = '%[//%]: # %(muttlook%-references:(.+)%)'

--- Find marker lines and extract message-id / references
---@param lines string[]
---@return {reply_to?: {line: integer, msgid: string}, references?: {line: integer, refs: string}}
function M.find_markers(lines)
  local result = {}
  for i, l in ipairs(lines) do
    local reply_id = l:match(M.reply_pattern)
    if reply_id then result.reply_to = { line = i - 1, msgid = reply_id } end
    local refs = l:match(M.references_pattern)
    if refs then result.references = { line = i - 1, refs = refs } end
  end
  return result
end

--- Legacy single-marker finder (backward compat)
---@param lines string[]
---@return integer? line_idx (0-indexed), string? msgid
function M.find_marker(lines)
  local markers = M.find_markers(lines)
  if markers.reply_to then
    return markers.reply_to.line, markers.reply_to.msgid
  end
  return nil, nil
end

--- Apply extmarks to show markers as virtual text
---@param bufnr integer
function M.apply(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = M.find_markers(lines)

  if markers.reply_to then
    vim.api.nvim_buf_set_extmark(bufnr, M.ns, markers.reply_to.line, 0, {
      virt_text = { { ' ↩ replying to: ' .. markers.reply_to.msgid:sub(1, 50), 'Comment' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
  end

  if markers.references then
    vim.api.nvim_buf_set_extmark(bufnr, M.ns, markers.references.line, 0, {
      virt_text = { { ' 🔗 thread: ' .. markers.references.refs:sub(1, 60), 'Comment' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
  end
end

return M
