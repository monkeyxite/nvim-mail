local attachment = require('nvim-mail.attachment')

describe('mail.attachment', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function read_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    return lines
  end

  describe('parse_mail', function()
    it('splits headers from body', function()
      local lines = read_fixture('draft_no_attach.txt')
      local headers, body, body_start = attachment.parse_mail(lines)
      assert.is_true(#headers > 0)
      assert.is_true(#body > 0)
      assert.equals('From: John Doe <john@example.com>', headers[1])
      assert.is_true(body_start > 1)
    end)
  end)

  describe('has_attach_mention', function()
    it('detects "attached" in body', function()
      local lines = read_fixture('draft_with_attach_mention.txt')
      local _, body = attachment.parse_mail(lines)
      assert.is_true(attachment.has_attach_mention(body))
    end)

    it('returns false when no mention', function()
      local lines = read_fixture('draft_no_attach.txt')
      local _, body = attachment.parse_mail(lines)
      assert.is_false(attachment.has_attach_mention(body))
    end)
  end)

  describe('has_attachment', function()
    it('detects <#part marker', function()
      local lines = read_fixture('draft_with_attachment.txt')
      local _, body = attachment.parse_mail(lines)
      assert.is_true(attachment.has_attachment(body))
    end)

    it('detects markdown image', function()
      local lines = read_fixture('draft_with_image_attach.txt')
      local _, body = attachment.parse_mail(lines)
      assert.is_true(attachment.has_attachment(body))
    end)

    it('returns false when no attachment', function()
      local lines = read_fixture('draft_with_attach_mention.txt')
      local _, body = attachment.parse_mail(lines)
      assert.is_false(attachment.has_attachment(body))
    end)
  end)

  describe('check', function()
    it('returns true when mention but no attachment', function()
      local lines = read_fixture('draft_with_attach_mention.txt')
      local missing, match = attachment.check(lines)
      assert.is_true(missing)
      assert.is_truthy(match)
    end)

    it('returns false when mention AND attachment present', function()
      local lines = read_fixture('draft_with_attachment.txt')
      local missing = attachment.check(lines)
      assert.is_false(missing)
    end)

    it('returns false when no mention at all', function()
      local lines = read_fixture('draft_no_attach.txt')
      local missing = attachment.check(lines)
      assert.is_false(missing)
    end)

    it('returns false when image attachment satisfies mention', function()
      local lines = read_fixture('draft_with_image_attach.txt')
      local missing = attachment.check(lines)
      assert.is_false(missing)
    end)
  end)
end)
