#!/usr/bin/env python3
"""pdf2book.py — 把带书签大纲的 PDF 文集转成 bookdown 图书工程

一条命令完成三件事（均可单独关闭）：

  1. scaffold：在项目根目录生成 Makefile/VERSION，在书稿目录生成
     _bookdown.yml、_output.yml、.Rprofile、latex/、css/、index.Rmd、
     附录（hmm.Rmd、references.Rmd），同步 cnbook 排版包，导出封面
  2. extract：按书签大纲把 PDF 切分为 分册页 + 章节 Rmd
  3. format：调用 cn-doc-format 的 zhformat.py 做中文排版规范化

用法：

  python3 pdf2book.py --pdf "文集.pdf" --dir 项目根目录 --name 书稿目录名 \
      --title "书名" --author "作者"

  # 只重新提取（工程已存在时）
  python3 pdf2book.py --pdf "文集.pdf" --name 书稿目录名 --no-scaffold --no-format

依赖：pypdf（提取）；scaffold 的 cnbook/封面步骤在缺工具时自动降级跳过。

分册识别：书签标题匹配 --part-regex（默认 ^\\*(\\d{4})$，即 *2001 这种
年份标记）。命中者为分册（PART），其后书签为该分册下的章节。

提取要点（Pages/Word 导出的中文版 PDF 常见问题均已处理）：

  - 文章不一定另起一页，按"标题行位置"在连续行流中切分，不按页码区间
  - 标题竖排可能被拆成多行（极端逐字一行），拼接去空白后与书签相等即命中
  - 独体字常被替换为康熙部首/部首补充字符（⼈⺠→人民），内置映射表归一
  - 行尾"空格+换行"= 段落结束；无标记的文章按句末标点兜底
  - 页首/页尾纯数字行为书页码，剔除
  - 文件名中的 ASCII 空格与标点替换为 -（bookdown 不接受）
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATES = os.path.join(SKILL_DIR, 'templates')

# ---------------------------------------------------------------------------
# 部首字符归一（Pages 导出的 PDF 把独体字写成部首字符）
# ---------------------------------------------------------------------------

RADICAL_OVERRIDES = {
    '⺠': '民', '⺩': '王', '⺫': '目', '⺴': '网',
    '⻁': '虎', '⻄': '西', '⻅': '见', '⻆': '角',
    '⻉': '贝', '⻋': '车', '⻑': '長', '⻓': '长',
    '⻔': '门', '⻘': '青', '⻙': '韦', '⻛': '风',
    '⻜': '飞', '⻝': '食', '⻢': '马', '⻥': '鱼',
    '⻦': '鸟', '⻩': '黄', '⻬': '齐', '⻰': '龙',
    # NFKC 得到繁体形的，按简体覆盖
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

# ---------------------------------------------------------------------------
# PDF 读取（逐页文本带缓存）
# ---------------------------------------------------------------------------

def load_pages(pdf_path):
    cache = pdf_path + '.pages-cache.json'
    if os.path.exists(cache):
        with open(cache) as f:
            return json.load(f)
    from pypdf import PdfReader
    r = PdfReader(pdf_path)
    texts = [(p.extract_text() or '') for p in r.pages]
    with open(cache, 'w') as f:
        json.dump(texts, f, ensure_ascii=False)
    return texts

def load_outline(pdf_path):
    from pypdf import PdfReader
    r = PdfReader(pdf_path)
    items = []

    def walk(o):
        for it in o:
            if isinstance(it, list):
                walk(it)
            else:
                items.append((it.title, r.get_destination_page_number(it)))

    walk(r.outline)
    return items

# ---------------------------------------------------------------------------
# 行流切分
# ---------------------------------------------------------------------------

DATE_RE = re.compile(r'^\d{4}-\d{1,2}-\d{1,2}$')
# 日期行扩展形式（可选，--date-source 启用）：日期 + 出处
# （如 “2006-10-10 香港商报”），可再带圆括号副标题前缀
# （如 “（从保尔森访华看中美关系二之一）2006-12-13 香港商报”）
DATE_SRC_RE = re.compile(
    r'^(?:（[^）]*）\s*)?\d{4}-\d{1,2}-\d{1,2}(?:\s+\S.*)?$')
PAGE_NO_RE = re.compile(r'^\d{1,4}$')

def part_lines(pages):
    """若干页文本 → [(text, para_end)] 行流，去页脚。"""
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
    """从 start 起定位标题（竖排可能拆多行）。竖排标题里 广 常被写成
    部首 ⼲（=干），比较时把 广 折叠为 干。
    date_source=True 时，标题后第一行若为“日期 + 出处”（如
    “2006-10-10 香港商报”），整行作为日期行处理。
    返回 (标题首行, 正文首行, 日期)。"""
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

# 段落兜底：无行尾空格标记的文章按句末标点重组
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

# 文件名净化：bookdown 的 check_special_chars 不接受 ASCII 空格和标点
BAD_FN = re.compile(r'[ -/:-@\[-`{-~]+')

def safe_name(s):
    return BAD_FN.sub('-', s).strip('-.')

# ---------------------------------------------------------------------------
# 提取主流程
# ---------------------------------------------------------------------------

def extract(pdf_path, book_dir, part_regex, date_source=False):
    items = load_outline(pdf_path)
    pages = load_pages(pdf_path)
    npages = len(pages)
    part_re = re.compile(part_regex)

    parts = []  # [(分册名, 起始页, [(标题, 页码), ...])]
    for t, p in items:
        m = part_re.match(t)
        if m:
            parts.append((m.group(1), p, []))
        elif parts:
            parts[-1][2].append((t, p))
    if not parts:
        print('错误：书签大纲中没有匹配的分册标记', file=sys.stderr)
        return 1

    # 清理旧的生成文件（分册页 + 章节，均以“分册名-”开头）
    prefixes = tuple(p + '-' for p, _s, _a in parts)
    for f in os.listdir(book_dir):
        if f.endswith('.Rmd') and f.startswith(prefixes):
            os.remove(os.path.join(book_dir, f))

    nfiles, problems = 0, []
    for pi, (part, pstart, arts) in enumerate(parts):
        pend = parts[pi + 1][1] if pi + 1 < len(parts) else npages
        lines = part_lines(pages[pstart:pend])
        if lines and lines[0][0].lstrip('*') == part:
            lines.pop(0)

        pos, cursor = [], 0
        for title, _p in arts:
            tstart, cstart, date = find_title(lines, title, cursor,
                                              date_source=date_source)
            if tstart is None:
                problems.append(('TITLE NOT FOUND', part, title))
                pos.append((None, None, None))
            else:
                pos.append((tstart, cstart, date))
                cursor = cstart

        # 首个分册页带 \mainmatter（preamble 以 \frontmatter 收尾）
        head = '\\mainmatter\n\n' if pi == 0 else ''
        with open(os.path.join(book_dir, f'{part}-00.Rmd'), 'w') as f:
            f.write(f'{head}# (PART) {part} {{-}}\n\n')

        for k, (title, _p) in enumerate(arts):
            _ts, start, date = pos[k]
            if start is None:
                continue
            nxt = next((pos[m][0] for m in range(k + 1, len(arts))
                        if pos[m][0] is not None), len(lines))
            paras = smart_paras(lines[start:nxt])
            if not paras:
                problems.append(('EMPTY', part, title))
            body = [f'# {title}\n']
            if date:
                body.append(f'\n[{date}]{{.hline align=right}}\n')
            for p in paras:
                body.append(f'\n{p}\n')
            fn = f'{part}-{k + 1:02d}-{safe_name(title)}.Rmd'
            with open(os.path.join(book_dir, fn), 'w') as f:
                f.write(''.join(body))
            nfiles += 1

    print(f'分册: {len(parts)}, 章节: {nfiles}')
    for part, _s, arts in parts:
        print(f'  {part}: {len(arts)}')
    if problems:
        print('待人工核查:')
        for x in problems:
            print(' ', x)
    return 0

# ---------------------------------------------------------------------------
# 工程骨架
# ---------------------------------------------------------------------------

def render_template(name, mapping):
    with open(os.path.join(TEMPLATES, name)) as f:
        text = f.read()
    for k, v in mapping.items():
        text = text.replace(f'@@{k}@@', v)
    return text

def write_if_absent(path, content, force=False):
    if os.path.exists(path) and not force:
        print(f'  跳过（已存在）: {path}')
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(content)
    print(f'  生成: {path}')

def scaffold(args):
    root = os.path.abspath(args.dir)
    book = os.path.join(root, args.name)
    today = datetime.date.today().isoformat()
    mapping = {
        'NAME': args.name,
        'TITLE': args.title,
        'AUTHOR': args.author,
        'DATE': today,
        'VERSION': 'v1.0.0',
        'MOTTO': args.motto,
        'PDF': os.path.relpath(os.path.abspath(args.pdf), root),
        'PDF2BOOK': os.path.relpath(os.path.abspath(__file__), root),
        'ZHFORMAT': args.zhformat or '',
        'CNBOOK': args.cnbook,
        'EXTRACT_FLAGS': '--date-source' if args.date_source else '',
    }

    print('工程骨架:')
    write_if_absent(os.path.join(root, 'VERSION'), 'v1.0.0\n')
    write_if_absent(os.path.join(root, 'Makefile'),
                    render_template('Makefile', mapping))
    os.makedirs(book, exist_ok=True)
    write_if_absent(os.path.join(book, '_bookdown.yml'),
                    render_template('_bookdown.yml', mapping))
    write_if_absent(os.path.join(book, '_output.yml'),
                    render_template('_output.yml', mapping))
    write_if_absent(os.path.join(book, '.Rprofile'),
                    render_template('Rprofile', mapping))
    write_if_absent(os.path.join(book, 'index.Rmd'),
                    render_template('index.Rmd', mapping))
    for tex in ('preamble.tex', 'before_body.tex', 'after_body.tex',
                'template.tex'):
        write_if_absent(os.path.join(book, 'latex', tex),
                        render_template(tex, mapping))
    write_if_absent(os.path.join(book, 'css', 'style.css'),
                    render_template('style.css', mapping))
    if not args.no_appendix:
        write_if_absent(os.path.join(book, 'hmm.Rmd'),
                        render_template('hmm.Rmd', mapping))
        write_if_absent(os.path.join(book, 'references.Rmd'),
                        render_template('references.Rmd', mapping))

    # cnbook 排版包副本
    if os.path.isdir(args.cnbook):
        for sub, pat in (('lua/cnbook', '*.lua'), ('latex/cnbook', '*.tex')):
            dst = os.path.join(book, sub)
            os.makedirs(dst, exist_ok=True)
            import glob
            for src in glob.glob(os.path.join(args.cnbook,
                                              sub.split('/')[0], pat)):
                shutil.copy(src, dst)
        os.makedirs(os.path.join(book, 'css'), exist_ok=True)
        shutil.copy(os.path.join(args.cnbook, 'css', 'cnbook.css'),
                    os.path.join(book, 'css', 'cnbook.css'))
        print(f'  cnbook 副本已同步: {args.cnbook}')
    else:
        print(f'  警告：cnbook 目录不存在（{args.cnbook}），'
              f'请手工同步 lua/latex/css 排版包', file=sys.stderr)

    # 封面：macOS 用 sips 取 PDF 首页
    cover = os.path.join(book, 'images', 'cover.png')
    if not os.path.exists(cover) and shutil.which('sips'):
        os.makedirs(os.path.dirname(cover), exist_ok=True)
        r = subprocess.run(['sips', '-s', 'format', 'png', args.pdf,
                            '--out', cover], capture_output=True)
        if r.returncode == 0:
            print(f'  封面: {cover}')

def run_format(book_dir, zhformat):
    if not zhformat or not os.path.exists(zhformat):
        print('警告：未找到 zhformat.py，跳过排版格式化', file=sys.stderr)
        return
    r = subprocess.run([sys.executable, zhformat, '-i', book_dir])
    if r.returncode != 0:
        print('警告：zhformat 执行失败', file=sys.stderr)

def main(argv=None):
    ap = argparse.ArgumentParser(
        prog='pdf2book',
        description='把带书签大纲的 PDF 文集转成 bookdown 图书工程')
    ap.add_argument('--pdf', required=True, help='源 PDF 路径')
    ap.add_argument('--dir', default='.', help='项目根目录（默认当前目录）')
    ap.add_argument('--name', required=True,
                    help='书稿目录名，也是 book_filename（如 chat）')
    ap.add_argument('--title', default='未命名文集', help='书名')
    ap.add_argument('--author', default='', help='作者')
    ap.add_argument('--motto', default='',
                    help='献词页寄语（before_body.tex）')
    ap.add_argument('--part-regex', default=r'^\*(\d{4})$',
                    help='分册书签的匹配模式，需含一个分组（默认 *年份）')
    ap.add_argument('--cnbook', default='/Users/flora/books/cnbook',
                    help='cnbook 共享排版包路径')
    ap.add_argument('--zhformat',
                    default=os.path.expanduser(
                        '~/.agents/skills/cn-doc-format/scripts/zhformat.py'),
                    help='zhformat.py 路径（cn-doc-format skill）')
    ap.add_argument('--no-scaffold', action='store_true', help='不生成工程骨架')
    ap.add_argument('--no-extract', action='store_true', help='不提取章节')
    ap.add_argument('--no-format', action='store_true', help='不做排版格式化')
    ap.add_argument('--no-appendix', action='store_true',
                    help='骨架中不生成附录（hmm.Rmd / references.Rmd）')
    ap.add_argument('--date-source', action='store_true',
                    help='可选特性：标题后第一行若为“日期 + 出处”（如 '
                         '2006-10-10 香港商报），整行作为日期行（.hline）处理')
    args = ap.parse_args(argv)

    book_dir = os.path.join(os.path.abspath(args.dir), args.name)
    if not args.no_scaffold:
        scaffold(args)
    rc = 0
    if not args.no_extract:
        os.makedirs(book_dir, exist_ok=True)
        rc = extract(os.path.abspath(args.pdf), book_dir, args.part_regex,
                     date_source=args.date_source)
    if rc == 0 and not args.no_format:
        run_format(book_dir, args.zhformat)

    print('\n后续步骤:')
    print(f'  1. 编辑 {args.name}/index.Rmd 撰写序言')
    print(f'  2. cd {os.path.abspath(args.dir)} && make pdf')
    return rc

if __name__ == '__main__':
    sys.exit(main())
