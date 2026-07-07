-- Tests for lua/nvim-mail/init.lua keymaps.
-- Currently covers the normal-mode ,mq (Quote) handler which used to crash
-- when the '< / '> marks were unset (returning 0 from vim.fn.line).

describe('mail.init', function()
  local function make_mail_buf(lines)
    -- Clear any prior visual marks that could bleed between tests.
    pcall(vim.cmd, "delmarks '<'>")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'mail'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    -- Force the plugin's per-buffer setup (registered on FileType=mail).
    vim.cmd('doautocmd FileType')
    return buf
  end

  -- Fetch the callback for a buffer-local keymap.
  local function get_keymap_callback(mode, lhs)
    local maps = vim.api.nvim_buf_get_keymap(0, mode)
    for _, m in ipairs(maps) do
      if m.lhs == lhs then return m.callback end
    end
    return nil
  end

  describe(',mq (Quote, normal mode)', function()
    it('does not crash when no visual selection has ever been made', function()
      local buf = make_mail_buf({
        'From: me@example.com',
        'To: alice@example.com',
        '',
        'This is line one of the body.',
        'This is line two.',
      })
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      local cb = get_keymap_callback('n', ',mq')
      assert.is_function(cb)
      -- The pre-fix code crashed here with E5108 ('start' > 'end') because
      -- vim.fn.line("'<") returns 0 (not nil) when the mark is unset.
      local ok, err = pcall(cb)
      assert.is_true(ok, 'quote handler crashed: ' .. tostring(err))

      local line4 = vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1]
      assert.equals('> This is line one of the body.', line4)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('prefixes the current line (not stale visual-selection lines)', function()
      local buf = make_mail_buf({
        'From: me@example.com',
        '',
        'body line 1',
        'body line 2',
        'body line 3',
      })
      -- Explicitly set stale '<'/> marks on lines 1..2 to simulate a prior
      -- visual selection that left marks behind. Signature of setpos:
      --   setpos({expr}, [bufnum, lnum, col, off])
      vim.fn.setpos("'<", { 0, 1, 1, 0 })
      vim.fn.setpos("'>", { 0, 2, 1, 0 })
      -- Cursor on line 4 in normal mode.
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      local cb = get_keymap_callback('n', ',mq')
      cb()

      -- Line 4 (current line) should be quoted; the mark-referenced lines
      -- 1 and 2 must be untouched.
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals('From: me@example.com', lines[1])
      assert.equals('', lines[2])
      assert.equals('body line 1', lines[3])
      assert.equals('> body line 2', lines[4])
      assert.equals('body line 3', lines[5])

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
