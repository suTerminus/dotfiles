-- Just an example, supposed to be placed in /lua/custom/

local M = {}

-- make sure you maintain the structure of `core/default_config.lua` here,
-- example of changing theme:

M.ui = {
   theme = "nord",
}

map("C-j", ":silent +g/\m^\s*$/d<CR>", ":noh<CR>")
map("C-k", ":silent -g/\m^\s*$/d<CR>", ":noh<CR>")

return M