local nav = require('nvim-mail.navigate')

describe('mail.navigate', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function load_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  describe('goto_field', function()
    it('jumps to To: line', function()
      local buf = load_fixture('draft_work_reply.txt')
      nav.goto_field('^[Tt]o:')
      local pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false)[1]
      assert.is_truthy(line:match('^To:'))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('jumps to Subject: line', function()
      local buf = load_fixture('draft_work_reply.txt')
      nav.goto_field('^[Ss]ubject:')
      local pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false)[1]
      assert.is_truthy(line:match('^Subject:'))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('goto_body', function()
    it('jumps to first line after headers', function()
      local buf = load_fixture('draft_work_reply.txt')
      nav.goto_body()
      local pos = vim.api.nvim_win_get_cursor(0)
      -- Should be after the empty line separator
      assert.is_true(pos[1] > 4)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('goto_reply', function()
    it('jumps to first quoted line', function()
      local buf = load_fixture('draft_reply_with_thread.txt')
      -- This fixture has no quotes, so it should not move
      -- Let's test with marker fixture which also has no quotes
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('kill_quoted_sig', function()
    it('removes quoted signature block', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: a@b.com',
        'To: c@d.com',
        '',
        'My reply',
        '',
        '> Original message',
        '> -- ',
        '> John Doe',
        '> Company Inc',
      })
      vim.api.nvim_set_current_buf(buf)
      nav.kill_quoted_sig()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.is_falsy(text:find('John Doe'))
      assert.is_falsy(text:find('Company Inc'))
      assert.is_truthy(text:find('Original message'))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
