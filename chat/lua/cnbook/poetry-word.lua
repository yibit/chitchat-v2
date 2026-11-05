-- cnbook/lua/poetry-word.lua
-- 为中文古诗提供居中排版（poetry）、词（word）支持。
-- 用法：
--   ::: {.poetry title="静夜思" author="李白" date="唐代"}
--   床前明月光
--   疑是地上霜
--   :::
--
--   ::: {.word title="清平乐" author="李白" date="唐代"}
--   云想衣裳花想容，
--   春风拂槛露华浓。
--   :::
--
--   ::: {.riddle title="" author="" date=""}
--   身自端方，体自坚硬。
--   虽不能言，有言必应。
--   打一用物。
--   :::
-- riddle（灯谜等谜语）：谜面排版同 poetry（整体居中）；最后一行以
-- “打”字开头时视为谜目（可选，无谜目的谜语全部按谜面处理），
-- 单独以右对齐小一号字渲染（LaTeX 端 \riddlemimu，HTML 端
-- .riddle-mimu）。
--
-- LaTeX 端依赖 latex/poetry-word.tex 提供的 poetry/word 环境与
-- \poetrytitle 等宏；HTML/EPUB 端输出嵌套 Div，样式见 css/cnbook.css。
--
-- 作品级脚注标记（如 [^2-2-1]）可以直接跟在开 fence 的 } 后面：
--   ::: {.poetry title="贺新郎·别友" author="毛泽东" date="1923 年"}[^2-2-1]
--
--   挥手从兹去[^2-2-2]。
--   :::
-- 标记也可以紧跟在某个属性值后面，随该属性行渲染：
--   ::: {.poetry title="贺新郎·别友"[^2-2-1] author="毛泽东" date="1923 年"}
-- pandoc 本身不允许属性行内/后出现这些内容，会把整段解析成普通段落；
-- 本滤镜的 Pandoc 函数会把这些写法重新组装成真正的 Div 再渲染。
-- 也可以把标记单独一行写在 Div 开头，效果与 }[^x] 相同。
-- 注意：
-- * 标记不能写在引号内部（title="题[^x]"），pandoc 会把它当作普通
--   文字且对应的脚注定义会被丢弃。
--
-- 脚注内的诗体（note 属性）：诗块放在脚注里时，不必用 pandoc 多块
-- 脚注的缩进写法（空行 + 续行 4 空格缩进，脆弱且不便识别），把 Div
-- 写在顶层（建议紧跟在对应脚注定义之后），加 note="<脚注标签>" 属性：
--   [^064-2]: 出自王安石《明妃曲》。全篇内容，如下：
--
--   ::: {.poetry title="" author="" date="" note="064-2"}
--   明妃初出汉宫时，泪湿春风鬓脚垂。
--   :::
-- 本滤镜的 Pandoc 函数把这类 Div 移入对应脚注（按脚注定义首段文字
-- 匹配 Note；找不到时告警并留在原位按正文诗体渲染），并以较小的
-- 字号排版：LaTeX 端用 poetrynote/wordnote/riddlenote 环境，
-- HTML/EPUB 端加 .in-note 类（样式见 css/cnbook.css）。
--
-- 正文行的宽松写法（poetry / word 通用）：
-- * 行之间可以不空行：pandoc 会把多行合并为一个段落（软换行），
--   滤镜按换行拆成独立的行，与空行分隔的写法效果相同；
-- * 行首可以带空格或制表符：1–3 个空格 pandoc 会自动忽略；
--   制表符/4 个以上空格会被 pandoc 解析成代码块，滤镜把它按行
--   拆回普通文本（行内的 .ruby 等标记会重新解析，不受影响）；
-- * 带脚注标记的“破碎 fence”写法同样支持 fence 与正文、正文与
--   闭 fence 之间不空行，滤镜重组时会按换行拆行；闭 fence 同一
--   段落内后面的行会作为 Div 之外的内容保留。
-- 该滤镜不引入 HTML 标签；所有标记均为 Pandoc Markdown 原生扩展。

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

-- 提取诗体 Div 开头仅由脚注引用组成的段落（作品级脚注标记），
-- 返回脚注 inline 列表和剩余内容块；否则返回空列表与原内容。
local function extract_leading_notes(content)
  if #content == 0 then return {}, content end
  local first = content[1]
  if first.t ~= 'Para' and first.t ~= 'Plain' then return {}, content end
  local notes = {}
  for _, inline in ipairs(first.content) do
    if inline.t == 'Note' then
      table.insert(notes, inline)
    elseif inline.t ~= 'Space' then
      return {}, content
    end
  end
  if #notes == 0 then return {}, content end
  local rest = {}
  for i = 2, #content do
    table.insert(rest, content[i])
  end
  return notes, rest
end

-- 把一行诗歌文本解析为 inline 列表（保留 .ruby 等行内标记）；
-- 解析失败时退化为普通字符串。
local function parse_verse_line(text)
  if pandoc.read then
    local ok, doc = pcall(pandoc.read, text, 'markdown')
    if ok and doc and #doc.blocks > 0 then
      local b = doc.blocks[1]
      if b.t == 'Para' or b.t == 'Plain' then
        return b.content
      end
    end
  end
  return { pandoc.Str(text) }
end

-- 规范化诗体 Div 的正文行，返回新的块列表：
-- * Para/Plain 内的软换行/硬换行（行间未空行的写法）拆成独立段落；
-- * CodeBlock（行首制表符/4 个以上空格的写法）按行拆回普通段落，
--   并去掉行首空白；
-- * 其他块（如已有的空行分隔段落结构）原样保留。
local function split_verse_lines(content)
  local out = {}
  for _, block in ipairs(content) do
    if block.t == 'CodeBlock' then
      for line in (block.text .. '\n'):gmatch('(.-)\n') do
        local t = line:gsub('^[ \t]+', ''):gsub('[ \t]+$', '')
        if t ~= '' then
          table.insert(out, pandoc.Para(parse_verse_line(t)))
        end
      end
    elseif block.t == 'Para' or block.t == 'Plain' then
      local cur = {}
      local function flush()
        if #cur > 0 then
          table.insert(out, pandoc.Para(cur))
          cur = {}
        end
      end
      for _, inline in ipairs(block.content) do
        if inline.t == 'SoftBreak' or inline.t == 'LineBreak' then
          flush()
        else
          table.insert(cur, inline)
        end
      end
      flush()
    else
      table.insert(out, block)
    end
  end
  return out
end

-- 判断 inline 是否为批注（与 zhipi.lua 的判定口径一致：行内代码，
-- 内容以 ( 或（ 开头、以 ) 或 ） 结尾）
local function is_anno_inline(il)
  if il.t ~= 'Code' then return false end
  local t = il.text
  if t:sub(1, 1) ~= '(' and t:sub(1, 3) ~= '（' then return false end
  return t:match('%)%s*$') ~= nil or t:match('）%s*$') ~= nil
end

-- 把诗行内容规范为条目列表：{kind='line'|'block', verse=..., anno=...}。
-- 只拆出**行尾**的批注：不随诗体大字号，同一行跟随正文之后排版
-- （不另起行）。夹在正文中间的批注位置不动，仍留在 verse 里，
-- 输出时仅换成正常字号（见 emit_verse）。
local function split_verse_anno(content)
  local items = {}
  for _, block in ipairs(content) do
    if block.t == 'Para' or block.t == 'Plain' then
      local inls = block.content
      -- 从行尾向前收集批注（允许多条，之间可带空格）
      local anno_rev = {}
      local i = #inls
      while i >= 1 do
        local il = inls[i]
        if il.t == 'Space' then
          i = i - 1
        elseif is_anno_inline(il) then
          table.insert(anno_rev, 1, il)
          i = i - 1
        else
          break
        end
      end
      local verse = {}
      for j = 1, i do
        table.insert(verse, inls[j])
      end
      -- 多条行尾批注之间补一个空格
      local anno = {}
      for _, a in ipairs(anno_rev) do
        if #anno > 0 then table.insert(anno, pandoc.Space()) end
        table.insert(anno, a)
      end
      -- 行尾批注拆出后，正文行首尾的空格没有存在意义
      while #verse > 0 and verse[1].t == 'Space' do table.remove(verse, 1) end
      while #verse > 0 and verse[#verse].t == 'Space' do table.remove(verse) end
      table.insert(items, { kind = 'line', verse = verse, anno = anno })
    else
      table.insert(items, { kind = 'block', block = block })
    end
  end
  return items
end

-- 输出诗行正文（LaTeX）：夹在正文中间的批注位置不动，
-- 包 \verseanno 换成正常字号
local function emit_verse_latex(inls, verse)
  for _, il in ipairs(verse) do
    if is_anno_inline(il) then
      table.insert(inls, pandoc.RawInline('latex', '\\verseanno{'))
      table.insert(inls, il)
      table.insert(inls, pandoc.RawInline('latex', '}'))
    else
      table.insert(inls, il)
    end
  end
end

-- 输出诗行正文（HTML）：夹在正文中间的批注位置不动，
-- 包 .verse-anno span 换成正常字号
local function emit_verse_html(inls, verse)
  for _, il in ipairs(verse) do
    if is_anno_inline(il) then
      table.insert(inls, pandoc.Span({ il }, pandoc.Attr('', { 'verse-anno' })))
    else
      table.insert(inls, il)
    end
  end
end

-- 拆开元信息属性值中的批注标记 ```(类型：…)```：
-- 如 author="蘅芜君```(己夹：…)```"、title="芙蓉女儿诔```(庚夹：…)```"。
-- 返回纯文本与批注 Code 列表；
-- 批注以 Code 形式交回主流程，由 zhipi 滤镜统一着色。
local function split_meta_anno(s)
  local text, annos = {}, {}
  local pos = 1
  while true do
    local b, e, inner = s:find('```([(（].-[)）])```', pos)
    if not b then break end
    if b > pos then table.insert(text, s:sub(pos, b - 1)) end
    table.insert(annos, pandoc.Code(inner))
    pos = e + 1
  end
  table.insert(text, s:sub(pos))
  return table.concat(text), annos
end

-- 元信息文字以全角空格“　”分隔主名与副题（如 title="凝晖钟瑞　匾额"
-- 的“匾额”）：返回主名（保留末尾“　”作间隔）与副题；无“　”时副题
-- 为 nil。副题由主流程以小一号字渲染
local function split_meta_sub(s)
  local b = s:find('　')
  if not b then return s, nil end
  return s:sub(1, b + 2), s:sub(b + 3)  -- “　”占 3 字节
end

-- 将诗体 Div（poetry / word 等）转换为 LaTeX 环境或 HTML div。
-- cls: Pandoc 类名； latex_env: LaTeX 环境名；
-- title_cmd/author_cmd/date_cmd: LaTeX 标题/作者/日期命令名；
-- meta_notes: 可选，属性值后的脚注标记（如 {title={...}, author={...}}）；
-- meta_center: 可选，为 true 时元信息行在 LaTeX 中用 center 环境居中
-- （HTML 端由 CSS 的 text-align 控制）；
-- attr_parts: 可选，属性值内嵌脚注标记的片段（如 title="沁园春[^x]·长沙"）。
local function render_poetry_like(el, cls, latex_env, title_cmd, author_cmd, date_cmd, meta_notes, meta_center, attr_parts)
  -- title/author/date 为空时，不输出任何与之相关的格式内容：
  -- 清掉空属性，避免 HTML 端产生 title="" / data-author="" 之类的空属性
  for _, key in ipairs({ 'title', 'author', 'date' }) do
    if el.attributes[key] == '' then el.attributes[key] = nil end
  end
  -- 脚注内的诗体（.in-note 类，由 note 属性嫁接时打上）：
  -- LaTeX 端换用 *note 环境（字号更小），HTML 端类已带上由 CSS 控制
  if el.classes:includes('in-note') then
    latex_env = latex_env .. 'note'
  end
  local title = el.attributes['title'] or ''
  local author = el.attributes['author'] or ''
  local date = el.attributes['date'] or ''
  -- author/title/date 中可能带批注（如 author="蘅芜君```(己夹：…)```"）：
  -- 拆出后文字照常渲染，批注跟在文字后以正常字号着色排版
  local author_text, author_annos = split_meta_anno(author)
  local title_text, title_annos = split_meta_anno(title)
  local date_text, date_annos = split_meta_anno(date)
  local notes, content = extract_leading_notes(el.content)
  -- 行间未空行（软换行合并为一个段落）或行首带空白（代码块）的
  -- 宽松写法，统一规范为“每行一个段落”
  content = split_verse_lines(content)
  -- 谜语（riddle）：最后一行以“打”开头（可带前导“——”）时视为谜目
  -- （可选），从谜面中取出，稍后以右对齐小一号字单独渲染
  local mimu = nil
  if cls == 'riddle' and #content > 0 then
    local last = content[#content]
    if (last.t == 'Para' or last.t == 'Plain')
       and pandoc.utils.stringify(last.content):match('^——?打') then
      mimu = last.content
      table.remove(content)
    end
  end
  meta_notes = meta_notes or {}
  attr_parts = attr_parts or {}
  -- 诗行中的批注拆出（正文行 verse / 批注行 anno）
  local items = split_verse_anno(content)

  if FORMAT:match 'latex' then
    local result = { pandoc.RawBlock('latex', '\\begin{' .. latex_env .. '}') }
    -- LaTeX 元信息命令：title/author 的副题（“　”之后）小一号字
    local function meta_tex(cmd, text, with_sub)
      local head, sub = text, nil
      if with_sub then head, sub = split_meta_sub(text) end
      local tex = '\\' .. cmd .. '{' .. escape_latex(head)
      if sub then tex = tex .. '\\metasub{' .. escape_latex(sub) .. '}' end
      return tex .. '}'
    end
    local metas = {}
    if title ~= '' then
      table.insert(metas, { key = 'title', cmd = title_cmd,
        tex = meta_tex(title_cmd, title_text, true),
        annos = title_annos })
    end
    if author ~= '' then
      table.insert(metas, { key = 'author', cmd = author_cmd,
        tex = meta_tex(author_cmd, author_text, true),
        annos = author_annos })
    end
    if date ~= '' then
      table.insert(metas, { key = 'date', cmd = date_cmd,
        tex = meta_tex(date_cmd, date_text, false),
        annos = date_annos })
    end
    if #metas > 0 and meta_center then
      table.insert(result, pandoc.RawBlock('latex', '\\begin{center}'))
    end
    for i, meta in ipairs(metas) do
      -- 属性值后标记（title="..."[^x]）随对应属性行；
      -- 作品级标记（}[^x] 或 Div 首行）随首个元信息行
      local attached = {}
      for _, note in ipairs(meta_notes[meta.key] or {}) do
        table.insert(attached, note)
      end
      if i == 1 then
        for _, note in ipairs(notes) do
          table.insert(attached, note)
        end
      end
      if attr_parts[meta.key] then
        -- 值内嵌标记（title="沁园春[^x]·长沙"）：命令拆开，
        -- 让脚注落在标记原位
        local inlines = { pandoc.RawInline('latex',
          '\\' .. meta.cmd .. '{') }
        for _, part in ipairs(attr_parts[meta.key]) do
          if part.kind == 'text' then
            table.insert(inlines,
              pandoc.RawInline('latex', escape_latex(part.text)))
          else
            table.insert(inlines, part.note)
          end
        end
        table.insert(inlines, pandoc.RawInline('latex', '}'))
        for _, note in ipairs(attached) do
          table.insert(inlines, note)
        end
        table.insert(result, pandoc.Plain(inlines))
      elseif #attached > 0 or (meta.annos and #meta.annos > 0) then
        local inlines = { pandoc.RawInline('latex', meta.tex) }
        -- 元信息里的批注：以零宽盒子挂在名字右侧，名字的居中不受影响
        for _, a in ipairs(meta.annos or {}) do
          table.insert(inlines, pandoc.RawInline('latex',
            '\\makebox[0pt][l]{\\hspace{0.5em}\\verseanno{'))
          table.insert(inlines, a)
          table.insert(inlines, pandoc.RawInline('latex', '}}'))
        end
        for _, note in ipairs(attached) do
          table.insert(inlines, note)
        end
        table.insert(result, pandoc.Plain(inlines))
      else
        table.insert(result, pandoc.RawBlock('latex', meta.tex))
      end
    end
    if #metas > 0 and meta_center then
      table.insert(result, pandoc.RawBlock('latex', '\\end{center}'))
    end
    if #metas > 0 then
      table.insert(result, pandoc.RawBlock('latex', '\\vspace{0.6em}'))
    elseif #notes > 0 then
      -- 无元信息时脚注标记作为独立段落保留
      table.insert(result, pandoc.Plain(notes))
    end
    -- poetry/riddle：第一行用 \verselinefirst 定统一缩进（本行居中），
    -- 后续行用 \verseline 与第一行左对齐；批注都作为第二参数同行跟随
    local first_line = (cls ~= 'word')
    for _, item in ipairs(items) do
      if item.kind == 'line' then
        local inls = {}
        if cls == 'word' then
          -- 词（左对齐环境）：批注同一行紧跟正文，正常字号，
          -- 折行后续行顶格（左对齐段落的自然行为）
          emit_verse_latex(inls, item.verse)
          if #item.anno > 0 then
            table.insert(inls, pandoc.RawInline('latex', '\\verseanno{'))
            for _, il in ipairs(item.anno) do
              table.insert(inls, il)
            end
            table.insert(inls, pandoc.RawInline('latex', '}'))
          end
        else
          local cmd = first_line and '\\verselinefirst{' or '\\verseline{'
          first_line = false
          table.insert(inls, pandoc.RawInline('latex', cmd))
          emit_verse_latex(inls, item.verse)
          table.insert(inls, pandoc.RawInline('latex', '}{'))
          for _, il in ipairs(item.anno) do
            table.insert(inls, il)
          end
          table.insert(inls, pandoc.RawInline('latex', '}'))
        end
        table.insert(result, pandoc.Para(inls))
      else
        table.insert(result, item.block)
      end
    end
    if mimu then
      local inlines = { pandoc.RawInline('latex', '\\riddlemimu{') }
      for _, il in ipairs(mimu) do
        table.insert(inlines, il)
      end
      table.insert(inlines, pandoc.RawInline('latex', '}'))
      table.insert(result, pandoc.Plain(inlines))
    end
    table.insert(result, pandoc.RawBlock('latex', '\\end{' .. latex_env .. '}'))
    return result

  elseif FORMAT:match 'html' or FORMAT:match 'epub' then
    -- 元信息行用嵌套 Div 渲染
    local function meta_block(suffix, inlines)
      return pandoc.Div({ pandoc.Plain(inlines) },
                        pandoc.Attr('', { cls .. '-' .. suffix }))
    end
    local blocks = {}
    local hoisted = false
    -- 属性值后标记随对应属性行；作品级标记随首个元信息行
    local function collect(key)
      local ns = {}
      for _, note in ipairs(meta_notes[key] or {}) do
        table.insert(ns, note)
      end
      if not hoisted then
        for _, note in ipairs(notes) do
          table.insert(ns, note)
        end
        hoisted = true
      end
      return ns
    end
    -- 值内嵌标记（title="沁园春[^x]·长沙"）落在标记原位（此路径不拆副题）；
    -- annos：属性值中拆出的批注（Code，交给 zhipi 滤镜着色）；
    -- with_sub：title/author 拆副题（“　”之后小一号字）
    local function meta_inlines(key, text, annos, with_sub)
      local inlines = {}
      if attr_parts[key] then
        for _, part in ipairs(attr_parts[key]) do
          if part.kind == 'text' then
            table.insert(inlines, pandoc.Str(part.text))
          else
            table.insert(inlines, part.note)
          end
        end
      else
        local head, sub = text, nil
        if with_sub then head, sub = split_meta_sub(text) end
        table.insert(inlines, pandoc.Str(head))
        if sub then
          table.insert(inlines, pandoc.Span({ pandoc.Str(sub) },
                                            pandoc.Attr('', { 'meta-sub' })))
        end
      end
      for _, a in ipairs(annos or {}) do
        table.insert(inlines, pandoc.Space())
        table.insert(inlines, a)
      end
      for _, note in ipairs(collect(key)) do
        table.insert(inlines, note)
      end
      return inlines
    end
    if title ~= '' then
      table.insert(blocks, meta_block('title',
                                      meta_inlines('title', title_text,
                                                   title_annos, true)))
    end
    if author ~= '' then
      table.insert(blocks, meta_block('author',
                                      meta_inlines('author', author_text,
                                                   author_annos, true)))
    end
    if date ~= '' then
      table.insert(blocks, meta_block('date',
                                      meta_inlines('date', date_text,
                                                   date_annos, false)))
    end
    if not hoisted and #notes > 0 then
      table.insert(blocks, pandoc.Plain(notes))
    end
    -- 正文行：批注拆为 .verse-anno span 同一行紧跟（不随诗体大字号）；
    -- poetry/riddle 的行包进内层 Div（.poetry-lines/.riddle-lines），
    -- CSS 用 inline-block 让各行左边缘对齐、整体居中
    local line_blocks = {}
    for _, item in ipairs(items) do
      if item.kind == 'line' then
        local inls = {}
        emit_verse_html(inls, item.verse)
        if #item.anno > 0 then
          table.insert(inls, pandoc.Span(item.anno,
                                         pandoc.Attr('', { 'verse-anno' })))
        end
        table.insert(line_blocks, pandoc.Para(inls))
      else
        table.insert(line_blocks, item.block)
      end
    end
    if cls == 'word' then
      for _, b in ipairs(line_blocks) do
        table.insert(blocks, b)
      end
    else
      table.insert(blocks, pandoc.Div(line_blocks,
                                      pandoc.Attr('', { cls .. '-lines' })))
    end
    if mimu then
      table.insert(blocks, pandoc.Div({ pandoc.Plain(mimu) },
                                      pandoc.Attr('', { 'riddle-mimu' })))
    end
    el.content = blocks
    return el
  end

  -- 对不支持的输出格式保持原样透传
  return el
end

-- 从 pandoc 输入文件扫描脚注定义文本。
-- pandoc 会把未被引用的脚注定义丢弃；合法 fence 属性值里的 [^label]
-- 只是纯文本，滤镜只能从源文件把定义找回来。
-- 缓存的是定义原文，每次使用时重新解析，避免共享 Note 对象。
local note_defs_cache = nil
local function load_note_defs()
  if note_defs_cache then return note_defs_cache end
  note_defs_cache = {}
  local files = (PANDOC_STATE and PANDOC_STATE.input_files) or {}
  for _, path in ipairs(files) do
    local fh = io.open(path, 'r')
    if fh then
      local label, buf = nil, {}
      local function flush()
        if label and #buf > 0 then
          note_defs_cache[label] = table.concat(buf, '\n')
        end
        label, buf = nil, {}
      end
      for line in fh:lines() do
        local l, rest = line:match('^%[%^([^]]+)%]:%s*(.*)$')
        if l then
          flush()
          label, buf = l, { rest }
        elseif label and line:match('^%s+%S') then
          -- 缩进的续行属于同一条定义
          table.insert(buf, (line:gsub('^%s+', '')))
        elseif label then
          flush()
        end
      end
      flush()
      fh:close()
    end
  end
  return note_defs_cache
end

-- 把定义原文解析为 Note inline；失败返回 nil。
local function make_note(label)
  local text = load_note_defs()[label]
  if not text or not pandoc.read then return nil end
  local ok, doc = pcall(pandoc.read, text, 'markdown')
  if ok and doc and #doc.blocks > 0 then
    return pandoc.Note(doc.blocks)
  end
  return nil
end

-- 把合法 fence 属性值里的字面 [^label] 标记拆成片段并解析定义。
-- 返回片段列表与找不到定义的标签列表；值内无标记时返回 nil。
local function split_literal_value(value)
  if not value:find('%[%^') then return nil end
  local parts = {}
  local unresolved = {}
  local pos = 1
  while true do
    local s, e, label = value:find('%[%^([^]]+)%]', pos)
    if not s then break end
    if s > pos then
      table.insert(parts, { kind = 'text', text = value:sub(pos, s - 1) })
    end
    local note = make_note(label)
    if note then
      table.insert(parts, { kind = 'note', note = note })
    else
      -- 定义找不到时保留字面文本，避免静默丢失
      table.insert(parts, { kind = 'text', text = value:sub(s, e) })
      table.insert(unresolved, label)
    end
    pos = e + 1
  end
  if pos <= #value then
    table.insert(parts, { kind = 'text', text = value:sub(pos) })
  end
  return parts, unresolved
end

-- 将 .poetry div 转换为 LaTeX 的 poetry 环境或 HTML 的 div。
-- 支持可选 title、author 与 date 属性。
-- 将 .word（词） div 转换为 LaTeX 的 word 环境或 HTML 的 div。
-- 属性与 poetry 相同，排版为左对齐、段前空两个中文字符。
-- meta_notes: 可选，属性值后脚注标记（重组破碎 fence 时传入）；
-- attr_parts: 可选，属性值内嵌脚注标记的片段（同上）。
local function render_div(el, meta_notes, attr_parts)
  if (el.classes:includes('poetry') or el.classes:includes('word')
      or el.classes:includes('riddle'))
     and attr_parts == nil then
    -- 合法 fence（pandoc 直接解析）的属性值只是纯字符串，
    -- 其中的 [^x] 不会被 pandoc 解析为脚注；从源文件找回定义。
    local resolved = {}
    local any = false
    for _, key in ipairs({ 'title', 'author', 'date' }) do
      local value = el.attributes[key]
      if value and value:find('%[%^') then
        local parts, unresolved = split_literal_value(value)
        if parts then
          resolved[key] = parts
          any = true
          -- 清掉属性里的字面标记，避免在 HTML 属性中原样显示
          el.attributes[key] = (value:gsub('%[%^[^]]+%]', ''))
        end
        for _, label in ipairs(unresolved or {}) do
          io.stderr:write(string.format(
            '[poetry-word] WARNING: %s 属性里的脚注标记 [^%s] 找不到定义，'
            .. '已按普通文字处理。\n', key, label))
        end
      end
    end
    if any then attr_parts = resolved end
  end
  if el.classes:includes('poetry') then
    -- 诗：正文第一行居中、后续行与第一行左对齐；标题/作者/日期行居中
    return render_poetry_like(el, 'poetry', 'poetry',
                              'poetrytitle', 'poetryauthor', 'poetrydate',
                              meta_notes, true, attr_parts)
  elseif el.classes:includes('word') then
    -- 词：正文左对齐、段前空两格，标题/作者/日期行居中
    return render_poetry_like(el, 'word', 'word',
                              'wordtitle', 'wordauthor', 'worddate',
                              meta_notes, true, attr_parts)
  elseif el.classes:includes('riddle') then
    -- 谜语：谜面同 poetry；标题/作者/日期行居中；
    -- 末行以“打”开头时按谜目特殊渲染
    return render_poetry_like(el, 'riddle', 'riddle',
                              'riddletitle', 'riddleauthor', 'riddledate',
                              meta_notes, true, attr_parts)
  end
  return el
end

function Div(el)
  -- 带 note 属性的诗体 Div 推迟到 Pandoc 函数统一处理（移入对应
  -- 脚注）；此处原样保留，避免先按正文诗体渲染后无法定位移除
  if (el.classes:includes('poetry') or el.classes:includes('word')
      or el.classes:includes('riddle'))
     and el.attributes['note'] then
    return el
  end
  return render_div(el, nil)
end

-- 把属性值（Quoted 内容）拆成文本与脚注标记片段。
-- 返回纯文本（不含标记）与片段列表；值内无标记时片段为 nil。
local function split_value_parts(inlines)
  local parts = {}
  local buf = {}
  local full = {}
  local has_note = false
  local function flush()
    if #buf > 0 then
      local s = pandoc.utils.stringify(buf)
      table.insert(parts, { kind = 'text', text = s })
      table.insert(full, s)
      buf = {}
    end
  end
  for _, inline in ipairs(inlines) do
    if inline.t == 'Note' then
      flush()
      has_note = true
      table.insert(parts, { kind = 'note', note = inline })
    else
      table.insert(buf, inline)
    end
  end
  flush()
  return table.concat(full), (has_note and parts or nil)
end

-- 解析被脚注标记“撑破”的 Div 开 fence 段落。
-- pandoc 不允许 fenced Div 属性行后跟随其他内容，
-- `::: {.poetry ...}[^2-2-1]` 会被解析成普通段落（Para）；
-- fence 与正文/闭 fence 之间未空行时，整个 Div 也会合并进该段落。
-- 成功时返回 { classes, attributes, notes, meta_notes, attr_parts,
-- leading, trailing, closed }，否则返回 nil。
-- leading：开 fence 段落内自带的正文行（按换行拆分）；
-- closed/trailing：同段落内遇到闭 fence 及其后的剩余行。
local function parse_broken_fence(block)
  if block.t ~= 'Para' then return nil end
  local inl = block.content
  if #inl < 5 then return nil end
  if inl[1].t ~= 'Str' or not inl[1].text:match('^:::+$') then return nil end
  local i = 2
  if inl[i].t ~= 'Space' then return nil end
  i = i + 1
  if inl[i].t ~= 'Str' or not inl[i].text:match('^{%.') then return nil end
  local classes = { (inl[i].text:gsub('^{%.', '')) }
  i = i + 1
  -- 附加类（以 . 开头的 Str）
  while i + 1 <= #inl and inl[i].t == 'Space'
        and inl[i + 1].t == 'Str' and inl[i + 1].text:match('^%.') do
    table.insert(classes, (inl[i + 1].text:gsub('^%.', '')))
    i = i + 2
  end
  local attrs = {}
  local attr_parts = {}
  local notes = {}
  local meta_notes = {}
  local last_attr = nil
  while i <= #inl do
    local cur = inl[i]
    if cur.t == 'Space' then
      i = i + 1
    elseif cur.t == 'Str' and cur.text == '}' then
      i = i + 1
      -- } 之后同一行内只允许跟脚注引用
      while i <= #inl and inl[i].t ~= 'SoftBreak' and inl[i].t ~= 'LineBreak' do
        if inl[i].t == 'Note' then
          table.insert(notes, inl[i])
        elseif inl[i].t ~= 'Space' then
          return nil
        end
        i = i + 1
      end
      -- 开 fence 与闭 fence 之间未空行时，pandoc 会把整个 Div 合并成
      -- 一个段落：按换行把正文拆回独立的行；独占一行的 ::: 视为
      -- 闭 fence，其后的行属于 Div 之外的后续内容，需要保留
      local leading, trailing = {}, {}
      local cur_line = {}
      local closed = false
      local function flush_line()
        while #cur_line > 0 and cur_line[1].t == 'Space' do
          table.remove(cur_line, 1)
        end
        while #cur_line > 0 and cur_line[#cur_line].t == 'Space' do
          table.remove(cur_line)
        end
        if #cur_line > 0 then
          table.insert(closed and trailing or leading, cur_line)
          cur_line = {}
        end
      end
      local at_line_start = true
      while i <= #inl do
        local x = inl[i]
        if x.t == 'SoftBreak' or x.t == 'LineBreak' then
          flush_line()
          at_line_start = true
        elseif not closed and at_line_start and x.t == 'Str'
               and x.text:match('^:::+$')
               and (inl[i + 1] == nil or inl[i + 1].t == 'SoftBreak'
                    or inl[i + 1].t == 'LineBreak') then
          closed = true
        else
          table.insert(cur_line, x)
          if x.t ~= 'Space' then at_line_start = false end
        end
        i = i + 1
      end
      flush_line()
      return { classes = classes, attributes = attrs,
               notes = notes, meta_notes = meta_notes,
               attr_parts = attr_parts,
               leading = leading, trailing = trailing,
               closed = closed }
    elseif cur.t == 'Note' then
      -- } 之前的脚注标记归属于最近解析的属性（缺省 title）
      local key = last_attr or 'title'
      meta_notes[key] = meta_notes[key] or {}
      table.insert(meta_notes[key], cur)
      i = i + 1
    elseif cur.t == 'Str' and cur.text:match('=$') then
      local key = cur.text:gsub('=$', '')
      local val = inl[i + 1]
      if val == nil then return nil end
      if val.t == 'Quoted' then
        -- 值内的脚注标记（如 title="沁园春[^x]·长沙"）拆片段保留
        local full, parts = split_value_parts(val.content)
        attrs[key] = full
        if parts then attr_parts[key] = parts end
      elseif val.t == 'Str' then
        attrs[key] = val.text
      else
        return nil
      end
      last_attr = key
      i = i + 2
    else
      return nil
    end
  end
  return nil
end

-- 闭合 fence：恰好只含一串冒号的段落。
local function is_closing_fence(block)
  return block.t == 'Para' and #block.content == 1
         and block.content[1].t == 'Str'
         and block.content[1].text:match('^:::+$') ~= nil
end

-- 把渲染后的块并入“内容以 prefix 开头”的首个未嫁接脚注（pandoc 的
-- Note 不保留标签，只能按定义首段文字做内容前缀匹配；.content 访问
-- 拿到的是副本，必须赋回并把修改后的元素作为过滤器返回值写回）。
-- 成功返回 true 与更新后的 blocks；未命中返回 false 与原 blocks。
local function graft_into_note(blocks, prefix, grafted, rblocks)
  local done = false
  local div = pandoc.walk_block(pandoc.Div(blocks), { Note = function(n)
    if done or grafted[n] then return nil end
    if pandoc.utils.stringify(n.content):sub(1, #prefix) ~= prefix then
      return nil
    end
    local nc = n.content
    for _, rb in ipairs(rblocks) do table.insert(nc, rb) end
    n.content = nc
    grafted[n] = true
    done = true
    return n
  end })
  return done, div.content
end

-- 脚注定义首段的纯文本（作为匹配 Note 的前缀）；找不到定义返回 nil。
-- 与正文同样开 smart 排版，保证引号/破折号 stringify 后一致
local function note_def_prefix(label)
  local text = load_note_defs()[label]
  if not text or not pandoc.read then return nil end
  local ok, doc = pcall(pandoc.read, text, 'markdown+smart')
  if ok and doc and #doc.blocks > 0 then
    return pandoc.utils.stringify(doc.blocks[1])
  end
  return nil
end

-- 把带 note 属性的顶层诗体 Div 移入对应脚注（渲染为较小的脚注诗体）；
-- 找不到对应脚注时告警并留在原位按正文诗体渲染。
-- 注意：walk 命中 Note 后会一路重建祖先元素（克隆出新表），因此
-- 1) 先给每个标记 Div 编上 poetry-graft-id 属性，之后靠属性值而
--    不是表 identity 识别（克隆体带着同一属性）；
-- 2) 渲染用克隆体，不改原 Div（原 Div 要留到最后统一剔除/回退）；
-- 3) 先完成全部嫁接（graft_into_note 返回更新后的 blocks），再从
--    最终的 blocks 里按 poetry-graft-id 剔除/回退标记 Div。
local function graft_note_divs(blocks)
  local marked = {}
  for _, b in ipairs(blocks) do
    local is_poem = b.t == 'Div'
      and (b.classes:includes('poetry') or b.classes:includes('word')
           or b.classes:includes('riddle'))
    if is_poem and b.attributes['note'] then
      local id = tostring(#marked + 1)
      b.attributes['poetry-graft-id'] = id
      table.insert(marked, { id = id, label = b.attributes['note'],
                             div = b })
    end
  end
  if #marked == 0 then return blocks end
  -- 用克隆体渲染（in_note 决定脚注诗体/正文诗体），不碰原 Div
  local function render_clone(b, in_note)
    local classes = pandoc.List(b.classes)
    if in_note then classes:insert('in-note') end
    local attrs = {}
    for k, v in pairs(b.attributes) do
      if k ~= 'note' and k ~= 'poetry-graft-id' then attrs[k] = v end
    end
    local clone = pandoc.Div(b.content, pandoc.Attr('', classes, attrs))
    local rendered = render_div(clone, nil)
    if type(rendered) == 'table' and rendered.t then
      return { rendered }
    elseif type(rendered) == 'table' then
      return rendered
    end
    return {}
  end
  local grafted_notes = {}
  local done, fallback = {}, {}
  for _, m in ipairs(marked) do
    local prefix = note_def_prefix(m.label)
    local ok = false
    if prefix and prefix ~= '' then
      ok, blocks = graft_into_note(blocks, prefix, grafted_notes,
                                   render_clone(m.div, true))
    end
    if ok then
      done[m.id] = true
    else
      io.stderr:write(string.format(
        '[poetry-word] WARNING: note="%s" 的诗体 Div 找不到对应脚注，'
        .. '已按正文诗体渲染。\n', m.label))
      fallback[m.id] = render_clone(m.div, false)
    end
  end
  local out = {}
  for _, b in ipairs(blocks) do
    local gid = b.t == 'Div' and b.attributes['poetry-graft-id'] or nil
    if gid and done[gid] then
      -- 已并入脚注，顶层不再保留
    elseif gid and fallback[gid] then
      for _, rb in ipairs(fallback[gid]) do table.insert(out, rb) end
    else
      table.insert(out, b)
    end
  end
  return out
end

-- 全文扫描，把 } 后跟脚注标记而未能识别的 Div 重新组装并渲染。
function Pandoc(doc)
  -- 带 note 属性的诗体 Div 先移入对应脚注（note 属性写法见文件头注释）
  doc.blocks = graft_note_divs(doc.blocks)
  local blocks = doc.blocks
  local out = {}
  local i = 1
  while i <= #blocks do
    local parsed = parse_broken_fence(blocks[i])
    if not parsed then
      table.insert(out, blocks[i])
      i = i + 1
    else
      -- 开 fence 所在段落内可能已带正文行（fence 与正文之间未空行的
      -- 写法），甚至同段落内已有闭 fence（parsed.closed）
      local content = {}
      for _, line_inlines in ipairs(parsed.leading or {}) do
        table.insert(content, pandoc.Para(line_inlines))
      end
      local next_i = nil
      if parsed.closed then
        next_i = i + 1
      else
        local j = i + 1
        while j <= #blocks and not is_closing_fence(blocks[j]) do
          table.insert(content, blocks[j])
          j = j + 1
        end
        if j <= #blocks then next_i = j + 1 end
      end
      if not next_i then
        -- 找不到闭合 fence，保持原样输出
        table.insert(out, blocks[i])
        i = i + 1
      else
        local div = pandoc.Div(content,
          pandoc.Attr('', parsed.classes, parsed.attributes))
        local is_poem = div.classes:includes('poetry')
                        or div.classes:includes('word')
                        or div.classes:includes('riddle')
        if is_poem then
          if #parsed.notes > 0 then
            -- 作品级脚注标记放到 Div 开头，交由统一渲染提升
            table.insert(div.content, 1, pandoc.Plain(parsed.notes))
          end
        else
          -- 其他类的 Div：所有标记放回内容开头
          local all = {}
          for _, ns in pairs(parsed.meta_notes) do
            for _, n in ipairs(ns) do
              table.insert(all, n)
            end
          end
          for _, n in ipairs(parsed.notes) do
            table.insert(all, n)
          end
          if #all > 0 then
            table.insert(div.content, 1, pandoc.Plain(all))
          end
        end
        local rendered = render_div(div,
          is_poem and parsed.meta_notes or nil,
          is_poem and parsed.attr_parts or nil)
        if type(rendered) == 'table' and rendered.t then
          table.insert(out, rendered)
        elseif type(rendered) == 'table' then
          for _, rb in ipairs(rendered) do
            table.insert(out, rb)
          end
        end
        -- 闭 fence 之后同段落内的剩余行属于 Div 外的内容，补回
        for _, line_inlines in ipairs(parsed.trailing or {}) do
          table.insert(out, pandoc.Para(line_inlines))
        end
        i = next_i
      end
    end
  end
  doc.blocks = out
  return doc
end
