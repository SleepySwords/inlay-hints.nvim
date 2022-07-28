local ih = require("inlay-hints")

local M = {}

function M.new()
  M.namespace = vim.api.nvim_create_namespace("textDocument/inlayHints")
  local self = setmetatable({ cache = {}, enabled = false }, { __index = M })

  return self
end

local function clear_ns(bufnr)
  -- clear namespace which clears the virtual text as well
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
end

-- Disable hints and clear all cached buffers
function M.disable(self)
  self.disable = false
  M.disable_cache_autocmd()

  for k, _ in pairs(self.cache) do
    if vim.api.nvim_buf_is_valid(k) then
      clear_ns(k)
    end
  end
end

local function set_all(self)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    M.cache_render(self, bufnr)
  end
end

-- Enable auto hints and set hints for the current buffer
function M.enable(self)
  self.enabled = true
  M.enable_cache_autocmd()
  set_all(self)
end

-- Set inlay hints only for the current buffer
function M.set(self)
  M.cache_render(self, 0)
end

-- Clear hints only for the current buffer
function M.unset()
  clear_ns()
end

function M.enable_cache_autocmd()
  local opts = ih.config.options
  vim.cmd(string.format(
    [[
        augroup InlayHintsCache
        autocmd BufWritePost,BufReadPost,BufEnter,BufWinEnter,TabEnter * :lua require"inlay-hints".cache()
        %s
        augroup END
    ]],
    opts.only_current_line
        and "autocmd CursorMoved * :lua require'inlay-hints'.render()"
      or ""
  ))
end

function M.disable_cache_autocmd()
  vim.cmd(
    [[
    augroup InlayHintsCache
    autocmd!
    augroup END
  ]],
    false
  )
end

local function get_params(bufnr)
  local params = vim.lsp.util.make_given_range_params()
  params["range"]["start"]["line"] = 0
  params["range"]["end"]["line"] = vim.api.nvim_buf_line_count(bufnr) - 1

  return params
end

-- parses the result into a easily parsable format
-- example:
-- {
--  ["12"] = { {
--      kind = "TypeHint",
--      label = "String"
--    } },
--  ["13"] = { {
--      kind = "TypeHint",
--      label = "usize"
--    } },
-- }
--
local function parse_hints(result)
  local map = {}

  if type(result) ~= "table" then
    return {}
  end

  for _, value in pairs(result) do
    local range = value.position
    local line = value.position.line
    local label = value.label

    local label_str = ""

    if type(label) == "string" then
      label_str = value.label
    elseif type(label) == "table" then
      for _, label_part in ipairs(label) do
        label_str = label_str .. label_part.value
      end
    end

    local kind = value.kind

    if map[line] ~= nil then
      table.insert(map[line], { label = label_str, kind = kind, range = range })
    else
      map[line] = { { label = label_str, kind = kind, range = range } }
    end
  end

  return map
end

function M.cache_render(self, bufnr)
  local buffer = bufnr or vim.api.nvim_get_current_buf()

  for _, v in ipairs(vim.lsp.buf_get_clients(buffer)) do
    v.request(
      "textDocument/inlayHint",
      get_params(buffer),
      function(err, result, ctx)
        if err then
          return
        end

        self.cache[ctx.bufnr] = parse_hints(result)

        M.render(self, ctx.bufnr)
      end,
      buffer
    )
  end
end

function M.render(self, bufnr)
  local buffer = bufnr or vim.api.nvim_get_current_buf()

  local hints = self.cache[buffer]

  if hints == nil then
    return
  end

  ih.renderer.render(buffer, M.namespace, hints)
end

return M
