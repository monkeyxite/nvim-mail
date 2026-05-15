-- Mail navigation: jump to headers, body sections, signature
local M = {}

--- Go to a header field and position cursor
---@param field string pattern like "^To:" or "^Subject:"
---@param after? string "A" for end of line, "W" for first word
function M.goto_field(field, after)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l == '' then break end
    if l:match(field) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      if after == 'A' then vim.cmd('normal! A')
      elseif after == 'W' then vim.cmd('normal! Wl') end
      return
    end
  end
end

--- Jump to body (first empty line after headers)
function M.goto_body()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l == '' then
      vim.api.nvim_win_set_cursor(0, { i + 1, 0 })
      return
    end
  end
end

--- Jump to signature (line starting with "-- ")
function M.goto_signature()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l == '-- ' then
      vim.api.nvim_win_set_cursor(0, { i + 1, 0 })
      return
    end
  end
end

--- Jump to first quoted line
function M.goto_reply()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:match('^>') then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
  end
end

--- Jump to end of own text (line before first quote)
function M.goto_end_of_reply()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local in_body = false
  for i, l in ipairs(lines) do
    if not in_body and l == '' then in_body = true end
    if in_body and l:match('^>') then
      vim.api.nvim_win_set_cursor(0, { i - 1, 0 })
      return
    end
  end
end

--- Kill quoted signatures (lines after "> -- " in quotes)
function M.kill_quoted_sig()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local start = nil
  for i, l in ipairs(lines) do
    if l:match('^> ?%-%-') then
      start = i
    end
  end
  if start then
    -- Find end of this quoted block
    local stop = start
    for i = start + 1, #lines do
      if lines[i]:match('^>') then stop = i
      else break end
    end
    vim.api.nvim_buf_set_lines(0, start - 1, stop, false, {})
  end
end

--- Switch From address from a list
---@param from_list string[]
function M.switch_from(from_list)
  if not from_list or #from_list == 0 then
    vim.notify('No from addresses configured', vim.log.levels.WARN)
    return
  end
  vim.ui.select(from_list, { prompt = 'Select From:' }, function(choice)
    if not choice then return end
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l == '' then break end
      if l:match('^From:') then
        vim.api.nvim_buf_set_lines(0, i - 1, i, false, { 'From: ' .. choice })
        return
      end
    end
  end)
end

--- Switch spell language cycling
---@param langs string[]
function M.switch_spell(langs)
  langs = langs or { 'en', 'sv' }
  local current = vim.opt_local.spelllang:get()
  local cur_str = table.concat(current, ',')
  -- Find current in list, cycle to next
  for idx, lang in ipairs(langs) do
    if cur_str == lang then
      local next_idx = idx % #langs + 1
      if next_idx > #langs then
        vim.opt_local.spell = false
        vim.notify('Spell off', vim.log.levels.INFO)
      else
        vim.opt_local.spell = true
        vim.opt_local.spelllang = langs[next_idx]
        vim.notify('Spell: ' .. langs[next_idx], vim.log.levels.INFO)
      end
      return
    end
  end
  -- Not found, set first
  vim.opt_local.spell = true
  vim.opt_local.spelllang = langs[1]
  vim.notify('Spell: ' .. langs[1], vim.log.levels.INFO)
end

return M
