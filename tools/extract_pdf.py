#!/usr/bin/env python3
# tools/extract_pdf.py
# 解析 doc/卢麒元文集 2001-2025.pdf，生成 chat/ 下的 bookdown 章节 Rmd。
#
# 结构：书签大纲扁平，*YYYY 为年份分册标记，其后书签为该年文章。
# 文章不一定另起一页——同一页可能依次排有多篇（标题行 + 日期行 + 正文），
# 因此不能按页码区间切分，须按“标题行位置”在连续行流中切分。
# 标题在版面上可能竖排被拆成多行，拼接（去空白）后与书签标题相等即命中。
# 行尾空格 + \n = 段落结束；无尾空格 = 硬换行。页脚为连续书页码（纯数字行）。
#
# 用法：python3 tools/extract_pdf.py [--date-source]
#   --date-source  可选特性：标题后第一行若为“日期 + 出处”（如
#                  “2006-10-10 香港商报”），整行也作日期行处理（.hline）。
# 首次运行会把逐页文本缓存到 doc/<PDF文件名>.pages-cache.json（与
# pdf-to-bookdown skill 同一约定），之后重跑秒级完成。

import argparse
import json
import os
import re
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF = os.path.join(ROOT, 'doc', '卢麒元文集 2001-2025.pdf')
CACHE = os.path.join(ROOT, 'doc', '卢麒元文集 2001-2025.pdf.pages-cache.json')
OUT = os.path.join(ROOT, 'chat')

# ---- 部首字符规范化 -------------------------------------------------------
# Pages 导出的 PDF 中，部分独体字被替换为康熙部首（U+2F00–2FDF）或
# 部首补充块（U+2E80–2EFF）字符。康熙块用 NFKC 即可映射回统一表意文字；
# 补充块 NFKC 无效，需手工映射（已按上下文逐一核实）；个别 NFKC 结果
# 是繁体形（书稿为简体），也列入覆盖表。⻑ 见于繁体引文《史记》，映射为長。
RADICAL_OVERRIDES = {
    '⺠': '民', '⺩': '王', '⺫': '目', '⺴': '网',
    '⻁': '虎', '⻄': '西', '⻅': '见', '⻆': '角',
    '⻉': '贝', '⻋': '车', '⻑': '長', '⻓': '长',
    '⻔': '门', '⻘': '青', '⻙': '韦', '⻛': '风',
    '⻜': '飞', '⻝': '食', '⻢': '马', '⻥': '鱼',
    '⻦': '鸟', '⻩': '黄', '⻬': '齐', '⻰': '龙',
    # NFKC 得到繁体形的，按简体书稿覆盖
    '⾞': '车', '⾵': '风', '⾙': '贝', '⿂': '鱼', '⿈': '黄', '⿓': '龙',
}

def norm(text):
    out = []
    for ch in text:
        o = ord(ch)
        if 0x2E80 <= o <= 0x2EFF or 0x2F00 <= o <= 0x2FDF:
            out.append(RADICAL_OVERRIDES.get(ch) or unicodedata.normalize('NFKC', ch))
        else:
            out.append(ch)
    return ''.join(out)

# ---- 页面文本（带缓存） ---------------------------------------------------

def page_texts():
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    from pypdf import PdfReader
    r = PdfReader(PDF)
    texts = [(p.extract_text() or '') for p in r.pages]
    with open(CACHE, 'w') as f:
        json.dump(texts, f, ensure_ascii=False)
    return texts

def outline():
    from pypdf import PdfReader
    r = PdfReader(PDF)
    items = []

    def walk(o):
        for it in o:
            if isinstance(it, list):
                walk(it)
            else:
                items.append((it.title, r.get_destination_page_number(it)))

    walk(r.outline)
    return items

# ---- 行流与标题定位 -------------------------------------------------------

DATE_RE = re.compile(r'^\d{4}-\d{1,2}-\d{1,2}$')
# 日期行扩展形式（可选，--date-source 启用）：日期 + 出处
# （如 “2006-10-10 香港商报”），可再带圆括号副标题前缀
# （如 “（从保尔森访华看中美关系二之一）2006-12-13 香港商报”）
DATE_SRC_RE = re.compile(
    r'^(?:（[^）]*）\s*)?\d{4}-\d{1,2}-\d{1,2}(?:\s+\S.*)?$')
PAGE_NO_RE = re.compile(r'^\d{1,4}$')

def year_lines(pages):
    """把一年的若干页文本转成 [(text, para_end)] 行流，去页脚、去年份标记。"""
    lines = []
    for t in pages:
        raw = t.split('\n')
        for i, ln in enumerate(raw):
            para_end = ln.endswith(' ')
            s = norm(ln.strip())
            if not s:
                continue
            if (i == 0 or i == len(raw) - 1) and PAGE_NO_RE.match(s):
                continue
            lines.append([s, para_end])
    return lines

def find_title(lines, title, start, date_source=False):
    """从 start 起找标题行位置。标题可能被竖排拆成多行（极端情况逐字一行），
    拼接（去空白）后与书签标题完全相等才算命中。
    竖排标题里 广 会被 Pages 写成部首 ⼲（=干），比较时把 广 折叠为 干。
    date_source=True 时，标题后第一行若为“日期 + 出处”（如
    “2006-10-10 香港商报”），整行作为日期行处理。
    返回 (match_start, content_start, date)：标题首行、正文首行、日期。"""
    fold = lambda s: re.sub(r'\s+', '', s).replace('广', '干')
    tnorm = fold(title)
    for j in range(start, len(lines)):
        acc = ''
        for k in range(j, min(j + 40, len(lines))):
            acc += re.sub(r'\s+', '', lines[k][0])
            if fold(acc) == tnorm:
                end = k + 1
                date = ''
                if end < len(lines):
                    if DATE_RE.match(lines[end][0]):
                        date = lines[end][0]
                        end += 1
                    elif date_source and DATE_SRC_RE.match(lines[end][0]):
                        date = re.sub(r'\s+', ' ', lines[end][0])
                        end += 1
                return j, end, date
            if len(acc) > len(tnorm):
                break
    return None, None, ''

def merge_paras(lines):
    paras, cur = [], []
    for s, para_end in lines:
        cur.append(s)
        if para_end:
            paras.append(''.join(cur))
            cur = []
    if cur:
        paras.append(''.join(cur))
    return paras

# 段落兜底：部分文章（讲座实录等）段落结束缺少行尾空格标记，或标记
# 在文内不稳定，按空格规则会粘成数千字符的一段。若最长段超过阈值，
# 改用混合规则重组：行尾空格 或 行尾为句末标点，均视为段落结束。
FALLBACK_MAX = 1200
SENT_END = tuple('。！？；…”’」』!?')

def merge_paras_fallback(lines):
    paras, cur = [], []
    for s, para_end in lines:
        cur.append(s)
        if para_end or s.endswith(SENT_END):
            paras.append(''.join(cur))
            cur = []
    if cur:
        paras.append(''.join(cur))
    return paras

def smart_paras(lines):
    paras = merge_paras(lines)
    if paras and max(len(p) for p in paras) > FALLBACK_MAX:
        alt = merge_paras_fallback(lines)
        if max(len(p) for p in alt) < max(len(p) for p in paras):
            return alt
    return paras

# 源文档中的零星排版杂质，按精确串修正
CLEANUPS = [
    ('《读<</span>政治经济学教科书>（社会主义部分）笔记》',
     '《读〈政治经济学教科书〉（社会主义部分）笔记》'),
]

def cleanup(text):
    for old, new in CLEANUPS:
        text = text.replace(old, new)
    return text

# ---- 文件名 ---------------------------------------------------------------

# bookdown 的 check_special_chars 不接受文件名中的 ASCII 空格及标点，
# 全部替换为 -（全角标点如 《》：，不受影响）
BAD_FN = re.compile(r'[ -/:-@\[-`{-~]+')

def safe_name(s):
    return BAD_FN.sub('-', s).strip('-.')

# ---- 主流程 ---------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        prog='extract_pdf',
        description='解析 doc/卢麒元文集 2001-2025.pdf 生成 chat/ 章节 Rmd')
    ap.add_argument('--date-source', action='store_true',
                    help='标题后第一行若为“日期 + 出处”（如 2006-10-10 '
                         '香港商报），整行作为日期行（.hline）处理')
    args = ap.parse_args()

    items = outline()
    pages = page_texts()
    npages = len(pages)

    # 分年分组：书签 (title, page)
    parts = []  # [(year, [title, ...])]
    year = None
    for t, p in items:
        if t.startswith('*') and t[1:].isdigit():
            parts.append((t[1:], p, []))
            year = t[1:]
        else:
            parts[-1][2].append((t, p))

    # 清理旧的章节文件（保留 index.Rmd / 00-author.Rmd 等手工文件）
    for f in os.listdir(OUT):
        if re.match(r'^\d{4}-\d{2}', f):
            os.remove(os.path.join(OUT, f))

    nfiles, problems = 0, []
    for pi, (year, ystart, arts) in enumerate(parts):
        yend = parts[pi + 1][1] if pi + 1 < len(parts) else npages
        lines = year_lines(pages[ystart:yend])
        # 跳过年份标记行
        if lines and lines[0][0] == '*' + year:
            lines.pop(0)

        # 依次定位各篇标题
        pos, cursor = [], 0
        for title, _p in arts:
            tstart, cstart, date = find_title(lines, title, cursor,
                                              date_source=args.date_source)
            if tstart is None:
                problems.append(('TITLE NOT FOUND', year, title))
                pos.append((None, None, None))
            else:
                pos.append((tstart, cstart, date))
                cursor = cstart

        # 首个分册页带 \mainmatter：preamble.tex 以 \frontmatter 收尾，
        # 正文从此进入阿拉伯页码、章节编号模式
        part_head = '\\mainmatter\n\n' if pi == 0 else ''
        with open(os.path.join(OUT, f'{year}-00.Rmd'), 'w') as f:
            f.write(f'{part_head}# (PART) {year} {{-}}\n\n')

        for k, (title, _p) in enumerate(arts):
            _ts, start, date = pos[k]
            if start is None:
                problems.append(('SKIPPED', year, title))
                continue
            # 正文止于下一篇标题的首行
            nxt = None
            for m in range(k + 1, len(arts)):
                if pos[m][0] is not None:
                    nxt = pos[m][0]
                    break
            seg_end = nxt if nxt is not None else len(lines)
            paras = [cleanup(p) for p in smart_paras(lines[start:seg_end])]
            if not paras:
                problems.append(('EMPTY', year, title))
            body = [f'# {title}\n']
            if date:
                body.append(f'\n[{date}]{{.hline align=right}}\n')
            for p in paras:
                body.append(f'\n{p}\n')
            fn = f'{year}-{k + 1:02d}-{safe_name(title)}.Rmd'
            with open(os.path.join(OUT, fn), 'w') as f:
                f.write(''.join(body))
            nfiles += 1

    print(f'years: {len(parts)}, articles written: {nfiles}')
    for year, _s, arts in parts:
        print(f'  {year}: {len(arts)}')
    if problems:
        print('PROBLEMS:')
        for x in problems:
            print(' ', x)

if __name__ == '__main__':
    main()
