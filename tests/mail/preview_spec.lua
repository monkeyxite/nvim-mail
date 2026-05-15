local preview = require('nvim-mail.preview')

describe('mail.preview', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function read_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    return lines
  end

  describe('extract_body', function()
    it('returns lines after empty line separator', function()
      local lines = read_fixture('draft_no_attach.txt')
      local body = preview.extract_body(lines)
      assert.is_true(#body > 0)
      assert.is_truthy(body[1]:find('Hi'))
    end)

    it('excludes headers', function()
      local lines = read_fixture('draft_no_attach.txt')
      local body = preview.extract_body(lines)
      for _, l in ipairs(body) do
        assert.is_falsy(l:match('^From:'))
        assert.is_falsy(l:match('^To:'))
        assert.is_falsy(l:match('^Subject:'))
      end
    end)

    it('excludes muttlook markers from body', function()
      local lines = read_fixture('draft_with_marker.txt')
      local body = preview.extract_body(lines)
      local text = table.concat(body, '\n')
      assert.is_falsy(text:find('muttlook%-reply%-to'))
    end)
  end)

  describe('build_cmd', function()
    it('builds pandoc command', function()
      local cmd = preview.build_cmd()
      assert.is_truthy(cmd:find('pandoc'))
      assert.is_truthy(cmd:find('html'))
    end)
  end)
end)
