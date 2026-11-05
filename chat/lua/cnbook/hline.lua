-- cnbook/lua/hline.lua
-- 文字排版属性滤镜，两种形态：
--
-- 1) 块级 .hline —— 带排版属性的独立行（落款、写作日期、题记等）。
--    一个段落里只写一个带 .hline 类的 bracketed span 时，整行按属性渲染：
--
--      [卢麒元 2024年12月26日]{.hline align=right color=#888888}
--      [2001-12-25]{.hline align=right bold=true}
--
--    属性：
--      align  left | center | right（左顶格 / 居中 / 右顶末字；默认 center）
--      color  #RRGGBB 或常用颜色名（xcolor/CSS 交集，如 gray、Maroon、red）；
--             缺省不着色，继承正文颜色
--      bold   true 加粗（缺省不加粗）
--
-- 2) 行内 .c —— 原地着色/加粗（正文里夹杂的古文原文等），不改版式位置：
--
--      孟子说[“利者，义之和也”]{.c color=Maroon}，这就是中庸。
--      [天命之谓性]{.c color=Maroon bold=true}
--
--    属性：color 同上；bold=true 加粗（也可直接在 span 内写 __加粗__，
--    两者等效）。color 与 bold 至少给一个，否则告警并原样保留。
--
-- span 内的行内格式（__加粗__ 等）照常生效，LaTeX 端转 \textbf，
-- HTML 端转 <strong>。
-- LaTeX 端用 flushleft/center/flushright + \textcolor（xcolor 由
-- base.tex 加载，无需配套 .tex 件）；HTML/EPUB 端输出
-- <div class="hline" style="text-align:...;color:..."> 或
-- <span class="c" style="color:...;font-weight:bold">。

local ALIGN_ENV = { left = 'flushleft', center = 'center', right = 'flushright' }

local function warn(msg)
  io.stderr:write('cnbook/hline.lua: 警告: ' .. msg .. '\n')
end

local function has_class(attr, name)
  for _, cls in ipairs(attr.classes) do
    if cls == name then return true end
  end
  return false
end

-- 校验并归一化 color 属性；非法时告警并返回 nil
local function check_color(color)
  if not color then return nil end
  if color:match('^#%x%x%x%x%x%x$') or color:match('^[%a]+$') then
    return color
  end
  warn('非法 color 取值 "' .. color .. '"，按不着色处理')
  return nil
end

-- bold 属性判真：存在且不是 false/0/no
local function truthy(v)
  return v ~= nil and v ~= 'false' and v ~= '0' and v ~= 'no'
end

-- LaTeX 特殊字符转义
local LATEX_ESC = {
  ['\\'] = '\\textbackslash{}', ['{'] = '\\{', ['}'] = '\\}',
  ['$'] = '\\$', ['&'] = '\\&', ['#'] = '\\#', ['%'] = '\\%',
  ['_'] = '\\_', ['^'] = '\\textasciicircum{}', ['~'] = '\\textasciitilde{}',
}
local function esc_latex(s)
  return (s:gsub('[\\{}$&#%%_^~]', LATEX_ESC))
end

-- 行内内容手工渲染为 LaTeX（pandoc 2.12 滤镜里没有 pandoc.write，
-- 独立行内容简单，递归处理常见行内元素即可）
local function inlines_to_latex(inlines)
  local parts = {}
  for _, inl in ipairs(inlines) do
    local t = inl.t
    if t == 'Str' then
      parts[#parts + 1] = esc_latex(inl.text)
    elseif t == 'Space' or t == 'SoftBreak' then
      parts[#parts + 1] = ' '
    elseif t == 'LineBreak' then
      parts[#parts + 1] = '\\newline '
    elseif t == 'Strong' then
      parts[#parts + 1] = '\\textbf{' .. inlines_to_latex(inl.content) .. '}'
    elseif t == 'Emph' then
      parts[#parts + 1] = '\\emph{' .. inlines_to_latex(inl.content) .. '}'
    elseif t == 'Code' then
      parts[#parts + 1] = '\\texttt{' .. esc_latex(inl.text) .. '}'
    elseif t == 'Quoted' then
      if inl.quotetype == 'DoubleQuote' then
        parts[#parts + 1] = '``' .. inlines_to_latex(inl.content) .. "''"
      else
        parts[#parts + 1] = '`' .. inlines_to_latex(inl.content) .. "'"
      end
    else
      parts[#parts + 1] = esc_latex(pandoc.utils.stringify(inl))
    end
  end
  return table.concat(parts)
end

-- color 属性 → \textcolor 的参数；hex 走 xcolor 的 HTML 色彩模型
local function latex_color_cmd(color)
  if color:match('^#%x%x%x%x%x%x$') then
    return '[HTML]{' .. color:sub(2) .. '}'
  end
  return '{' .. color .. '}'
end

function Para(el)
  -- 整段只有一个带 .hline 类的 span 才触发；混在普通句子里的 span 不动
  if #el.content ~= 1 or el.content[1].t ~= 'Span' then return nil end
  local span = el.content[1]
  if not has_class(span.attr, 'hline') then return nil end

  local align = span.attributes['align'] or 'center'
  if not ALIGN_ENV[align] then
    warn('非法 align 取值 "' .. align .. '"，按 center 处理')
    align = 'center'
  end
  local color = check_color(span.attributes['color'])
  local bold = truthy(span.attributes['bold'])

  if FORMAT == 'latex' then
    local inner = inlines_to_latex(span.content)
    if bold then inner = '\\textbf{' .. inner .. '}' end
    if color then
      inner = '\\textcolor' .. latex_color_cmd(color) .. '{' .. inner .. '}'
    end
    return pandoc.RawBlock('latex',
      '\\begin{' .. ALIGN_ENV[align] .. '}\n' .. inner ..
      '\n\\end{' .. ALIGN_ENV[align] .. '}')
  end

  -- HTML / EPUB：样式内联，EPUB 阅读器同样生效
  local style = 'text-align:' .. align
  if color then style = style .. ';color:' .. color end
  if bold then style = style .. ';font-weight:bold' end
  return pandoc.Div({ pandoc.Para(span.content) },
    pandoc.Attr('', { 'hline' }, { style = style }))
end

-- 行内 .c：原地着色/加粗，不改版式位置
function Span(el)
  if not has_class(el.attr, 'c') then return nil end
  local color = check_color(el.attributes['color'])
  local bold = truthy(el.attributes['bold'])
  if not color and not bold then
    warn('.c 未给出有效 color 或 bold，原样保留')
    return nil
  end

  if FORMAT == 'latex' then
    local inner = inlines_to_latex(el.content)
    if bold then inner = '\\textbf{' .. inner .. '}' end
    if color then
      inner = '\\textcolor' .. latex_color_cmd(color) .. '{' .. inner .. '}'
    end
    return pandoc.RawInline('latex', inner)
  end

  -- HTML / EPUB：样式内联
  local styles = {}
  if color then styles[#styles + 1] = 'color:' .. color end
  if bold then styles[#styles + 1] = 'font-weight:bold' end
  return pandoc.Span(el.content,
    pandoc.Attr('', { 'c' }, { style = table.concat(styles, ';') }))
end
