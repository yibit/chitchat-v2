-- cnbook/lua/index.lua
-- \index{词条} 支持（书籍索引），PDF 与 HTML/EPUB 双端。
--
-- markdown 源码里直接写 LaTeX 原语 \index{词条}，pandoc 解析为
-- RawInline (Format "tex")：
--   LaTeX 输出：原样透传 \index{词条}（由 mato 负责在检测到词条时
--     给 pandoc 追加 makeidx 头并在 xelatex 编译序列里插 makeindex）
--   HTML/EPUB 输出：替换为空锚点
--     <span class="mato-idx" data-term="词条" id="idx-词条-序号"></span>
--     正文显示文本不动；序号防同词多次出现冲突
--   支持 \index{主词!子词} 主子词条形式：data-term 存完整串
--     （“甲!乙”），分组/排序由消费端（mato 的索引页生成器）按
--     主词分组；id 里的 ! 变形为 -
--
-- 兼容性：只用 pandoc 2.12 已有的 Lua API。文档没有 \index{ 时
-- 零开销（RawInline 过滤器只在出现 raw inline 时才会被调用，且
-- 格式不匹配直接返回）。

-- 每个词条的出现序号（词条 → 已出现次数）
local counts = {}

-- 词条 → id 用串：! 变形为 -（主子词条），其余原样（HTML5 的 id
-- 允许中文等非 ASCII 字符）
local function id_of(term, n)
  local safe = term:gsub('!', '-')
  return string.format('idx-%s-%d', safe, n)
end

function RawInline(el)
  -- pandoc 2.12 把 \index{…} 解析为 Format "tex"；保守起见也认 "latex"
  if el.format ~= 'tex' and el.format ~= 'latex' then return nil end
  local term = el.text:match('^\\index{(.-)}$')
  if not term then return nil end
  -- LaTeX 输出：原样透传（makeidx 的 \index 命令）
  if FORMAT:match('latex') or FORMAT == 'beamer' then return nil end
  -- HTML/EPUB：空锚点 span，显示文本不动
  counts[term] = (counts[term] or 0) + 1
  return pandoc.Span({}, pandoc.Attr(
    id_of(term, counts[term]),
    { 'mato-idx' },
    { ['data-term'] = term }
  ))
end
