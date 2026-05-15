local marker = require('nvim-mail.marker')

describe('mail.marker', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function read_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    return lines
  end

  describe('find_marker', function()
    it('finds muttlook-reply-to marker and extracts msgid', function()
      local lines = read_fixture('draft_with_marker.txt')
      local line_idx, msgid = marker.find_marker(lines)
      assert.is_not_nil(line_idx)
      assert.equals('<abc123@mail.example.com>', msgid)
    end)

    it('returns nil when no marker present', function()
      local lines = read_fixture('draft_no_attach.txt')
      local line_idx, msgid = marker.find_marker(lines)
      assert.is_nil(line_idx)
      assert.is_nil(msgid)
    end)
  end)

  describe('find_markers', function()
    it('finds both reply-to and references markers', function()
      local lines = read_fixture('draft_with_both_markers.txt')
      local markers = marker.find_markers(lines)
      assert.is_not_nil(markers.reply_to)
      assert.equals('<parent-id@example.com>', markers.reply_to.msgid)
      assert.is_not_nil(markers.references)
      assert.equals('<first@example.com> <parent-id@example.com>', markers.references.refs)
    end)

    it('returns empty table when no markers', function()
      local lines = read_fixture('draft_no_attach.txt')
      local markers = marker.find_markers(lines)
      assert.is_nil(markers.reply_to)
      assert.is_nil(markers.references)
    end)

    it('finds reply-to only when no references', function()
      local lines = read_fixture('draft_with_marker.txt')
      local markers = marker.find_markers(lines)
      assert.is_not_nil(markers.reply_to)
      assert.is_nil(markers.references)
    end)
  end)

  describe('apply', function()
    it('sets extmark on marker line', function()
      local lines = read_fixture('draft_with_marker.txt')
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      marker.apply(buf)

      local marks = vim.api.nvim_buf_get_extmarks(buf, marker.ns, 0, -1, { details = true })
      assert.equals(1, #marks)
      assert.is_truthy(marks[1][4].virt_text[1][1]:find('replying to'))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('sets two extmarks when both markers present', function()
      local lines = read_fixture('draft_with_both_markers.txt')
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      marker.apply(buf)

      local marks = vim.api.nvim_buf_get_extmarks(buf, marker.ns, 0, -1, { details = true })
      assert.equals(2, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('does nothing when no marker', function()
      local lines = read_fixture('draft_no_attach.txt')
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      marker.apply(buf)

      local marks = vim.api.nvim_buf_get_extmarks(buf, marker.ns, 0, -1, {})
      assert.equals(0, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
