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

--- The checkbox after a list marker: its state and its columns, or nil. The state is the
--- character between the brackets: ' ', 'x' or 'X', or a key of `checkbox.custom`.
---@param ctx inkmd.Ctx
---@param marker TSNode
---@param cfg inkmd.Config
---@return {state: string, row: integer, col: integer, end_col: integer, icon: string, hl: string, text_hl?: string, progress: 'done'|'todo'|false}?
local function checkbox(ctx, marker, cfg)
  -- The marker node includes the space after it.
  local row, _, _, col = marker:range()
  local c, after = ctx:line(row):sub(col + 1):match('^%[(.)%](.?)')
  if not c or not (after == '' or after:match('%s')) then
    return
  end
  local box = cfg.checkbox
  if c == ' ' then
    return { state = c, row = row, col = col, end_col = col + 3, icon = box.unchecked, hl = 'InkmdUnchecked', progress = 'todo' }
  elseif c == 'x' or c == 'X' then
    return { state = c, row = row, col = col, end_col = col + 3, icon = box.checked, hl = 'InkmdChecked', progress = 'done' }
  end
  local custom = box.custom[c]
  if custom then
    return {
      state = c,
      row = row,
      col = col,
      end_col = col + 3,
      icon = custom.icon,
      hl = custom.hl,
      text_hl = custom.text_hl,
      progress = custom.progress or false,
    }
  end
end

--- "done/total" of the tasks in the sub-lists of `item`, or nil when there are none.
---@param ctx inkmd.Ctx
---@param item TSNode list_item
---@param cfg inkmd.Config
local function progress(ctx, item, cfg)
  local done, total = 0, 0
  for list in item:iter_children() do
    if list:type() == 'list' then
      for sub in list:iter_children() do
        local marker = sub:type() == 'list_item' and sub:named_child(0)
        local box = marker and marker:type():match('^list_marker_') and checkbox(ctx, marker, cfg)
        if box and box.progress then
          total = total + 1
          done = done + (box.progress == 'done' and 1 or 0)
        end
      end
    end
  end
  if total > 0 then
    return done, total
  end
end

--- Checkbox and progress of the item that `marker` starts. Returns whether it had a
--- checkbox (which then replaces the bullet).
---@param ctx inkmd.Ctx
---@param marker TSNode
---@param cfg inkmd.Config
---@param hide_col integer where hiding starts: the bullet for "- [ ]", the box for "1. [ ]"
local function item(ctx, marker, cfg, hide_col)
  local s, e = item_span(marker)
  local box = checkbox(ctx, marker, cfg)
  if box then
    ctx:conceal(box.row, hide_col, box.end_col)
    ctx:inline(box.row, hide_col, { { box.icon, box.hl } })
    if box.text_hl then
      for row = s, e - 1 do
        local from = row == box.row and box.end_col or #ctx:line(row):match('^%s*')
        ctx:hl(row, from, #ctx:line(row), box.text_hl)
      end
    end
  end
  local parent = marker:parent()
  if cfg.checkbox.progress and parent and parent:type() == 'list_item' then
    local done, total = progress(ctx, parent, cfg)
    if done then
      -- On the item's last text row, kept while the item is raw (it is being edited).
      ctx:add(e - 1, 0, {
        virt_text = { { done .. '/' .. total, done == total and 'InkmdChecked' or 'InkmdProgress' } },
        virt_text_pos = 'eol',
      }, true)
    end
  end
  return box ~= nil
end

---@param ctx inkmd.Ctx
---@param node TSNode list_marker_minus | list_marker_plus | list_marker_star
---@param cfg inkmd.Config
function M.bullet(ctx, node, cfg)
  ctx:block(item_span(node))
  local row, col = node:range()
  -- "- [ ]": one checkbox icon replaces the bullet and the box.
  if item(ctx, node, cfg, col) then
    return
  end
  local bullets = cfg.list.bullets
  -- The marker node includes the space after it; only the character itself is replaced.
  ctx:conceal(row, col, col + 1)
  ctx:inline(row, col, { { bullets[(depth(node) - 1) % #bullets + 1], 'InkmdBullet' } })
end

---@param ctx inkmd.Ctx
---@param node TSNode list_marker_dot | list_marker_parenthesis
---@param cfg inkmd.Config
function M.ordered(ctx, node, cfg)
  ctx:block(item_span(node))
  local row, col, _, end_col = node:range()
  ctx:hl(row, col, end_col, 'InkmdBullet')
  -- "1. [ ]": the number stays, the box becomes an icon.
  item(ctx, node, cfg, end_col)
end

return M
