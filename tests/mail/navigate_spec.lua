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
      local buf = load_fixture('draft_with_quotes.txt')
      nav.goto_reply()
      local pos = vim.api.nvim_win_get_cursor(0)
      local line = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false)[1]
      assert.is_truthy(line:match('^>'))
      -- Assert exact first-quote line (fixture: draft_with_quotes.txt line 8 is `> On Mon, ...`)
      assert.are.equal(8, pos[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('does not move cursor when there are no quoted lines', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: a@b.com',
        'To: c@d.com',
        'Subject: Hello',
        '',
        'Just a plain body line.',
        'No quotes here.',
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      nav.goto_reply()
      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(5, pos[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('switch_spell', function()
    local langs = { 'en', 'sv' }

    after_each(function()
      vim.opt_local.spell = false
      vim.opt_local.spelllang = 'en'
    end)

    it('cycles: lang1 -> lang2 -> off -> lang1', function()
      -- Starting state: spell on at lang1
      vim.opt_local.spell = true
      vim.opt_local.spelllang = langs[1]

      -- lang1 -> lang2
      nav.switch_spell(langs)
      assert.is_true(vim.opt_local.spell:get())
      assert.are.equal(langs[2], table.concat(vim.opt_local.spelllang:get(), ','))

      -- lang2 -> off
      nav.switch_spell(langs)
      assert.is_false(vim.opt_local.spell:get())

      -- off -> lang1
      nav.switch_spell(langs)
      assert.is_true(vim.opt_local.spell:get())
      assert.are.equal(langs[1], table.concat(vim.opt_local.spelllang:get(), ','))
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

    it('removes ALL quoted signature blocks in a long thread', function()
      -- This test fails against the old code (which only removed the last block)
      -- and passes with the new collect_quoted_sig_ranges-based implementation.
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'From: me@example.com',
        'To: you@example.com',
        '',
        'My latest reply',
        '',
        '> On Tue, Alice wrote:',
        '> > On Mon, Bob wrote:',
        '> > -- ',
        '> > Bob Smith',
        '> > Bob Corp',
        '',
        '> Alice reply',
        '> -- ',
        '> Alice Johnson',
        '> Alice Corp',
      })
      vim.api.nvim_set_current_buf(buf)
      nav.kill_quoted_sig()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local text = table.concat(lines, '\n')
      -- Both sig blocks must be gone
      assert.is_falsy(text:find('Bob Smith'),    'Bob Smith should be removed')
      assert.is_falsy(text:find('Bob Corp'),     'Bob Corp should be removed')
      assert.is_falsy(text:find('Alice Johnson'), 'Alice Johnson should be removed')
      assert.is_falsy(text:find('Alice Corp'),   'Alice Corp should be removed')
      -- Non-sig quoted content must survive
      assert.is_truthy(text:find('My latest reply'), 'own reply must survive')
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('collect_quoted_sig_ranges returns correct ranges (pure, no buffer)', function()
      -- Blank line on line 6 separates the two quoted-sig blocks so ranges
      -- don't bleed into each other.
      local lines = {
        'My reply',           -- 1
        '> On Tue, Alice:',   -- 2
        '> > -- ',            -- 3  range1.start
        '> > Bob Smith',      -- 4
        '> > Bob Corp',       -- 5  range1.stop
        '',                   -- 6  non-'>' stops range1
        '> -- ',              -- 7  range2.start
        '> Alice Johnson',    -- 8  range2.stop
      }
      local ranges = nav.collect_quoted_sig_ranges(lines)
      assert.equals(2, #ranges)
      -- First block: line 3 through line 5
      assert.equals(3, ranges[1].start)
      assert.equals(5, ranges[1].stop)
      -- Second block: line 7 through line 8
      assert.equals(7, ranges[2].start)
      assert.equals(8, ranges[2].stop)
    end)
  end)
end)
