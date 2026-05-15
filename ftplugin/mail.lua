-- nvim-mail ftplugin loader
-- Called per-buffer. If setup was already called with opts (by lazy.nvim),
-- just apply buffer-local features. Otherwise call setup with defaults.
local M = require('nvim-mail')
if M._configured then
  M.setup(M.config)
else
  M.setup()
end
