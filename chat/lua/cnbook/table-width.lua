-- cnbook/lua/table-width.lua
-- 过宽表格自动分配列宽。
-- 管道表格（pipe table）写不出列宽，pandoc 的 LaTeX 输出对未指定列宽的
-- 表格一律用 l 列、长单元格不换行，内容会超出版心被裁掉。
-- 这里对未显式指定列宽、且估计总宽度超出版心的表格，按各列最长单元格
-- 的显示宽度比例分配相对列宽：LaTeX 端由此生成 p{} 列自动换行，
-- HTML/EPUB 端输出 <col style="width:…%">，同样更利于窄屏排版。
-- 估计总宽度未超阈值（窄表格）时不干预，保持原样。

-- 简易显示宽度估算：ASCII 计 1，CJK/全角等计 2
local function display_width(s)
  local w = 0
  local ok = pcall(function()
    for _, cp in utf8.codes(s) do
      w = w + (cp < 0x2E80 and 1 or 2)
    end
  end)
  if not ok then return #s end
  return w
end

function Table(el)
  -- 已有显式列宽的表格不干预。pandoc 2.12 的 Lua API 里，未指定列宽
  -- 时 colspec 只有对齐一个元素；指定后是第二个位置上的数字（比例）。
  for _, spec in ipairs(el.colspecs) do
    if type(spec[2]) == 'number' and spec[2] > 0 then return nil end
  end
  local ncol = #el.colspecs
  if ncol == 0 then return nil end
  local colmax = {}
  local colword = {}  -- 各列最长不可断行词（连续非 CJK 字符，如 "U+24AEB"）的显示宽度
  for i = 1, ncol do colmax[i] = 0; colword[i] = 0 end
  local function scan_rows(rows)
    -- 兼容不同 pandoc 版本的表格结构：Row 可能是命名字段也可能是
    -- 位置字段 {attr, cells}
    for _, row in ipairs(rows or {}) do
      for i, cell in ipairs(row.cells or row[2] or {}) do
        if i <= ncol then
          local s = pandoc.utils.stringify(cell.contents or cell[2])
          local w = display_width(s)
          if w > colmax[i] then colmax[i] = w end
          -- CJK 字符之间允许任意断行，只有连续的非 CJK 词（含带调
          -- 拼音，如 shuāng）不可断；p{} 列宽若小于该词宽度，词会
          -- 溢出到下一列
          local run = 0
          pcall(function()
            for _, cp in utf8.codes(s) do
              if cp >= 0x2E80 or cp == 0x20 then
                if run > colword[i] then colword[i] = run end
                run = 0
              else
                run = run + 1
              end
            end
          end)
          if run > colword[i] then colword[i] = run end
        end
      end
    end
  end
  scan_rows(el.head and (el.head.rows or el.head[2]))
  for _, body in ipairs(el.bodies or {}) do
    scan_rows(body.body)
  end
  scan_rows(el.foot and (el.foot.rows or el.foot[2]))
  local total = 0
  for i = 1, ncol do total = total + colmax[i] end
  -- 版心约可容纳 40 个全角字符，留出余量，超过 44 才判定为过宽
  if total <= 44 or total == 0 then return nil end
  -- 按比例分配；另给每列两个下限：最长不可断词的版心占比、8% 兜底，
  -- 最后重新归一化
  local widths = {}
  local sum = 0
  for i = 1, ncol do
    widths[i] = math.max(colmax[i] / total, colword[i] / 40, 0.08)
    sum = sum + widths[i]
  end
  for i = 1, ncol do
    el.colspecs[i] = { el.colspecs[i][1], widths[i] / sum }
  end
  return el
end
