local ts = require('inkmd.ts')

local M = {}

--- Nesting depth of a list marker: 1 for top-level lists.
local function depth(node)
  local d = 0
  local parent = node:parent()
  while parent do
    if parent:type() == 'list' then
      d = d + 1
    end
    parent = parent:parent()
  end
  return math.max(d, 1)
end

--- Span of the paragraph that follows the marker, so the marker goes raw with its text.
local function item_span(marker)
  local sibling = marker:next_named_sibling()
  while sibling do
    if sibling:type() == 'paragraph' or ts.leaf_blocks[sibling:type()] then
      return ts.row_span(sibling)
    end
    sibling = sibling:next_named_sibling()
  end
  local row = marker:range()
  return row, row + 1
end

---@param ctx inkmd.Ctx
---@param node TSNode list_marker_minus | list_marker_plus | list_marker_star
---@param cfg inkmd.Config
function M.bullet(ctx, node, cfg)
  ctx:block(item_span(node))
  local row, col = node:range()
  local task = node:next_named_sibling()
  if task and task:type():match('^task_list_marker_') then
    local checked = task:type() == 'task_list_marker_checked'
    local _, _, _, task_end = task:range()
    -- Hide "- [ ]" and show one checkbox icon.
    ctx:conceal(row, col, task_end)
    local icon = checked and cfg.checkbox.checked or cfg.checkbox.unchecked
    ctx:inline(row, col, { { icon, checked and 'InkmdChecked' or 'InkmdUnchecked' } })
    return
  end
  local bullets = cfg.list.bullets
  -- The marker node includes the space after it; only the character itself is replaced.
  ctx:conceal(row, col, col + 1)
  ctx:inline(row, col, { { bullets[(depth(node) - 1) % #bullets + 1], 'InkmdBullet' } })
end

---@param ctx inkmd.Ctx
---@param node TSNode list_marker_dot | list_marker_parenthesis
function M.ordered(ctx, node)
  ctx:block(item_span(node))
  local row, col, _, end_col = node:range()
  ctx:hl(row, col, end_col, 'InkmdBullet')
end

return M
