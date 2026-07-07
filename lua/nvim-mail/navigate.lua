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

--- Collect all quoted-signature ranges in a line array (pure, no buffer I/O)
--- Each range is { start = <1-based>, stop = <1-based> } covering the
--- '> --' separator line and every following quoted line.
---@param lines string[]
---@return {start: integer, stop: integer}[]
function M.collect_quoted_sig_ranges(lines)
  local ranges = {}
  for i, l in ipairs(lines) do
    -- Capture the exact quote prefix so we only extend the range to lines
    -- at the SAME depth. Without this, a deeper-quote signature (e.g. '> > --')
    -- would swallow subsequent shallower lines (e.g. '> Alice reply') and
    -- silently delete them from the thread.
    local prefix = l:match('^(>[ >]*)%-%-')
    if prefix then
      local stop = i
      for j = i + 1, #lines do
        if lines[j]:sub(1, #prefix) == prefix then
          stop = j
        else
          break
        end
      end
      ranges[#ranges + 1] = { start = i, stop = stop }
    end
  end
  return ranges
end

--- Kill all quoted signatures (lines starting with "> -- " and the quoted
--- lines that follow). Handles multiple quoted-sig blocks in long threads.
function M.kill_quoted_sig()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local ranges = M.collect_quoted_sig_ranges(lines)
  -- Remove bottom-to-top so earlier line indices remain valid
  for k = #ranges, 1, -1 do
    vim.api.nvim_buf_set_lines(0, ranges[k].start - 1, ranges[k].stop, false, {})
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
  -- If spell is currently off, start cycle from first lang
  if not vim.opt_local.spell:get() then
    vim.opt_local.spell = true
    vim.opt_local.spelllang = langs[1]
    vim.notify('Spell: ' .. langs[1], vim.log.levels.INFO)
    return
  end
  local current = vim.opt_local.spelllang:get()
  local cur_str = table.concat(current, ',')
  -- Find current in list, cycle to next; exceed length means spell off
  for idx, lang in ipairs(langs) do
    if cur_str == lang then
      local next_idx = idx + 1
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
  -- Current lang not in list, set first
  vim.opt_local.spell = true
  vim.opt_local.spelllang = langs[1]
  vim.notify('Spell: ' .. langs[1], vim.log.levels.INFO)
end

return M
