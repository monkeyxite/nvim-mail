-- nvim-mail ftplugin entry point.
-- Neovim sources this file automatically for every buffer whose filetype is
-- 'mail'.  We rely on this Neovim convention instead of the self-registering
-- FileType autocmd that used to live in setup().
--
-- If the user already called setup() via their plugin manager (lazy.nvim etc.)
-- config is ready; otherwise initialise with defaults now.
local M = require('nvim-mail')
if not M._configured then
  M.setup()
end
M.attach_buffer()
