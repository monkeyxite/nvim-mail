-- Thread context: show notmuch thread in a vsplit
local M = {}

local marker = require('nvim-mail.marker')

--- Extract message-id from headers or muttlook marker
---@param lines string[]
---@return string? msgid (without angle brackets)
function M.extract_msgid(lines)
  -- First try In-Reply-To header
  for _, l in ipairs(lines) do
    if l == '' then break end -- end of headers
    local id = l:match('^In%-Reply%-To:%s*<?([^>]+)>?')
    if id then return id end
  end
  -- Fallback to muttlook marker
  local markers = marker.find_markers(lines)
  if markers.reply_to then
    -- Strip angle brackets if present
    return markers.reply_to.msgid:match('^<?([^>]+)>?$')
  end
  return nil
end

--- Build command to show thread (nm-html-extract for readable output)
---@param msgid string
---@return string
function M.build_cmd(msgid)
  return string.format('nm-html-extract %s', msgid)
end

--- Build fallback command (plain text, no rendering)
---@param msgid string
---@return string
function M.build_cmd_plain(msgid)
  return string.format('notmuch show --format=text --entire-thread=true thread:{id:%s}', msgid)
end

--- Open thread context in a vsplit with ANSI color support
---@param bufnr? integer
function M.show(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local msgid = M.extract_msgid(lines)
  if not msgid then
    vim.notify('No reply-to found — cannot show thread', vim.log.levels.WARN)
    return
  end

  -- Open terminal buffer running nm-html-extract (renders ANSI natively)
  vim.cmd('below new')
  vim.fn.termopen(M.build_cmd(msgid), {
    on_exit = function()
      vim.bo.modifiable = false
    end,
  })
  vim.bo.swapfile = false
  vim.api.nvim_buf_set_name(0, '[Thread: ' .. msgid:sub(1, 30) .. ']')
  -- Enter normal mode after terminal opens
  vim.cmd('normal! G')
  vim.cmd('normal! gg')
end

return M
