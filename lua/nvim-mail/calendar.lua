-- Telescope calendar search (mirrors kms-select)
-- Usage: require('telescope').extensions.nvim_mail.calendar()
local M = {}

--- Build the kcal command args for a date string.
local function kcal_args(date_arg)
  date_arg = date_arg or 'today'
  if date_arg == 'today' then return { 'kcal', 'eventsToday' }
  elseif date_arg == 'tomorrow' then return { 'kcal', 'eventsToday+1' }
  elseif date_arg:match('^%+%d') then return { 'kcal', 'eventsToday' .. date_arg }
  elseif date_arg:match('^%-') or date_arg:match('^%d%d%d%d%-') then
    return { 'kcal', 'events', '--from=' .. date_arg, '--to=' .. date_arg }
  end
  return { 'kcal', 'eventsToday' }
end

--- Fetch events synchronously (used for initial open).
local function get_events(date_arg)
  local result = vim.system(kcal_args(date_arg), { text = true }):wait()
  if result.code ~= 0 then return {} end
  local ok, data = pcall(vim.json.decode, result.stdout)
  return (ok and data) or {}
end

--- Fetch events asynchronously, call cb(events) on completion.
local function get_events_async(date_arg, cb)
  vim.system(kcal_args(date_arg), { text = true }, function(result)
    local ok, data = pcall(vim.json.decode, result.stdout or '')
    vim.schedule(function() cb((ok and data) or {}) end)
  end)
end

local function format_entry(event)
  local s = (event.sctime or ''):sub(12, 16)
  local t = (event.ectime or ''):sub(12, 16)
  return string.format('%s-%s  %s', s, t, event.title or '?')
end

local function preview_event(event)
  local lines = {}
  lines[#lines + 1] = '# ' .. (event.title or '')
  local s = (event.sctime or ''):sub(12, 16)
  local t = (event.ectime or ''):sub(12, 16)
  if s ~= '' then lines[#lines + 1] = '**󰔛 ' .. s .. ' - ' .. t .. '**' end
  if event.location and type(event.location) == 'string' and event.location ~= '' then
    lines[#lines + 1] = '**󰍎 ' .. event.location .. '**'
  end
  if event.conference_url_detected and type(event.conference_url_detected) == 'string' and event.conference_url_detected ~= '' then
    lines[#lines + 1] = '**󰌷 ' .. event.conference_url_detected .. '**'
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## Attendees'
  for i, a in ipairs(event.attendees or {}) do
    lines[#lines + 1] = '- ' .. (i == 1 and '󰀄 ' or '') .. a
  end
  if event.notes and type(event.notes) == 'string' and event.notes ~= '' then
    lines[#lines + 1] = ''
    lines[#lines + 1] = '## Notes'
    for _, l in ipairs(vim.split(event.notes, '\n')) do
      lines[#lines + 1] = l
    end
  end
  return lines
end

local function start_mom(event)
  -- Create MoM buffer from meeting template
  local lines = {
    '---',
    'title: "MoM: ' .. (event.title or '') .. '"',
    'date: ' .. os.date('%Y-%m-%d'),
    'tags: [mom, meeting]',
    '---',
    '',
    '# MoM: ' .. (event.title or ''),
    '',
    '## Attendees',
  }
  for _, a in ipairs(event.attendees or {}) do
    lines[#lines + 1] = '- [ ] ' .. a
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## Agenda'
  lines[#lines + 1] = ''
  lines[#lines + 1] = '1. '
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## Action Items'
  lines[#lines + 1] = ''
  lines[#lines + 1] = '- [ ] '
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## Notes'
  lines[#lines + 1] = ''

  vim.cmd('enew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = 'markdown'
  -- Position cursor at Agenda item
  vim.api.nvim_win_set_cursor(0, { 14, 3 })
  vim.cmd('startinsert')
end

function M.calendar(opts)
  opts = opts or {}
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')
  local conf = require('telescope.config').values

  -- Parse date from prompt: today, tomorrow, +N, -N, YYYY-MM-DD
  -- Otherwise fuzzy-filter current day's events
  local function parse_date(input)
    if not input or input == '' then return 'today' end
    if input:match('^today') then return 'today' end
    if input:match('^tomorrow') then return 'tomorrow' end
    if input:match('^%+%d') then return input:match('^(%+%d+)') end
    if input:match('^%-?%d%d%d%d%-') then return input:match('^(%-?%d%d%d%d%-%d%d%-%d%d)') end
    if input:match('^%-%d') then return input:match('^(%-?%d+)') end
    return nil -- not a date, use as filter
  end

  local current_date = opts.date or 'today'
  local events = opts.events or get_events(current_date)

  -- Deduplicate
  local function dedup(evts)
    local seen, unique = {}, {}
    for _, e in ipairs(evts) do
      local key = (e.title or '') .. (e.sctime or '')
      if not seen[key] then seen[key] = true; unique[#unique + 1] = e end
    end
    return unique
  end

  pickers.new(opts, {
    prompt_title = '  Calendar (' .. current_date .. ')  C-s:date  C-o:url  C-r:MoM mail',
    finder = finders.new_table({
      results = dedup(events),
      entry_maker = function(event)
        return {
          value = event,
          display = format_entry(event),
          ordinal = (event.title or '') .. ' ' .. table.concat(event.attendees or {}, ' '),
        }
      end,
    }),
    previewer = previewers.new_buffer_previewer({
      title = 'Meeting Details',
      define_preview = function(self, entry)
        if not entry or not entry.value then return end
        local lines = preview_event(entry.value)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = 'markdown'
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      -- Ctrl+s: switch to date from prompt (async fetch, no UI block)
      map({ 'i', 'n' }, '<C-s>', function()
        local prompt = action_state.get_current_line()
        local new_date = parse_date(prompt)
        if new_date then
          actions.close(prompt_bufnr)
          get_events_async(new_date, function(new_events)
            M.calendar({ date = new_date, events = new_events })
          end)
        end
      end)
      -- Enter: start MoM
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.value then
          start_mom(entry.value)
        end
      end)

      -- Ctrl+o: open conference URL
      map({ 'i', 'n' }, '<C-o>', function()
        local entry = action_state.get_selected_entry()
        if entry and entry.value then
          local url = entry.value.conference_url_detected or entry.value.url
          if url and url ~= '' then
            vim.fn.system({ 'open', url })
          else
            vim.notify('No conference URL', vim.log.levels.WARN)
          end
        end
      end)

      -- Ctrl+r: reply/email attendees
      -- C-r: compose MoM mail with attendee email lookup via khard (async, parallel)
      map({ 'i', 'n' }, '<C-r>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry or not entry.value then return end
        local event = entry.value
        local attendees = event.attendees or {}
        if #attendees == 0 then return end

        -- Clean notes: strip mailto, Teams boilerplate, normalize newlines
        local function clean_notes(s)
          return (s or '')
            :gsub('<mailto:[^>]+>', '')
            :gsub('\r\n', '\n'):gsub('\r', '\n')
            :gsub('\n_{3,}.*', ''):gsub('\nMicrosoft Teams meeting.*', '')
            :gsub('<https?://[^>]+>', '')
            :gsub('\n\n\n+', '\n\n')
            :gsub('^%s+', ''):gsub('%s+$', '')
        end

        local function open_buffer(emails)
          local date_str = os.date('%Y-%m-%d')
          local s = (event.sctime or ''):sub(12, 16)
          local t = (event.ectime or ''):sub(12, 16)
          local notes = clean_notes(event.notes)
          local lines = {
            'To: ' .. table.concat(emails, ', '),
            'Subject: MoM: ' .. (event.title or ''),
            '',
            '## ' .. (event.title or '') .. ' - ' .. date_str,
            '',
            '**Date**: ' .. date_str .. '  ' .. s .. ' - ' .. t,
            '**Attendees**: ' .. table.concat(attendees, ', '),
            '',
          }
          if notes ~= '' then
            vim.list_extend(lines, { '## Agenda', '' })
            vim.list_extend(lines, vim.split(notes, '\n'))
            lines[#lines + 1] = ''
          end
          vim.list_extend(lines, { '## Notes', '', '', '## Action Points', '', '- [ ] ' })
          vim.cmd('enew')
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
          vim.bo.filetype = 'mail'
          vim.api.nvim_win_set_cursor(0, { #lines - 3, 0 })
          vim.cmd('startinsert')
        end

        -- Open instantly with display names; use ,mC to resolve emails later
        open_buffer(attendees)
      end)

      return true
    end,
  }):find()
end

-- Expose internals for testing
M._preview_event = preview_event
M._start_mom = start_mom
M._clean_notes = function(s)
  return (s or '')
    :gsub('<mailto:[^>]+>', '')
    :gsub('\r\n', '\n'):gsub('\r', '\n')
    :gsub('\n_{3,}.*', ''):gsub('\nMicrosoft Teams meeting.*', '')
    :gsub('<https?://[^>]+>', '')
    :gsub('\n\n\n+', '\n\n')
    :gsub('^%s+', ''):gsub('%s+$', '')
end
M._format_entry = function(event)
  local s = (event.sctime or ''):sub(12, 16)
  local t = (event.ectime or ''):sub(12, 16)
  return string.format('%s-%s  %s', s, t, event.title or '?')
end

return M
