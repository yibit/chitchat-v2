-- cnbook/lua/xref.lua
-- bookdown 语法的交叉引用（\@ref），PDF 与 HTML/EPUB 双端。
--
-- 支持的标签写法（bookdown 语法）：
--   章节：# 标题 {#sec:foo}        → \@ref(sec:foo)
--   图：  ![标题 (#fig:foo)](…)    → \@ref(fig:foo)
--   表：  表格标题里写 (#tab:foo)   → \@ref(tab:foo)
--   公式：display math 后写 (#eq:foo) → \@ref(eq:foo)
--
-- 编号规则（与 bookdown 实测输出一致：\@ref 渲染为裸编号文字）：
--   一级标题（章）按 \mainmatter 之后、非 unnumbered、非 (PART) 的顺序
--   编为“第 N 回”（前后缀可用 -M chapter-prefix=…/-M chapter-suffix=…
--   覆盖，缺省“第”“回”；\appendix 之后编为“附录 A/B…”）；
--   \mainmatter 之前或未编号章里的 h1/h2 引用回退为显示标题文字。
--   二级标题、图、表、公式的引用文字都是裸编号“N.M”（bookdown 的
--   HTML 端实测行为；想要“图 1.1”式前缀可用 -M fig-prefix=图 等打开）。
--   未编号章里的图/表/公式章号用 0（0.1），序号随章重置。
--   章节标签支持任意标识符（{#sec:foo} 或裸的 {#beijing} 都行）；
--   (PART) 部首不占章号。
--
-- 输出：
--   HTML/EPUB：\@ref(fig:foo) → <a href="#fig-foo">图 1.2</a>；
--   图/表/公式标签从标题文字里摘除，包裹元素加 id（标签里的冒号变形为
--   连字符，fig:foo → fig-foo；章节直接用 pandoc 生成的标题 id，
--   即 #sec:foo 原样）。
--   LaTeX：与 bookdown 一致，直接替换为编号文字（“图 1.2”/“第 3 回”），
--   不用 \ref——滤镜自编号，无需 \label。
--   无法解析的 \@ref：stderr 警告，原文保留。
--
-- 兼容性：只使用 pandoc 2.12 已有的 Lua API（walk_block/walk_inline、
-- 基础构造器），不依赖 pandoc 3 的函数。文档里没有 \@ref( 也没有
-- 图/表/公式标签时零开销直接返回（对 bookdown 管线是 no-op：bookdown
-- 在 pandoc 之前已把 \@ref 替换掉）。

-- --- 工具 -----------------------------------------------------------------

-- 判定当前输出是否 HTML 系（html5/html/epub 走链接输出）
local function is_html()
  return FORMAT:match('^html') ~= nil or FORMAT:match('^epub') ~= nil
end

-- 把带空格的编号文字拆成 Str/Space 序列（Str 内不应含空格）。
-- 注意：pandoc 2.12 的 Lua 字符串库是 UTF-8 改造版，gmatch('%S+')
-- 会把多字节汉字从中间切断（“1章”被拆成 "1"+半个"章"），
-- 这里只用 plain find 按 ASCII 空格切分，纯字节操作
local function text_inlines(s)
  local out = {}
  local pos = 1
  while true do
    local i = s:find(' ', pos, true)
    local part = i and s:sub(pos, i - 1) or s:sub(pos)
    if #part > 0 then
      if #out > 0 then table.insert(out, pandoc.Space()) end
      table.insert(out, pandoc.Str(part))
    end
    if not i then break end
    pos = i + 1
  end
  return out
end

-- 去掉首尾 ASCII 空白（pandoc 会把 YAML 元数据值解析成行内序列，
-- 首尾空格被吃掉；编号的前后空格在拼接时统一规整）
-- 纯字节操作：pandoc 2.12 的 UTF-8 改造版 match('^%s*(.-)%s*$')
-- 会把句尾多字节汉字截断（"章" 只剩前两字节），这里用逐字节扫描
local function trim(s)
  local i, j = 1, #s
  while i <= j and (s:byte(i) == 32 or s:byte(i) == 9) do i = i + 1 end
  while j >= i and (s:byte(j) == 32 or s:byte(j) == 9) do j = j - 1 end
  return s:sub(i, j)
end

-- 标签锚点 id 变形：fig:foo → fig-foo（冒号在 HTML id 里合法，但
-- 统一变形后与章节 id 风格一致，也避开 CSS 选择器的转义问题）
local function anchor_of(label)
  -- 注意 gsub 会返回“替换次数”作为第二返回值，必须括号截断，
  -- 否则透传给 pandoc.Attr 会被当成 classes 参数
  return (label:gsub(':', '-'))
end

-- --- 状态 -----------------------------------------------------------------

-- 标签表：label → { kind = 'sec'|'fig'|'tab'|'eq', text = 编号文字,
--                   anchor = HTML 锚点 id }
local labels = {}

-- 计数器：chapter_no 已编号的章数；sec_no/fig_no/tab_no/eq_no 随章重置；
-- cur_chap 当前章号（0 表示未编号章或章前内容，图/表章号用 0）
local chapter_no = 0
local sec_no, fig_no, tab_no, eq_no = 0, 0, 0, 0
local cur_chap = '0'        -- 当前章号字符串（附录期为大写字母）
local in_main = false       -- 是否已进入 \mainmatter（书里没有时视为 true）
local has_mainmatter = false
local in_appendix = false
local appendix_no = 0

local chapter_prefix, chapter_suffix = '第 ', ' 回'
local fig_prefix, tab_prefix = '', '' -- 缺省裸编号（bookdown 实测行为）

-- 图/表/公式的编号文字：前缀（可空）+ 章号.序号
local function number_text(prefix, n)
  if prefix == '' then
    return string.format('%s.%d', cur_chap, n)
  end
  return string.format('%s %s.%d', prefix, cur_chap, n)
end

-- --- 标签摘除 -------------------------------------------------------------

-- 从行内序列里摘除标签记号 (#fig:foo)：标签可在标题**末尾或开头**
-- （hong 的图标签在末尾，zhong 的表标签 `Table: (#tab:x) 标题` 在开头），
-- 返回摘除后的行内序列与标签名
local function strip_label(inlines, kind)
  local pat = '^%(#(' .. kind .. ':[%w%._%-]+)%)$'
  -- 末尾
  for i = #inlines, 1, -1 do
    local el = inlines[i]
    if el.t == 'Str' then
      local label = el.text:match(pat)
      if label then
        table.remove(inlines, i)
        if i > 1 and inlines[i - 1].t == 'Space' then
          table.remove(inlines, i - 1)
        end
        return inlines, label
      end
      break
    elseif el.t ~= 'Space' then
      break
    end
  end
  -- 开头
  for i = 1, #inlines do
    local el = inlines[i]
    if el.t == 'Str' then
      local label = el.text:match(pat)
      if label then
        table.remove(inlines, i)
        if inlines[i] and inlines[i].t == 'Space' then
          table.remove(inlines, i)
        end
        return inlines, label
      end
      break
    elseif el.t ~= 'Space' then
      break
    end
  end
  return inlines, nil
end

-- --- 第一遍：收集标签 + 摘除记号 + 包锚点 ---------------------------------

-- RawBlock：\mainmatter / \appendix 边界（raw LaTeX 块）
local function collect_RawBlock(el)
  if el.format ~= 'tex' and el.format ~= 'latex' then return nil end
  local t = el.text:gsub('%s+', '')
  if t == '\\mainmatter' then in_main = true end
  if t == '\\appendix' then
    in_appendix = true
    appendix_no = 0
  end
  return nil
end

-- Header：章节标签（{#sec:foo} 或裸标识符 {#beijing} 都登记）。
-- 编号规则：\mainmatter 之后、非 unnumbered、非 (PART) 的 h1 顺序编号；
-- \appendix 之后编为“附录 A/B…”；其余引用回退为标题文字
local function collect_Header(el)
  -- (PART) 部首不占章号
  local title = pandoc.utils.stringify(el.content)
  if title:match('^%(PART%)') then return nil end

  local unnumbered = not in_main
  for _, c in ipairs(el.classes) do
    if c == 'unnumbered' then unnumbered = true end
  end

  if el.level == 1 then
    sec_no, fig_no, tab_no, eq_no = 0, 0, 0, 0
    if unnumbered then
      cur_chap = '0'
    elseif in_appendix then
      appendix_no = appendix_no + 1
      cur_chap = string.char(string.byte('A') + appendix_no - 1)
    else
      chapter_no = chapter_no + 1
      cur_chap = tostring(chapter_no)
    end
    if el.identifier ~= '' then
      local text
      if unnumbered then
        text = title
      elseif in_appendix then
        text = '附录 ' .. cur_chap
      else
        text = trim(chapter_prefix) .. ' ' .. chapter_no .. ' ' .. trim(chapter_suffix)
      end
      labels[el.identifier] = { kind = 'sec', text = text, anchor = el.identifier }
    end
  elseif el.level == 2 then
    sec_no = sec_no + 1
    if el.identifier ~= '' then
      local text
      if unnumbered then
        text = title
      else
        -- h2 引用为裸编号（bookdown 实测行为），作者行文自带“一节”等后缀
        text = string.format('%s.%d', cur_chap, sec_no)
      end
      labels[el.identifier] = { kind = 'sec', text = text, anchor = el.identifier }
    end
  end
  return nil
end

-- Para/Plain：整段只有一个图片时视为图（implicit_figures），
-- 图片标题尾巴上的 (#fig:foo) 摘除、编号、包锚点 Div
local function collect_Para(el)
  if #el.content ~= 1 or el.content[1].t ~= 'Image' then return nil end
  local img = el.content[1]
  local caption, label = strip_label(img.caption, 'fig')
  if not label then return nil end
  fig_no = fig_no + 1
  labels[label] = {
    kind = 'fig', text = number_text(fig_prefix, fig_no),
    anchor = anchor_of(label),
  }
  img.caption = caption
  local para = (el.t == 'Plain') and pandoc.Plain({img}) or pandoc.Para({img})
  -- 包一层带 id 的 Div 作 HTML 锚点（LaTeX 端 Div 透传无副作用）
  return pandoc.Div({para}, pandoc.Attr(anchor_of(label)))
end

-- Table：表格标题里的 (#tab:foo)；pandoc 2.12 新表格模型，
-- caption.long 是块列表
local function collect_Table(el)
  local long = el.caption and el.caption.long
  if not long then return nil end
  for _, blk in ipairs(long) do
    local content = blk.content
    if content then
      local stripped, label = strip_label(content, 'tab')
      if label then
        tab_no = tab_no + 1
        labels[label] = {
          kind = 'tab', text = number_text(tab_prefix, tab_no),
          anchor = anchor_of(label),
        }
        blk.content = stripped
        return pandoc.Div({el}, pandoc.Attr(anchor_of(label)))
      end
    end
  end
  return nil
end

-- 公式：display math 后紧跟 (#eq:foo)（同一段落内）
local function collect_Para_eq(el)
  -- 找 DisplayMath + 标签的组合（标签 Str 前有 Space）
  for i = 1, #el.content - 1 do
    if el.content[i].t == 'Math' and el.content[i].mathtype == 'DisplayMath' then
      for j = i + 1, #el.content do
        local t = el.content[j]
        if t.t == 'Str' then
          local label = t.text:match('^%(#(eq:[%w%._%-]+)%)$')
          if label then
            eq_no = eq_no + 1
            labels[label] = {
              kind = 'eq',
              text = string.format('%d.%d', cur_chap, eq_no),
              anchor = anchor_of(label),
            }
            table.remove(el.content, j)
            if el.content[j - 1] and el.content[j - 1].t == 'Space' then
              table.remove(el.content, j - 1)
            end
            return pandoc.Div({el}, pandoc.Attr(anchor_of(label)))
          end
          break -- math 后的第一个 Str 不是标签就放弃
        end
      end
    end
  end
  return nil
end

-- --- 第二遍：替换 \@ref ----------------------------------------------------

-- 把一个 Str 里的所有 \@ref(xxx) 替换为链接（HTML）或编号文字（LaTeX），
-- 返回行内列表；无法解析的引用告警并原样保留
local function replace_refs(str)
  local text = str.text
  if not text:find('@ref%(') then return nil end
  local out = {}
  local pos = 1
  while true do
    local s, e, label = text:find('@ref%(([%w:_.%-]+)%)', pos)
    if not s then break end
    if s > pos then
      for _, inl in ipairs(text_inlines(text:sub(pos, s - 1))) do
        table.insert(out, inl)
      end
    end
    local info = labels[label]
    if not info then
      io.stderr:write('xref.lua: 警告：无法解析的引用 \\@ref(' ..
        label .. ')，原样保留\n')
      table.insert(out, pandoc.Str(text:sub(s, e)))
    elseif is_html() then
      local link = pandoc.Link(text_inlines(info.text), '#' .. info.anchor)
      table.insert(out, link)
    else
      for _, inl in ipairs(text_inlines(info.text)) do
        table.insert(out, inl)
      end
    end
    pos = e + 1
  end
  if pos <= #text then
    for _, inl in ipairs(text_inlines(text:sub(pos))) do
      table.insert(out, inl)
    end
  end
  return out
end

-- --- 入口 -----------------------------------------------------------------

function Pandoc(doc)
  -- 快速探测：全文没有 \@ref( 且没有图/表/公式标签记号时零开销返回
  -- （章节 {#sec:x} 属性本身无害，不需要摘除）
  local plain = pandoc.utils.stringify(doc)
  local has_ref = plain:find('@ref%(') ~= nil
  local has_label = plain:find('%(#fig:') ~= nil or
    plain:find('%(#tab:') ~= nil or plain:find('%(#eq:') ~= nil
  if not has_ref and not has_label then
    -- 仍可能有 {#sec:x} 标签配 \@ref 之外……没有 \@ref 就无可替换，
    -- 章节 id 留着无副作用，直接返回
    return nil
  end

  -- 章节编号单位与图/表前缀可用 metadata 覆盖
  if doc.meta['chapter-prefix'] then
    chapter_prefix = pandoc.utils.stringify(doc.meta['chapter-prefix'])
  end
  if doc.meta['chapter-suffix'] then
    chapter_suffix = pandoc.utils.stringify(doc.meta['chapter-suffix'])
  end
  if doc.meta['fig-prefix'] then
    fig_prefix = pandoc.utils.stringify(doc.meta['fig-prefix'])
  end
  if doc.meta['tab-prefix'] then
    tab_prefix = pandoc.utils.stringify(doc.meta['tab-prefix'])
  end

  -- 预扫描：书里有没有 \mainmatter（没有则全部按正文编号）
  pandoc.walk_block(pandoc.Div(doc.blocks), { RawBlock = function(el)
    if (el.format == 'tex' or el.format == 'latex')
        and el.text:gsub('%s+', '') == '\\mainmatter' then
      has_mainmatter = true
    end
  end })
  in_main = not has_mainmatter

  -- 第一遍：收集标签（顺带摘除记号、包锚点）。
  -- 注意 pandoc 2.12 的 walk_block 只作用于“子元素”（不含传入的根
  -- 节点本身），因此把整书块包进一个临时 Div 再遍历
  local pass1 = {
    Header = collect_Header,
    RawBlock = collect_RawBlock,
    Para = function(el)
      -- Para 先查图（整段一图），再查公式
      return collect_Para(el) or collect_Para_eq(el)
    end,
    Plain = collect_Para,
    Table = collect_Table,
  }
  local wrapped = pandoc.walk_block(pandoc.Div(doc.blocks), pass1)
  doc.blocks = wrapped.content

  -- 第二遍：替换 \@ref（支持前向引用，因为标签已收齐）
  if has_ref then
    wrapped = pandoc.walk_block(pandoc.Div(doc.blocks),
      { Str = replace_refs })
    doc.blocks = wrapped.content
  end
  return doc
end
