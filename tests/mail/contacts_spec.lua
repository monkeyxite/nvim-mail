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
end)
