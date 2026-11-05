-- cnbook/lua/ruby.lua
-- 拼音注音（ruby/furigana 风格），PDF 与 HTML/EPUB 双端输出。
-- 用法：
--   [床前]{.ruby pinyin="chuáng qián"}[明月光]{.ruby pinyin="míng yuè guāng"}
-- LaTeX 端依赖 latex/ruby.tex 提供的 \ruby 宏；
-- HTML/EPUB 端输出 <ruby><rt> 标签，样式见 css/cnbook.css。

-- 简易 HTML 转义
local function escape_html(s)
  return s:gsub('&', '&amp;')
          :gsub('<', '&lt;')
          :gsub('>', '&gt;')
          :gsub('"', '&quot;')
end

-- 简易 LaTeX 转义（仅处理常见特殊字符）
local function escape_latex(s)
  return s:gsub('\\', '\\textbackslash{}')
          :gsub('{', '\\{')
          :gsub('}', '\\}')
          :gsub('#', '\\#')
          :gsub('%%', '\\%%')
          :gsub('&', '\\&')
          :gsub('%$', '\\$')
          :gsub('%^', '\\textasciicircum{}')
end

-- 将 .ruby span 转换为 PDF 的 ruby 宏或 HTML 的 ruby 标签。
-- 支持单字注音，也支持词组注音（拼音文本居中对齐于整组汉字上方）。
function Span(el)
  if el.classes:includes('ruby') then
    local pinyin = el.attributes['pinyin'] or el.attributes['p'] or ''
    local base = pandoc.utils.stringify(el.content)

    if FORMAT:match 'latex' then
      return pandoc.RawInline('latex',
        '\\ruby{' .. escape_latex(base) .. '}{' .. escape_latex(pinyin) .. '}')
    elseif FORMAT:match 'html' or FORMAT:match 'epub' then
      return pandoc.RawInline('html',
        '<ruby>' .. escape_html(base) .. '<rt>' .. escape_html(pinyin) .. '</rt></ruby>')
    end
  end
  return el
end
