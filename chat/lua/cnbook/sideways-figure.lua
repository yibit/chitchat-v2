-- cnbook/lua/sideways-figure.lua
-- 整页横排大图：把带 {.sideways} 标记的独立图片段落，在 LaTeX 输出中
-- 替换为 rotating 宏包的 sidewaysfigure 环境 —— 图片独占一页并旋转 90°，
-- 版心高度方向拉满；宽度方向（图高 + 图题）不超过正文版心宽度
-- \pgsidetextwidth（该长度在配套的 latex/sideways-figure.tex 中定义，
-- 因为 sidewaysfigure 环境内部 \textwidth/\textheight 会被 rotating
-- 对调）。HTML / EPUB 输出不做任何处理，图片保持原样。
--
-- 用法（图片须独占一段）：
--   ![图题](images/xx.png){.sideways}
--
-- 配套：pdf_book 的 in_header 需引用 latex/cnbook/sideways-figure.tex。

local function has_sideways_class(attr)
  for _, cls in ipairs(attr.classes) do
    if cls == 'sideways' then return true end
  end
  return false
end

function Para(el)
  if FORMAT ~= 'latex' then return nil end
  -- 独占一段的图片（pandoc 2.x 的 implicit figure 形态）
  if #el.content ~= 1 or el.content[1].t ~= 'Image' then return nil end
  local img = el.content[1]
  if not has_sideways_class(img.attr) then return nil end
  local caption = pandoc.utils.stringify(img.caption)
  return pandoc.RawBlock('latex',
    '\\begin{sidewaysfigure}\n' ..
    '\\centering\n' ..
    '\\includegraphics[width=\\linewidth, height=0.90\\pgsidetextwidth, keepaspectratio]{' .. img.src .. '}\n' ..
    '\\caption{' .. caption .. '}\n' ..
    '\\end{sidewaysfigure}')
end
