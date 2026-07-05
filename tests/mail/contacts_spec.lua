local contacts = require('nvim-mail.contacts')

describe('mail.contacts', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function read_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    return lines
  end

  describe('is_header_line', function()
    it('detects To: line', function()
      assert.is_true(contacts.is_header_line('To: someone@example.com'))
    end)

    it('detects Cc: line', function()
      assert.is_true(contacts.is_header_line('Cc: bob@work.com'))
    end)

    it('detects Bcc: line', function()
      assert.is_true(contacts.is_header_line('Bcc: secret@example.com'))
    end)

    it('rejects Subject line', function()
      assert.is_false(contacts.is_header_line('Subject: hello'))
    end)

    it('rejects body text', function()
      assert.is_false(contacts.is_header_line('Hello, how are you?'))
    end)
  end)

  describe('extract_query', function()
    it('extracts partial name after last comma', function()
      assert.equals('bob', contacts.extract_query('To: alice@x.com, bob'))
    end)

    it('extracts from start of field', function()
      assert.equals('ali', contacts.extract_query('To: ali'))
    end)

    it('returns empty for bare header', function()
      assert.equals('', contacts.extract_query('To: '))
    end)
  end)

  describe('parse_khard_line', function()
    it('parses tab-separated khard output', function()
      local item = contacts.parse_khard_line('john@example.com\tJohn Doe\tWork')
      assert.equals('john@example.com', item.email)
      assert.equals('John Doe', item.name)
      assert.equals('Work', item.type)
    end)

    it('handles missing type field', function()
      local item = contacts.parse_khard_line('john@example.com\tJohn Doe')
      assert.equals('john@example.com', item.email)
      assert.equals('John Doe', item.name)
    end)

    it('returns nil for empty line', function()
      assert.is_nil(contacts.parse_khard_line(''))
    end)
  end)

  describe('parse_khard_output', function()
    it('parses multi-line khard stdout', function()
      local output = 'alice@example.com\tAlice\tWork\nbob@test.com\tBob\tHome\n'
      local results = contacts.parse_khard_output(output)
      assert.equals(2, #results)
      assert.equals('alice@example.com', results[1].email)
      assert.equals('Alice', results[1].name)
      assert.equals('bob@test.com', results[2].email)
    end)

    it('returns empty list for empty output', function()
      assert.equals(0, #contacts.parse_khard_output(''))
    end)
  end)

  describe('parse_notmuch_output', function()
    it('parses notmuch JSON address output', function()
      local json = '[{"name":"Alice","address":"alice@example.com","name-addr":"Alice <alice@example.com>"},{"name":"","address":"bob@test.com","name-addr":"bob@test.com"}]'
      local results = contacts.parse_notmuch_output(json)
      assert.equals(2, #results)
      assert.equals('alice@example.com', results[1].email)
      assert.equals('Alice', results[1].name)
      assert.equals('notmuch', results[1].type)
      assert.equals('bob@test.com', results[2].email)
    end)

    it('returns empty list for empty output', function()
      assert.equals(0, #contacts.parse_notmuch_output(''))
    end)

    it('returns empty list on invalid JSON', function()
      assert.equals(0, #contacts.parse_notmuch_output('not json'))
    end)
  end)

  describe('detect_account', function()
    it('detects work account from From header', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: John <john@work.com>',
        'To: someone@example.com',
        '',
        'body',
      })
      vim.api.nvim_set_current_buf(buf)
      contacts.config.from_map = { ['work%.com'] = 'work', ['gmail%.com'] = 'personal' }
      assert.equals('work', contacts.detect_account())
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('returns nil for unknown sender', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: John <john@unknown.org>',
        'To: someone@example.com',
        '',
        'body',
      })
      vim.api.nvim_set_current_buf(buf)
      contacts.config.from_map = { ['work%.com'] = 'work' }
      assert.is_nil(contacts.detect_account())
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('prefers buffer-local account over From header', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: John <john@work.com>',
        'To: someone@example.com',
        '',
        'body',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.b.nvim_mail_account = 'personal'
      contacts.config.from_map = { ['work%.com'] = 'work' }
      assert.equals('personal', contacts.detect_account())
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('account_from_calendar', function()
    it('maps calendar name to account', function()
      contacts.config.calendar_map = { ['Calendar'] = 'work', ['monkeyxite'] = 'personal' }
      assert.equals('work', contacts.account_from_calendar('Calendar'))
      assert.equals('personal', contacts.account_from_calendar('monkeyxite@gmail.com'))
    end)

    it('returns nil for unknown calendar', function()
      contacts.config.calendar_map = { ['Calendar'] = 'work' }
      assert.is_nil(contacts.account_from_calendar('Holidays'))
    end)

    it('returns nil for empty/nil input', function()
      contacts.config.calendar_map = { ['Calendar'] = 'work' }
      assert.is_nil(contacts.account_from_calendar(nil))
      assert.is_nil(contacts.account_from_calendar(''))
    end)
  end)

  -- Legacy test kept for parse logic coverage (no longer calls vim.fn.system)
  describe('query_notmuch (parse logic)', function()
    it('parses notmuch JSON address output', function()
      local json = '[{"name":"Alice","address":"alice@example.com","name-addr":"Alice <alice@example.com>"},{"name":"","address":"bob@test.com","name-addr":"bob@test.com"}]'
      local data = vim.json.decode(json)
      local results = {}
      for _, entry in ipairs(data) do
        if entry.address then
          results[#results + 1] = {
            email = entry.address,
            name = entry.name or '',
            type = 'notmuch',
          }
        end
      end
      assert.equals(2, #results)
      assert.equals('alice@example.com', results[1].email)
      assert.equals('Alice', results[1].name)
      assert.equals('bob@test.com', results[2].email)
    end)
  end)

  describe('query_async', function()
    local original_vim_system

    before_each(function()
      original_vim_system = vim.system
      -- Reset config to known state
      contacts.config.notmuch = false
      contacts.config.from_map = {}
      contacts.config.cmd = 'khard'
      contacts.config.args = { 'email', '-p', '--remove-first-line' }
      -- Ensure no buffer-local account override
      vim.b.nvim_mail_account = nil
    end)

    after_each(function()
      vim.system = original_vim_system
      contacts.config.notmuch = true
    end)

    it('returns empty list for empty query', function()
      local got = nil
      contacts.query_async('', function(results) got = results end)
      assert.same({}, got)
    end)

    it('calls khard async and returns parsed results', function()
      local captured_cmd = nil
      vim.system = function(cmd, opts, cb)
        captured_cmd = cmd
        -- simulate async: call cb synchronously in test
        cb({ code = 0, stdout = 'alice@example.com\tAlice\tWork\n' })
      end

      local got = nil
      contacts.query_async('alice', function(results) got = results end)

      assert.equals('khard', captured_cmd[1])
      assert.equals('alice', captured_cmd[#captured_cmd])
      assert.equals(1, #got)
      assert.equals('alice@example.com', got[1].email)
      assert.equals('Alice', got[1].name)
    end)

    it('returns empty list when khard exits non-zero', function()
      vim.system = function(cmd, opts, cb)
        cb({ code = 1, stdout = '' })
      end

      local got = nil
      contacts.query_async('fail', function(results) got = results end)
      assert.same({}, got)
    end)

    it('merges khard and notmuch results, deduplicating by email', function()
      contacts.config.notmuch = true

      local call_count = 0
      vim.system = function(cmd, opts, cb)
        call_count = call_count + 1
        if cmd[1] == 'khard' then
          cb({ code = 0, stdout = 'alice@example.com\tAlice\tWork\nbob@test.com\tBob\t\n' })
        else
          -- notmuch returns alice (duplicate) + carol
          cb({
            code = 0,
            stdout = '[{"name":"Alice","address":"alice@example.com"},{"name":"Carol","address":"carol@test.com"}]',
          })
        end
      end

      local got = nil
      contacts.query_async('al', function(results) got = results end)

      assert.equals(2, call_count)   -- both processes launched
      assert.equals(3, #got)         -- alice, bob, carol (alice not duplicated)

      local emails = {}
      for _, r in ipairs(got) do emails[#emails + 1] = r.email end
      assert.same({ 'alice@example.com', 'bob@test.com', 'carol@test.com' }, emails)
    end)

    it('handles notmuch failure gracefully', function()
      contacts.config.notmuch = true

      vim.system = function(cmd, opts, cb)
        if cmd[1] == 'khard' then
          cb({ code = 0, stdout = 'alice@example.com\tAlice\tWork\n' })
        else
          cb({ code = 1, stdout = '' })
        end
      end

      local got = nil
      contacts.query_async('al', function(results) got = results end)

      assert.equals(1, #got)
      assert.equals('alice@example.com', got[1].email)
    end)

    it('uses account-specific khard args when account detected', function()
      contacts.config.accounts = {
        work = {
          cmd = 'khard',
          args = { 'email', '-p', '--remove-first-line', '-A', 'work' },
        },
      }
      contacts.config.from_map = { ['work%.com'] = 'work' }

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: John <john@work.com>',
        '',
      })
      vim.api.nvim_set_current_buf(buf)

      local captured_cmd = nil
      vim.system = function(cmd, opts, cb)
        captured_cmd = cmd
        cb({ code = 0, stdout = '' })
      end

      local got = nil
      contacts.query_async('john', function(results) got = results end)

      assert.truthy(vim.tbl_contains(captured_cmd, '-A'))
      assert.truthy(vim.tbl_contains(captured_cmd, 'work'))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('get_completions', function()
    local original_vim_system

    before_each(function()
      original_vim_system = vim.system
      contacts.config.notmuch = false
      contacts.config.from_map = {}
      contacts.config.cmd = 'khard'
      contacts.config.args = { 'email', '-p', '--remove-first-line' }
      vim.b.nvim_mail_account = nil
    end)

    after_each(function()
      vim.system = original_vim_system
      contacts.config.notmuch = true
    end)

    it('calls callback with empty items for non-header line', function()
      local source = contacts.new()
      local got = nil
      source:get_completions({ line = 'Subject: hello' }, function(r) got = r end)
      assert.same({ items = {}, is_incomplete_forward = false }, got)
    end)

    it('calls callback with is_incomplete_forward=true for short query', function()
      local source = contacts.new()
      local got = nil
      source:get_completions({ line = 'To: a' }, function(r) got = r end)
      assert.same({ items = {}, is_incomplete_forward = true }, got)
    end)

    it('returns formatted completion items from async results', function()
      vim.system = function(cmd, opts, cb)
        cb({ code = 0, stdout = 'alice@example.com\tAlice\tWork\n' })
      end

      local source = contacts.new()
      local got = nil
      source:get_completions({ line = 'To: alice' }, function(r) got = r end)

      -- vim.schedule fires synchronously in headless test env after callback
      vim.wait(100, function() return got ~= nil end)

      assert.equals(1, #got.items)
      assert.equals('Alice <alice@example.com>', got.items[1].label)
      assert.equals('Alice <alice@example.com>', got.items[1].insertText)
      assert.equals('Work', got.items[1].detail)
      assert.equals(12, got.items[1].kind)
      assert.is_false(got.is_incomplete_forward)
    end)
  end)
end)
