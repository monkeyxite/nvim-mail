-- Muttlook marker visibility: show reply-to context as virtual text
local M = {}

M.ns = vim.api.nvim_create_namespace('mail_muttlook_marker')

-- Pattern for the muttlook reply-to marker
M.marker_pattern = '%[//%]: # %(muttlook%-reply%-to:(.+)%)'

--- Find marker line and extract message-id
---@param lines string[]
---@return integer? line_idx (0-indexed), string? msgid
function M.find_marker(lines)
  for i, l in ipairs(lines) do
    local msgid = l:match(M.marker_pattern)
    if msgid then return i - 1, msgid end
  end
  return nil, nil
end

--- Apply extmark to show marker as virtual text
---@param bufnr integer
function M.apply(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line_idx, msgid = M.find_marker(lines)
  if not line_idx or not msgid then return end

  -- Conceal the raw marker line
  vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_idx, 0, {
    virt_text = { { ' ↩ replying to: ' .. msgid:sub(1, 50), 'Comment' } },
    virt_text_pos = 'overlay',
    hl_mode = 'combine',
  })
end

return M
