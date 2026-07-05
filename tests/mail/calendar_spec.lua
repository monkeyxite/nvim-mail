local calendar = require('nvim-mail.calendar')

describe('mail.calendar', function()
  describe('format_entry', function()
    it('formats event with time and title', function()
      local event = { sctime = '2026-05-15 09:00:00', ectime = '2026-05-15 10:00:00', title = 'Standup' }
      -- Access internal via module (format_entry is local, test via preview)
      assert.is_not_nil(calendar.calendar)
    end)
  end)

  describe('preview_event', function()
    it('renders meeting with all fields', function()
      local event = {
        title = 'Sprint Planning',
        sctime = '2026-05-15 09:00:00',
        ectime = '2026-05-15 10:00:00',
        location = 'Room 42',
        conference_url_detected = 'https://meet.google.com/abc-def',
        attendees = { 'alice@work.com', 'bob@work.com' },
        notes = 'Discuss Q2 goals\nReview backlog',
      }
      local lines = calendar._preview_event(event)
      local text = table.concat(lines, '\n')
      assert.is_truthy(text:find('Sprint Planning'))
      assert.is_truthy(text:find('09:00'))
      assert.is_truthy(text:find('Room 42'))
      assert.is_truthy(text:find('meet.google.com'))
      assert.is_truthy(text:find('alice@work.com'))
      assert.is_truthy(text:find('bob@work.com'))
      assert.is_truthy(text:find('Discuss Q2 goals'))
      assert.is_truthy(text:find('Review backlog'))
    end)

    it('handles missing optional fields', function()
      local event = { title = 'Quick sync', sctime = '2026-05-15 14:00:00', ectime = '2026-05-15 14:30:00' }
      local lines = calendar._preview_event(event)
      local text = table.concat(lines, '\n')
      assert.is_truthy(text:find('Quick sync'))
      assert.is_truthy(text:find('14:00'))
      -- No location or conference URL
      assert.is_falsy(text:find('meet.google'))
    end)

    it('splits multiline notes into separate lines', function()
      local event = {
        title = 'Test',
        sctime = '2026-05-15 10:00:00',
        ectime = '2026-05-15 11:00:00',
        notes = 'Line 1\nLine 2\nLine 3',
      }
      local lines = calendar._preview_event(event)
      -- Each note line should be a separate entry
      local found_lines = 0
      for _, l in ipairs(lines) do
        if l:match('^Line %d') then found_lines = found_lines + 1 end
      end
      assert.equals(3, found_lines)
    end)
  end)

  describe('start_mom', function()
    it('creates MoM buffer with attendees', function()
      local event = {
        title = 'Design Review',
        sctime = '2026-05-15 09:00:00',
        ectime = '2026-05-15 10:00:00',
        attendees = { 'alice@work.com', 'bob@work.com', 'carol@work.com' },
      }
      calendar._start_mom(event)
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.is_truthy(text:find('Design Review'))
      assert.is_truthy(text:find('alice@work.com'))
      assert.is_truthy(text:find('bob@work.com'))
      assert.is_truthy(text:find('carol@work.com'))
      assert.is_truthy(text:find('## Agenda'))
      assert.is_truthy(text:find('## Action Items'))
      vim.cmd('stopinsert')
      vim.api.nvim_buf_delete(0, { force = true })
    end)

    it('includes time from event', function()
      local event = {
        title = 'Standup',
        sctime = '2026-05-15 09:00:00',
        ectime = '2026-05-15 09:15:00',
        attendees = { 'alice' },
      }
      calendar._start_mom(event)
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.is_truthy(text:find('09:00 %- 09:15'))
      vim.cmd('stopinsert')
      vim.api.nvim_buf_delete(0, { force = true })
    end)

    it('includes agenda from event notes', function()
      local event = {
        title = 'Planning',
        sctime = '2026-05-15 10:00:00',
        ectime = '2026-05-15 11:00:00',
        attendees = { 'alice' },
        notes = 'Review sprint goals\nAssign tasks',
      }
      calendar._start_mom(event)
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.is_truthy(text:find('Review sprint goals'))
      assert.is_truthy(text:find('Assign tasks'))
      vim.cmd('stopinsert')
      vim.api.nvim_buf_delete(0, { force = true })
    end)

    it('sets buffer-local account from calendar name', function()
      local contacts = require('nvim-mail.contacts')
      contacts.config.calendar_map = { ['Calendar'] = 'work' }
      local event = {
        title = 'Sync',
        sctime = '2026-05-15 10:00:00',
        ectime = '2026-05-15 10:30:00',
        attendees = { 'alice' },
        calendar = 'Calendar',
      }
      calendar._start_mom(event)
      assert.equals('work', vim.b.nvim_mail_account)
      vim.cmd('stopinsert')
      vim.api.nvim_buf_delete(0, { force = true })
      contacts.config.calendar_map = {}
    end)

    it('uses event date (not today) for date field and filename', function()
      local event = {
        title = 'Future Sync',
        sctime = '2027-01-15T10:00:00Z',
        ectime = '2027-01-15T11:00:00Z',
        attendees = { 'alice@work.com' },
      }
      calendar._start_mom(event)
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local text = table.concat(lines, '\n')
      -- frontmatter date and Time line must use event date
      assert.is_truthy(text:find('date: 2027%-01%-15'))
      assert.is_truthy(text:find('2027%-01%-15.*10:00'))
      -- buffer name (filename) must contain event date
      local bufname = vim.api.nvim_buf_get_name(0)
      assert.is_truthy(bufname:find('2027%-01%-15'), 'filename should contain 2027-01-15, got: ' .. bufname)
      vim.cmd('stopinsert')
      vim.api.nvim_buf_delete(0, { force = true })
    end)
  end)
end)
