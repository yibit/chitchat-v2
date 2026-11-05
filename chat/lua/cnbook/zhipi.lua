-- cnbook/lua/zhipi.lua
-- 行内批注（评点本书籍的批语）按“批注类型”着色，PDF 与 HTML/EPUB 双端。
-- 批注写作行内代码：```(批注类型：批语)```（也接受全角括号），pandoc
-- 解析为行内代码（Code），本滤镜按全角冒号前的“批注类型”为整条批注
-- 着色：PDF 端输出 \textcolor[RGB]，HTML/EPUB 端输出
-- <span class="zhipi" style="color:#…">；渲染时去掉首尾包裹的括号与
-- 类型后的全角冒号（颜色与徽章已足以区分批注与正文），但 3 字及以上
-- 的类型（如 戚总评）保留冒号作分隔——徽章只覆盖首字，余下类型字与
-- 正文同色难以区分。类型为 1~3 个字时首字渲染为“白字色底”
-- 徽章（2 字类型的第 2 字为“色框色字”），PDF 端用 \zhipibg/\zhipiframe
-- 宏（定义见 latex/zhipi.tex），HTML/EPUB 端用等效内联样式。
-- 超长类型与无类型批注不做徽章；不带“类型：”的批注继承前一条批注的
-- 颜色，没有前条时用兜底色。
--
-- 编译期开关（环境变量，非空且非 "0" 即生效）：
--   ZHIPI_HIDE    隐藏模式：所有批注在编译期被整体丢弃，输出纯净正文
--   ZHIPI_PARENS  保留括号：批注首尾括号按源码原样印出（默认去掉），
--                 此模式下不做徽章，维持旧的整体着色样式
--   ZHIPI_BODY_ONLY  首尾保留模式：只去掉夹在正文中的批注；回目之后、
--                 正文之前的回前批语与正文之后的回末总评（整段批注）
--                 保留并照常着色；整段批注中嵌套的内层批注（如 001 回首
--                 庚辰凡例中夹的蒙府侧批）一并去掉，只留外层文字
--
-- 配色：内置默认配色表（《石头记》批注体系：同底本同色系，批式间小幅
-- 偏移）。书稿目录（pandoc 工作目录）下若存在 zhipi-colors.lua，
-- 应 return 一个“类型 → 十六进制颜色（不含 #）”的表，其条目会合并
-- 覆盖默认表，供其他评点本项目自定义。

-- --- 开关 ---------------------------------------------------------------

local ZHIPI_HIDDEN = (function()
  local v = os.getenv('ZHIPI_HIDE')
  return v ~= nil and v ~= '' and v ~= '0'
end)()

local ZHIPI_PARENS = (function()
  local v = os.getenv('ZHIPI_PARENS')
  return v ~= nil and v ~= '' and v ~= '0'
end)()

local ZHIPI_BODY_ONLY = (function()
  local v = os.getenv('ZHIPI_BODY_ONLY')
  return v ~= nil and v ~= '' and v ~= '0'
end)()

-- --- 配色表 ---------------------------------------------------------------

-- 类型 → 颜色（十六进制，不含 #）。同一底本同一色系（甲戌/甲为棕褐系、
-- 庚辰为青蓝系、己卯为草绿系、蒙为紫色系、靖为蓝灰系、列为玫红系、
-- 戚序为藕粉系、梦录为朱红系），同一底本的不同批式在色系内小幅偏移。
local ZHIPI_COLORS = {
  -- 甲戌本（棕褐/土金系；裸“甲”为甲戌本无批式标注的批语）
  ['甲'] = '936915',
  ['甲侧'] = '917d16',
  ['甲夹'] = '8f8f18',
  ['甲眉'] = '8c791b',
  ['甲回目标题'] = '9eaf1c',
  -- 庚辰本（青蓝系；裸“庚”为庚辰本无批式标注的批语，如 001 回首凡例段）
  ['庚'] = '155493',
  ['庚侧'] = '188b9a',
  ['庚夹'] = '20a3a6',
  ['庚眉'] = '18858f',
  ['庚旁'] = '1b5d8c',
  -- 己卯本（草绿系；裸“己”为己卯本无批式标注的批语，如 017 回前批，
  -- 与己侧错开以免混淆）
  ['己'] = '157a26',
  ['己侧'] = '1f9323',
  ['己夹'] = '3da819',
  ['己眉'] = '17a52c',
  -- 蒙府本（紫色系）
  ['蒙侧'] = '811d9a',
  ['蒙夹'] = '9620a0',
  -- 靖藏本（蓝灰系；靖录为据靖藏本等录出的批语；裸“靖”为靖藏本
  -- 无批式标注的批语）
  ['靖'] = '18368f',
  ['靖眉'] = '18548f',
  ['靖侧'] = '164991',
  ['靖录'] = '1e3cb2',
  -- 列藏本（玫红系）
  ['列侧'] = '9a1d74',
  -- 戚序本（藕粉系）
  ['戚'] = 'a85468',
  ['戚总批'] = '9e4c64',
  ['戚总评'] = 'b25c6a',
  ['戚夹'] = '96445f',
  -- 甲辰本（梦觉主人序本，赭橙系；如 019 回前的甲辰删批说明批）
  ['辰'] = 'b5621f',
  -- 其他
  ['梦录'] = 'b22d1e',
  ['题曰'] = 'b0a720',
  ['校注'] = '9b8f21',
  ['编注'] = '6d6256',
  ['编按'] = '6d6256',
}

-- 未列入主表时的底本家族回退色（按类型前缀匹配，长前缀在前）
local ZHIPI_FAMILIES = {
  { '甲辰', 'b5621f' },
  { '甲', '936915' }, { '庚', '155493' }, { '己', '1f9323' },
  { '蒙', '96168a' }, { '靖', '18368f' }, { '列', '9a1d74' },
  { '戚', 'a85468' }, { '梦', 'b22d1e' },
}

-- 兜底色：朱砂红（朱批）
local ZHIPI_DEFAULT = 'a13d36'

-- 项目自定义配色：书稿目录下的 zhipi-colors.lua return 的表逐条合并覆盖
do
  local ok, custom = pcall(dofile, 'zhipi-colors.lua')
  if ok and type(custom) == 'table' then
    for k, v in pairs(custom) do ZHIPI_COLORS[k] = v end
  end
end

-- 前一条批注的颜色：无类型批注继承它
local last_zhipi_color = nil

-- 首尾保留模式（ZHIPI_BODY_ONLY）下，批注元素在 pandoc 遍历时原样保留，
-- 由 Pandoc 滤镜的分章遍历统一取舍（见文件末尾）；该标志在 Pandoc 滤镜
-- 开始时置真，此后对 Code 的手动调用（渲染首尾部区块、脚注内的批注）
-- 正常工作
local in_pandoc_phase = false

local function hex_to_rgb(hex)
  return string.format('%d,%d,%d', tonumber(hex:sub(1, 2), 16),
                       tonumber(hex:sub(3, 4), 16),
                       tonumber(hex:sub(5, 6), 16))
end

-- 去掉批注文本首尾的包裹括号：首字符 '(' / '（'，末字符 ')' / '）'
-- （末尾括号后允许有空白，一并去掉）
local function strip_parens(text)
  text = text:gsub('%s+$', '')
  if text:sub(1, 3) == '（' then
    text = text:sub(4)
  elseif text:sub(1, 1) == '(' then
    text = text:sub(2)
  end
  if text:sub(-3) == '）' then
    text = text:sub(1, -4)
  elseif text:sub(-1) == ')' then
    text = text:sub(1, -2)
  end
  return text
end

-- 取字符串首个字符（ASCII 或 UTF-8 多字节）
local function first_char(s)
  return s:match('^[%z\1-\127\194-\244][\128-\191]*')
end

-- UTF-8 字符串的字符数（Continuation Byte 不计）
local function uchar_count(s)
  return #s - select(2, s:gsub('[\128-\191]', ''))
end

-- 解析批注类型对应的颜色：主表 → 底本家族回退 → 前一条批注颜色 →
-- 兜底色；同时更新“前一条批注的颜色”，供无类型批注继承
local function resolve_color(typ)
  local color = nil
  if typ then
    -- 类型里的空白（含全角空格）不影响匹配
    typ = (typ:gsub('%s+', ''):gsub('　', ''))
    color = ZHIPI_COLORS[typ]
    if not color then
      for _, fam in ipairs(ZHIPI_FAMILIES) do
        if typ:sub(1, #fam[1]) == fam[1] then
          color = fam[2]
          break
        end
      end
    end
  end
  color = color or last_zhipi_color or ZHIPI_DEFAULT
  last_zhipi_color = color
  return color
end

-- 批注类型徽章样式：
-- 类型为 1~3 个字时，第 1 字渲染为“白字色底”徽章；
-- 类型为 2 个字时，第 2 字渲染为“色框色字”（白底）。
-- 更长的类型（如 甲回目标题）与无类型批注不做徽章，维持整体着色。
-- 仅在默认（去括号）模式下启用；ZHIPI_PARENS 保留括号时也保留
-- 旧的整体着色样式。宏 \zhipibg/\zhipiframe 定义见 latex/zhipi.tex。
function Code(el)
  local text = el.text
  if text:sub(1, 1) ~= '(' and text:sub(1, 3) ~= '（' then return nil end
  if not (text:match('%)%s*$') or text:match('）%s*$')) then return nil end
  if ZHIPI_HIDDEN then return {} end
  -- 首尾保留模式：批注取舍依赖段落级上下文，元素阶段不动作，
  -- 由 Pandoc 滤镜统一处理
  if ZHIPI_BODY_ONLY and not in_pandoc_phase then return nil end
  local typ = text:match('^%((.-)：') or text:match('^（(.-)：')
  local color = resolve_color(typ)
  -- 渲染时去掉首尾括号：颜色已足以区分批注与正文；
  -- 设置 ZHIPI_PARENS 则保留括号（含类型后的冒号）原样印出
  local plain = strip_parens(text)
  -- 拆分“类型：正文”，判断徽章样式是否适用
  local typ2, body = plain:match('^(.-)：(.*)$')
  local use_badge = false
  local keep_colon = false
  if not ZHIPI_PARENS and typ2 then
    local n = uchar_count(typ2)
    use_badge = n >= 1 and n <= 3
    -- 3 字及以上的类型（如 戚总评）：徽章只覆盖首字，余下类型字与正文
    -- 同样着色难以区分，保留类型后的全角冒号作分隔
    keep_colon = n >= 3
  end
  -- 默认模式渲染时去掉类型后的全角冒号（徽章已起标识作用），
  -- 但 3 字及以上类型保留冒号
  local display = (not ZHIPI_PARENS and typ2)
      and (typ2 .. (keep_colon and '：' or '') .. body) or plain
  local shown = ZHIPI_PARENS and el or pandoc.Code(display, el.attr)
  if FORMAT:match 'latex' then
    -- \textcolor/\fcolorbox 由 xcolor 宏包提供（latex/base.tex 已加载）
    local rgb = hex_to_rgb(color)
    if use_badge then
      local c1 = first_char(typ2)
      local rest = typ2:sub(#c1 + 1)
      local out = { pandoc.RawInline('latex',
        '\\zhipibg{' .. rgb .. '}{' .. c1 .. '}') }
      if uchar_count(typ2) == 2 then
        local c2 = first_char(rest)
        rest = rest:sub(#c2 + 1)
        out[#out + 1] = pandoc.RawInline('latex',
          '\\zhipiframe{' .. rgb .. '}{' .. c2 .. '}')
      end
      out[#out + 1] = pandoc.RawInline('latex',
        '\\textcolor[RGB]{' .. rgb .. '}{')
      out[#out + 1] = pandoc.Code(
        rest .. (keep_colon and '：' or '') .. body, el.attr)
      out[#out + 1] = pandoc.RawInline('latex', '}')
      return out
    end
    return { pandoc.RawInline('latex',
               '\\textcolor[RGB]{' .. rgb .. '}{'),
             shown,
             pandoc.RawInline('latex', '}') }
  elseif FORMAT:match 'html' or FORMAT:match 'epub' then
    if use_badge then
      -- HTML/EPUB 端的等效徽章：首字白字色底，第 2 字色框色字；
      -- 两个 span 用相同的 padding + border 宽度，保证边框一样大
      local c1 = first_char(typ2)
      local rest = typ2:sub(#c1 + 1)
      local out = { pandoc.Span({ pandoc.Code(c1, el.attr) },
        pandoc.Attr('', { 'zhipi', 'zhipi-bg' }, { style =
          'color:#fff;background-color:#' .. color ..
          ';border:0.6pt solid #' .. color .. ';padding:0 1.5pt' })) }
      if uchar_count(typ2) == 2 then
        local c2 = first_char(rest)
        rest = rest:sub(#c2 + 1)
        out[#out + 1] = pandoc.Span({ pandoc.Code(c2, el.attr) },
          pandoc.Attr('', { 'zhipi', 'zhipi-frame' }, { style =
            'color:#' .. color .. ';border:0.6pt solid #' .. color ..
            ';padding:0 1.5pt' }))
      end
      out[#out + 1] = pandoc.Span({ pandoc.Code(
          rest .. (keep_colon and '：' or '') .. body, el.attr) },
        pandoc.Attr('', { 'zhipi' }, { style = 'color:#' .. color }))
      return out
    end
    return pandoc.Span({ shown },
      pandoc.Attr('', { 'zhipi' }, { style = 'color:#' .. color }))
  end
  return shown
end

-- --- 嵌套批注（外层批注中夹内层批注） -------------------------------------
--
-- 个别批注的行内代码里又嵌套另一条批注，如第一回回首的庚辰本凡例文字
-- ```(庚：此开卷第一回也。……诚不若彼裙钗哉？```(蒙侧：何非梦幻……)```
-- 实愧则有馀……)```。pandoc 不支持行内代码嵌套：外层批注从内层的 ```
-- 处断开，整段被解析成“代码、普通文本、代码……”交替序列——外层碎成
-- 多个 Code 片段（不再满足批注形态，上面 Code 滤镜原样放行），内层批注
-- 落成普通文本原样印出，既无着色也无徽章。本滤镜在行内列表层面识别这
-- 种断开的序列并重新组装：
--   外层各片段按外层类型着色，首片段带类型徽章（徽章规则同 Code 滤镜）；
--   内层“（类型：…）”文本还原为 Code 复用 Code 滤镜的完整渲染。
-- 隐藏模式（ZHIPI_HIDE）下整条序列一并丢弃——若交给 Code 滤镜逐片段
-- 处理，碎片段会因不满足批注形态而漏进纯净版。

-- 外层批注的开头片段：以（开头、含“类型：”、但不以）结尾的行内代码
local function is_outer_start(el)
  if el.t ~= 'Code' then return false end
  local t = el.text
  if t:sub(1, 1) ~= '(' and t:sub(1, 3) ~= '（' then return false end
  if not t:match('^[（(].-：') then return false end
  return not (t:match('%)%s*$') or t:match('）%s*$'))
end

-- 内层批注的纯文本形态：完整的“（类型：…）”落在普通文本里
local function is_inner_text(s)
  return s:match('^[（(].-：') ~= nil
     and (s:match('%)$') or s:match('）$')) ~= nil
end

-- 已解析好颜色的批注文本片段（不含括号与徽章），PDF 与 HTML/EPUB 双端
local function colored_segment(text, color)
  if FORMAT:match 'latex' then
    return { pandoc.RawInline('latex',
               '\\textcolor[RGB]{' .. hex_to_rgb(color) .. '}{'),
             pandoc.Code(text),
             pandoc.RawInline('latex', '}') }
  elseif FORMAT:match 'html' or FORMAT:match 'epub' then
    return { pandoc.Span({ pandoc.Code(text) },
      pandoc.Attr('', { 'zhipi' }, { style = 'color:#' .. color })) }
  end
  return { pandoc.Code(text) }
end

-- 类型徽章（1~3 字类型）：首字“白字色底”，2 字类型的第 2 字“色框色字”；
-- 返回徽章 inline 列表与去掉徽章用字后的剩余类型文字。样式同 Code 滤镜
local function badge_inlines(typ, color)
  local rgb = hex_to_rgb(color)
  local c1 = first_char(typ)
  local rest = typ:sub(#c1 + 1)
  local out = {}
  if FORMAT:match 'latex' then
    out[1] = pandoc.RawInline('latex',
      '\\zhipibg{' .. rgb .. '}{' .. c1 .. '}')
    if uchar_count(typ) == 2 then
      local c2 = first_char(rest)
      rest = rest:sub(#c2 + 1)
      out[2] = pandoc.RawInline('latex',
        '\\zhipiframe{' .. rgb .. '}{' .. c2 .. '}')
    end
  else
    out[1] = pandoc.Span({ pandoc.Code(c1) },
      pandoc.Attr('', { 'zhipi', 'zhipi-bg' }, { style =
        'color:#fff;background-color:#' .. color ..
        ';border:0.6pt solid #' .. color .. ';padding:0 1.5pt' }))
    if uchar_count(typ) == 2 then
      local c2 = first_char(rest)
      rest = rest:sub(#c2 + 1)
      out[2] = pandoc.Span({ pandoc.Code(c2) },
        pandoc.Attr('', { 'zhipi', 'zhipi-frame' }, { style =
          'color:#' .. color .. ';border:0.6pt solid #' .. color ..
          ';padding:0 1.5pt' }))
    end
  end
  return out, rest
end

-- 把 Code 滤镜的返回值（inline、列表或 nil）并入 out 列表
local function append_rendered(out, r)
  if r == nil then return end
  if type(r) == 'table' and r.t then
    out[#out + 1] = r
  elseif type(r) == 'table' then
    for _, x in ipairs(r) do out[#out + 1] = x end
  end
end

-- 从 inls 的 i 处尝试扫描嵌套批注序列：外层 Code 片段与内层纯文本批注
-- 交替，直至某个外层 Code 片段以“）”结尾；成功返回片段列表 parts 与
-- 结束游标 j（指向下一个未消费的元素），失败返回 nil
local function scan_nested(inls, i)
  if not is_outer_start(inls[i]) then return nil end
  local parts = { { kind = 'outer', text = inls[i].text } }
  local j, closed = i + 1, false
  local n = #inls
  while j <= n do
    local e = inls[j]
    if e.t == 'Str' or e.t == 'Space' then
      -- 汇集一段连续普通文本，判作内层批注候选
      local txt = ''
      while j <= n and (inls[j].t == 'Str' or inls[j].t == 'Space') do
        txt = txt .. (inls[j].t == 'Space' and ' ' or inls[j].text)
        j = j + 1
      end
      if not is_inner_text(txt) then return nil end
      parts[#parts + 1] = { kind = 'inner', text = txt }
    elseif e.t == 'Code' then
      parts[#parts + 1] = { kind = 'outer', text = e.text }
      j = j + 1
      if e.text:match('%)%s*$') or e.text:match('）%s*$') then
        closed = true
        break
      end
    else
      return nil
    end
  end
  if not closed or #parts < 3 then return nil end
  return parts, j
end

-- 拆分批注的起始片段：以“（”开头、不以“）”结尾的行内代码。比
-- is_outer_start 宽松：不要求含“类型：”，无类型批注（如 032 回末
-- 总评“（袭人湘云黛玉宝钗等之爱之哭……）”）也可被脚注拆开
local function is_split_start(el)
  if el.t ~= 'Code' then return false end
  local t = el.text
  if t:sub(1, 1) ~= '(' and t:sub(1, 3) ~= '（' then return false end
  return not (t:match('%)%s*$') or t:match('）%s*$'))
end

-- 从 inls 的 i 处尝试扫描“被脚注拆开的批注”序列：外层起始 Code（以
-- “（”开头、不以“）”结尾）之后，脚注 Note 与不带“（”的续段
-- Code 交替，直至某续段 Code 以“）”结尾。用于在批注中间夹脚注的写法：
--   ```(戚：谁谓诗书鲜误人```[^042-1]```，豪华相尚失天真？……)```
-- 脚注记号不能写在行内代码里（pandoc 不解析代码内的 Markdown），只能把
-- 批注拆成两段代码、脚注夹在中间。成功返回片段列表 parts（outer/note
-- 两种）与结束游标 j，失败返回 nil。parts 与 scan_nested 同构，渲染复用
-- render_nested（note 片段原样输出脚注，不参与着色）
local function scan_split_note(inls, i)
  if not is_split_start(inls[i]) then return nil end
  local parts = { { kind = 'outer', text = inls[i].text } }
  local has_note = false
  local j, closed = i + 1, false
  local n = #inls
  while j <= n do
    local e = inls[j]
    if e.t == 'Note' then
      has_note = true
      parts[#parts + 1] = { kind = 'note', note = e }
      j = j + 1
    elseif e.t == 'Code' and not is_outer_start(e)
        and e.text:sub(1, 1) ~= '(' and e.text:sub(1, 3) ~= '（' then
      -- 续段：不带“（”的批注正文碎片（注意不能用字符类 [（(] 判断：
      -- Lua 模式按字节匹配，EF 起头的汉字如“，”会误判）
      parts[#parts + 1] = { kind = 'outer', text = e.text }
      j = j + 1
      if e.text:match('%)%s*$') or e.text:match('）%s*$') then
        closed = true
        break
      end
    else
      return nil
    end
  end
  if not closed or not has_note then return nil end
  return parts, j
end

-- 渲染嵌套批注序列：外层各片段按外层类型着色、首片段带徽章（规则同
-- Code 滤镜）；drop_inner=false 时内层批注还原为 Code 复用 Code 滤镜
-- 的完整渲染，drop_inner=true 时内层批注丢弃（首尾保留模式）；
-- note 片段（被脚注拆开的批注中夹的脚注）原样输出，不受 drop_inner 影响
local function render_nested(parts, drop_inner)
  local out = {}
  if ZHIPI_HIDDEN then return out end
  local typ = parts[1].text:match('^[（(](.-)：')
  local color = resolve_color(typ)
  for idx, part in ipairs(parts) do
    if part.kind == 'note' then
      out[#out + 1] = part.note
    elseif part.kind == 'inner' then
      if not drop_inner then
        append_rendered(out, Code(pandoc.Code(part.text)))
      end
    elseif ZHIPI_PARENS then
      -- 保留括号模式：片段原样着色印出
      append_rendered(out, colored_segment(part.text, color))
    elseif idx == 1 then
      -- 首片段：去首括号，类型出徽章（规则同 Code 滤镜）
      local head = part.text:gsub('^[（(]', '')
      local body = head:match('^.-：(.*)$') or head
      local m = typ and uchar_count(typ) or 0
      if m >= 1 and m <= 3 then
        local badges, rest = badge_inlines(typ, color)
        for _, b in ipairs(badges) do out[#out + 1] = b end
        append_rendered(out, colored_segment(
          rest .. (m >= 3 and '：' or '') .. body, color))
      else
        append_rendered(out, colored_segment(
          typ and (typ .. '：' .. body) or head, color))
      end
    elseif idx == #parts then
      -- 末片段：去尾括号
      append_rendered(out, colored_segment(
        (part.text:gsub('%)%s*$', ''):gsub('）%s*$', '')), color))
    else
      append_rendered(out, colored_segment(part.text, color))
    end
  end
  return out
end

-- pandoc 的滤镜遍历分先后两遍：行内元素级滤镜（Code）先走完整篇文档，
-- 行内列表级滤镜（Inlines）再走第二遍。到第二遍时 last_zhipi_color 已
-- 与文档顺序脱节（只剩嵌套/拆分批注自己解析过的颜色），无类型的拆分
-- 批注（如 032 回末总评）会继承不到前一条批注的颜色。因此 Inlines
-- 滤镜遍历时从第一遍的渲染产物中同步“前一条批注的颜色”：HTML/EPUB
-- 端为 zhipi 着色 span（徽章 span 不算），LaTeX 端为 \textcolor[RGB]
-- 开启标记
local function resync_last_color(el)
  if el.t == 'Span' and el.classes:includes('zhipi')
      and not el.classes:includes('zhipi-bg')
      and not el.classes:includes('zhipi-frame') then
    local hex = el.attributes.style
      and el.attributes.style:match('^color:#(%x%x%x%x%x%x)')
    if hex then last_zhipi_color = hex end
  elseif el.t == 'RawInline' and el.format == 'latex' then
    local r, g, b = el.text:match('^\\textcolor%[RGB%]{(%d+),(%d+),(%d+)}')
    if r then last_zhipi_color = string.format('%02x%02x%02x', r, g, b) end
  end
end

function Inlines(inls)
  -- 首尾保留模式下由 Pandoc 滤镜的分章遍历统一处理，此处不动作
  if ZHIPI_BODY_ONLY then return nil end
  local out = {}
  local i, n = 1, #inls
  while i <= n do
    local parts, j = scan_nested(inls, i)
    if not parts then parts, j = scan_split_note(inls, i) end
    if parts then
      for _, x in ipairs(render_nested(parts, false)) do
        out[#out + 1] = x
      end
      i = j
    else
      resync_last_color(inls[i])
      out[#out + 1] = inls[i]
      i = i + 1
    end
  end
  return out
end

-- --- 整段批注（回前批语、回末总评） ---------------------------------------
--
-- 内容全部落在批注里的段落（回前批语、回末总评及回中独立批注段）：加大
-- 字号并与正文拉开距离，便于区分。识别依据：段落行内元素中只有空白与
-- 批注渲染产物（HTML/EPUB 端为 zhipi 系列 span；LaTeX 端为 \zhipibg/
-- \zhipiframe/\textcolor 的 RawInline 及其包裹的批注正文 Code），不含
-- 任何正文文字（Str）。行内批注夹在正文里的段落不受影响；诗体行尾的
-- 批注已被 poetry-word 滤镜包上 verse-anno span（顶层不是 zhipi），也
-- 不会误判。HTML/EPUB 端把段落包进 <div class="zhipi-block">（样式见
-- css/cnbook.css），PDF 端包进 zhipiblock 环境（定义见 latex/zhipi.tex）。
--
-- 包块在 Pandoc 滤镜里手动遍历实现而不用 Para 滤镜：脚注里的整段批注
-- （如回目脚注中的“庚侧：当得起。”）不能包 zhipiblock 环境——\par 类
-- 环境夹在 \footnote→\texorpdfstring→\chapter 的移动参数里会导致
-- LaTeX 编译失败（Paragraph ended before \hypertarget was complete）；
-- Para 滤镜看不到父级上下文，故改为在 Pandoc 阶段自顶向下遍历块列表，
-- 不下钻进 Note（脚注），脚注内的批注段落只着色、不加整段样式。

-- 判定段落是否为整段批注（见上）
local function is_zhipi_para(b)
  if b.t ~= 'Para' and b.t ~= 'Plain' then return false end
  local has_zhipi = false
  for _, il in ipairs(b.content) do
    if il.t == 'Space' or il.t == 'SoftBreak' or il.t == 'LineBreak' then
      -- 空白不计
    elseif il.t == 'Note' then
      -- 整段批注末尾的脚注标记（如 042 回前批引文的校注）不视为正文
    elseif il.t == 'Span' and il.classes:includes('zhipi') then
      has_zhipi = true
    elseif il.t == 'RawInline' and il.format == 'latex'
        and il.text:match('zhipi[bf][gr]') then
      -- \zhipibg / \zhipiframe 徽章
      has_zhipi = true
    elseif il.t == 'RawInline' and il.format == 'latex'
        and il.text:match('textcolor') then
      -- \textcolor[RGB]{…}{ 着色开启标记
      has_zhipi = true
    elseif il.t == 'RawInline' and il.format == 'latex'
        and il.text:match('^}%s*$') then
      -- \textcolor 的闭合括号
    elseif il.t == 'Code' and has_zhipi then
      -- LaTeX 端批注正文的 Code 片段（跟在 \textcolor 开启标记之后）
    else
      return false  -- 含正文文字或其他元素，不是整段批注
    end
  end
  return has_zhipi
end

-- 递归遍历块列表，包装整段批注段落（不下钻 Note；表格、定义列表等
-- 容器中的段落不处理——批注不落在其中）。连续的整段批注合并为一组：
-- 只有整组与正文相邻的首尾两处拉开距离，组内各批注段之间保持与正文
-- 段落一致的正常段距
local function wrap_zhipi_blocks(blocks)
  local out = {}
  local i, n = 1, #blocks
  while i <= n do
    local b = blocks[i]
    if b.t == 'Div' or b.t == 'BlockQuote' then
      b.content = wrap_zhipi_blocks(b.content)
      out[#out + 1] = b
      i = i + 1
    elseif b.t == 'BulletList' or b.t == 'OrderedList' then
      for k, item in ipairs(b.content) do
        b.content[k] = wrap_zhipi_blocks(item)
      end
      out[#out + 1] = b
      i = i + 1
    elseif is_zhipi_para(b) then
      local group = { b }
      local j = i + 1
      while j <= n and is_zhipi_para(blocks[j]) do
        group[#group + 1] = blocks[j]
        j = j + 1
      end
      if FORMAT:match 'latex' then
        out[#out + 1] = pandoc.RawBlock('latex', '\\begin{zhipiblock}')
        for _, g in ipairs(group) do out[#out + 1] = g end
        out[#out + 1] = pandoc.RawBlock('latex', '\\end{zhipiblock}')
      elseif FORMAT:match 'html' or FORMAT:match 'epub' then
        out[#out + 1] = pandoc.Div(group, pandoc.Attr('', { 'zhipi-block' }))
      else
        for _, g in ipairs(group) do out[#out + 1] = g end
      end
      i = j
    else
      out[#out + 1] = b
      i = i + 1
    end
  end
  return out
end

function Pandoc(doc)
  in_pandoc_phase = true
  if ZHIPI_BODY_ONLY then
    doc.blocks = body_only_blocks(doc.blocks)
  else
    doc.blocks = wrap_zhipi_blocks(doc.blocks)
  end
  return doc
end

-- --- 首尾保留模式（ZHIPI_BODY_ONLY） ---------------------------------------
--
-- 只去掉夹在正文中的批注，保留回目之后、正文之前的回前批语与正文之后的
-- 回末总评（整段批注），整段批注照常着色并包 zhipi-block；其中嵌套的内
-- 层批注（如 001 回首庚辰凡例中夹的蒙府侧批）一并去掉，只留外层文字。
-- 回目本身（Header）中的批注与脚注（校注）里的批注保留。
--
-- 该模式下 Code/Inlines 滤镜在 pandoc 遍历时均不动作（批注取舍依赖段落
-- 级上下文，元素级拿不到），统一在这里分章遍历处理：按一级标题分章，
-- 每章以“含普通文字的正文块”（整段批注、RawBlock、Header 等不算）划
-- 出正文区，正文区之前/之后为首尾保留区。

-- 脚注内容里的批注照常着色
local render_annos_inlines  -- 前置声明（与 map_note_annos 互递归）
local function map_note_annos(content)
  for _, b in ipairs(content) do
    if b.t == 'Para' or b.t == 'Plain' then
      b.content = render_annos_inlines(b.content)
    end
  end
  return content
end

-- 渲染行内列表中的批注：完整批注 Code 走 Code 滤镜渲染；嵌套序列只保留
-- 外层（内层批注丢弃）；脚注里的批注递归渲染；Quoted/Emph/Strong/Span
-- 等行内容器（smart 标点会产生 Quoted）递归下钻
local INLINE_CONTAINERS = {
  Quoted = true, Emph = true, Strong = true, Strikeout = true,
  Superscript = true, Subscript = true, SmallCaps = true,
  Span = true, Link = true,
}

render_annos_inlines = function(inls)
  local out = {}
  local i, n = 1, #inls
  while i <= n do
    local el = inls[i]
    local parts, j = scan_nested(inls, i)
    if not parts then parts, j = scan_split_note(inls, i) end
    if parts then
      for _, x in ipairs(render_nested(parts, true)) do
        out[#out + 1] = x
      end
      i = j
    elseif el.t == 'Code' then
      append_rendered(out, Code(el))
      i = i + 1
    elseif el.t == 'Note' then
      el.content = map_note_annos(el.content)
      out[#out + 1] = el
      i = i + 1
    elseif INLINE_CONTAINERS[el.t] then
      el.content = render_annos_inlines(el.content)
      out[#out + 1] = el
      i = i + 1
    else
      out[#out + 1] = el
      i = i + 1
    end
  end
  return out
end

-- 丢弃行内列表中夹在正文里的批注：完整批注 Code 与嵌套序列整条丢弃；
-- 脚注本身保留（其中批注照常着色）；Quoted/Emph/Strong/Span 等行内容器
-- 递归下钻（smart 标点会把引号区段解析为 Quoted，批注可能落在其中）
local function drop_body_annos(inls)
  local out = {}
  local i, n = 1, #inls
  while i <= n do
    local el = inls[i]
    local parts, j = scan_nested(inls, i)
    if not parts then parts, j = scan_split_note(inls, i) end
    if parts then
      i = j  -- 嵌套批注、被脚注拆开的批注整条丢弃（夹在中间的脚注
             -- 是针对批注的校注，批注去掉后无所依附，一并丢弃）
    elseif el.t == 'Code' and el.text:match('^[（(]') then
      i = i + 1  -- 完整批注丢弃
    elseif el.t == 'Note' then
      el.content = map_note_annos(el.content)
      out[#out + 1] = el
      i = i + 1
    elseif INLINE_CONTAINERS[el.t] then
      el.content = drop_body_annos(el.content)
      out[#out + 1] = el
      i = i + 1
    else
      out[#out + 1] = el
      i = i + 1
    end
  end
  return out
end

-- 判定源码形态的段落是否为整段批注：行内元素只有空白、批注 Code
-- （含嵌套批注断开后的外层片段）、嵌套内层批注的纯文本与脚注标记
-- （如 042 回前批末尾的校注脚注）
local function is_raw_anno_para(b)
  if b.t ~= 'Para' and b.t ~= 'Plain' then return false end
  local has = false
  local in_nested = false
  for _, il in ipairs(b.content) do
    if il.t == 'Space' or il.t == 'SoftBreak' or il.t == 'LineBreak' then
      -- 空白不计
    elseif il.t == 'Note' then
      -- 脚注标记不计
    elseif il.t == 'Code' and (il.text:match('^[（(]') or in_nested) then
      has = true
      if il.text:match('^[（(]') and not il.text:match('[）)]%s*$') then
        in_nested = true   -- 嵌套外层开始
      elseif in_nested and il.text:match('[）)]%s*$') then
        in_nested = false  -- 嵌套结束
      end
    elseif il.t == 'Str' and in_nested and is_inner_text(il.text) then
      -- 嵌套内层批注的纯文本
    else
      return false
    end
  end
  return has
end

-- 递归处理表格各单元格（批注可能落在表格引文中，如难字表的上下文）
local function map_table(tbl, fn)
  local function map_rows(rows)
    for _, row in ipairs(rows or {}) do
      for _, cell in ipairs(row.cells or row) do
        fn(cell.content or cell)
      end
    end
  end
  map_rows(tbl.head and tbl.head.rows)
  for _, body in ipairs(tbl.bodies or {}) do
    map_rows(body.body)
  end
  map_rows(tbl.foot and tbl.foot.rows)
  return tbl
end

-- 首尾部区块：批注照常渲染（递归下钻 Div/引用块/列表/表格；脚注由
-- render_annos_inlines 处理）
local function render_blocks_annos(blocks)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == 'Para' or b.t == 'Plain' or b.t == 'Header' then
      b.content = render_annos_inlines(b.content)
    elseif b.t == 'Div' or b.t == 'BlockQuote' then
      b.content = render_blocks_annos(b.content)
    elseif b.t == 'BulletList' or b.t == 'OrderedList' then
      for k, item in ipairs(b.content) do
        b.content[k] = render_blocks_annos(item)
      end
    elseif b.t == 'Table' then
      map_table(b, function(cell) render_blocks_annos(cell) end)
    end
    out[#out + 1] = b
  end
  return out
end

-- 正文区区块：丢弃批注（递归下钻 Div/引用块/列表/表格）；
-- 回目（Header）中的批注保留
local function drop_blocks_annos(blocks)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == 'Para' or b.t == 'Plain' then
      b.content = drop_body_annos(b.content)
    elseif b.t == 'Header' then
      b.content = render_annos_inlines(b.content)
    elseif b.t == 'Div' or b.t == 'BlockQuote' then
      b.content = drop_blocks_annos(b.content)
    elseif b.t == 'BulletList' or b.t == 'OrderedList' then
      for k, item in ipairs(b.content) do
        b.content[k] = drop_blocks_annos(item)
      end
    elseif b.t == 'Table' then
      map_table(b, function(cell) drop_blocks_annos(cell) end)
    end
    out[#out + 1] = b
  end
  return out
end

-- 处理一章（一级标题划分）：划出正文区；首尾部区块批注照常渲染，
-- 其中连续的整段批注分组包 zhipi-block；正文区批注丢弃
local function body_only_section(blocks)
  local first_text, last_text = nil, nil
  for i, b in ipairs(blocks) do
    local neutral = b.t == 'RawBlock' or b.t == 'HorizontalRule'
                    or b.t == 'Header'
    if not neutral and not is_raw_anno_para(b) then
      first_text = first_text or i
      last_text = i
    end
  end
  local out = {}
  local pending = {}  -- 待分组包块的连续整段批注
  local function flush()
    if #pending > 0 then
      for _, x in ipairs(wrap_zhipi_blocks(pending)) do
        out[#out + 1] = x
      end
      pending = {}
    end
  end
  for i, b in ipairs(blocks) do
    local keep_zone = (first_text ~= nil and i < first_text)
                      or (last_text ~= nil and i > last_text)
    if is_raw_anno_para(b) then
      if keep_zone then
        b.content = render_annos_inlines(b.content)
        pending[#pending + 1] = b
      end
      -- 正文区的整段批注丢弃
    else
      flush()
      if keep_zone then
        out[#out + 1] = render_blocks_annos({ b })[1]
      else
        out[#out + 1] = drop_blocks_annos({ b })[1]
      end
    end
  end
  flush()
  return out
end

-- 按一级标题分章，逐章处理
function body_only_blocks(blocks)
  local sections = {}
  local cur = {}
  for _, b in ipairs(blocks) do
    if b.t == 'Header' and b.level == 1 and #cur > 0 then
      sections[#sections + 1] = cur
      cur = {}
    end
    cur[#cur + 1] = b
  end
  sections[#sections + 1] = cur
  local out = {}
  for _, sec in ipairs(sections) do
    for _, b in ipairs(body_only_section(sec)) do out[#out + 1] = b end
  end
  return out
end
