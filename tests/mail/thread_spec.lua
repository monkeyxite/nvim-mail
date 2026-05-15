local thread = require('nvim-mail.thread')

describe('mail.thread', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function read_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    return lines
  end

  describe('extract_msgid', function()
    it('extracts from In-Reply-To header', function()
      local lines = read_fixture('draft_reply_with_thread.txt')
      local msgid = thread.extract_msgid(lines)
      assert.equals('thread-msg-123@example.com', msgid)
    end)

    it('extracts from muttlook marker', function()
      local lines = read_fixture('draft_with_marker.txt')
      local msgid = thread.extract_msgid(lines)
      assert.equals('abc123@mail.example.com', msgid)
    end)

    it('prefers In-Reply-To over marker', function()
      local lines = read_fixture('draft_reply_with_thread.txt')
      local msgid = thread.extract_msgid(lines)
      assert.equals('thread-msg-123@example.com', msgid)
    end)

    it('returns nil for new message', function()
      local lines = read_fixture('draft_new_message.txt')
      local msgid = thread.extract_msgid(lines)
      assert.is_nil(msgid)
    end)
  end)

  describe('build_cmd', function()
    it('builds notmuch show command from msgid', function()
      local cmd = thread.build_cmd('test-id@example.com')
      assert.is_truthy(cmd:find('notmuch', 1, true))
      assert.is_truthy(cmd:find('test-id@example.com', 1, true))
    end)
  end)
end)
