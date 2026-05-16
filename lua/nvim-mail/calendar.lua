-- Telescope calendar search (mirrors kms-select)
-- Usage: require('telescope').extensions.nvim_mail.calendar()
local M = {}

local function get_events(date_arg)
  date_arg = date_arg or 'today'
  local cmd, extra
  if date_arg == 'today' then cmd = 'eventsToday'; extra = ''
  elseif date_arg == 'tomorrow' then cmd = 'eventsToday+1'; extra = ''
  elseif date_arg:match('^%+') then cmd = 'eventsToday' .. date_arg; extra = ''
  elseif date_arg:match('^%-') or date_arg:match('^%d%d%d%d%-') then
    cmd = 'events'; extra = '--from=' .. date_arg .. ' --to=' .. date_arg
  else cmd = 'eventsToday'; extra = '' end

  local icalpal_cmd = 'icalpal ' .. cmd .. ' ' .. extra ..
    ' --iep "title,datetime,attendees,notes,url,conference_url_detected,location,sctime,ectime" --sort "datetime" --nc --ea --nb --npn -o json 2>/dev/null'
  local output = vim.fn.system({ 'sh', '-c', icalpal_cmd })
  if vim.v.shell_error ~= 0 then return {} end
  local ok, data = pcall(vim.json.decode, output)
  if not ok or not data then return {} end
  return data
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
  if s ~= '' then lines[#lines + 1] = '**󰔛 ' .. s .. ' – ' .. t .. '**' end
  if event.location and event.location ~= '' then
    lines[#lines + 1] = '**󰍎 ' .. event.location .. '**'
  end
  if event.conference_url_detected and event.conference_url_detected ~= '' then
    lines[#lines + 1] = '**󰌷 ' .. event.conference_url_detected .. '**'
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## Attendees'
  for i, a in ipairs(event.attendees or {}) do
    lines[#lines + 1] = '- ' .. (i == 1 and '󰀄 ' or '') .. a
  end
  if event.notes and event.notes ~= '' then
    lines[#lines + 1] = ''
    lines[#lines + 1] = '## Notes'
    lines[#lines + 1] = event.notes
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

  local date_arg = opts.date or 'today'
  local events = get_events(date_arg)

  -- Deduplicate by title+time
  local seen, unique = {}, {}
  for _, e in ipairs(events) do
    local key = (e.title or '') .. (e.sctime or '')
    if not seen[key] then
      seen[key] = true
      unique[#unique + 1] = e
    end
  end

  pickers.new(opts, {
    prompt_title = '  Calendar (' .. date_arg .. ')',
    finder = finders.new_table({
      results = unique,
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
    sorter = require('telescope.sorters').empty(),
    attach_mappings = function(prompt_bufnr, map)
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
      map({ 'i', 'n' }, '<C-r>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.value then
          local attendees = entry.value.attendees or {}
          local lines = {
            'To: ' .. table.concat(attendees, ', '),
            'Subject: Re: ' .. (entry.value.title or ''),
            '',
            '',
          }
          vim.cmd('enew')
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
          vim.bo.filetype = 'mail'
          vim.api.nvim_win_set_cursor(0, { 4, 0 })
          vim.cmd('startinsert')
        end
      end)

      return true
    end,
  }):find()
end

return M
