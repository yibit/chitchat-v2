#!/usr/bin/env python3
"""zhformat.py — 中文文章编排格式化工具

依据 style-guide/docs 中文写作规范（标题/文本/段落/数值/标点符号），
对 Markdown / R Markdown 中文文稿做机械、安全的自动格式化。

自动修正的规则（按规范出处标注）：

  文本 text.md
    T1  全角中文与半角英文/数字之间加一个半角空格（风格统一为加空格）
    T2  半角字符与全角标点之间不留空格
  标点 marks.md
    M1  中文语境下的半角标点 , ; : ! ? ( ) . 转全角，；：！？（）。
        （数字间冒号 8:00、千分位 1,000、小数 3.14 等不受影响）
    M2  直引号 "..." '...' 在中文语境转全角弯引号 “ ” ‘ ’（按出现顺序配对）
    M3  ... 或 。。。 等非标准省略号 → ……
    M4  多个感叹号连用（!!／！！）→ 单个
    M5  中文之间的 -- → ——（破折号占两个汉字位置）
    M6  数值范围 2009-2011 → 2009～2011（仅四位数年份式区间，不动日期）
  数值 number.md
    N1  全角数字 ０-９、全角百分号 ％ → 半角
    N2  五位以上数值加千分号：50000 → 50,000（四位数不变，可用 --no-thousands 关闭）
  段落 paragraph.md
    P1  段首不留空白（含全角空格 　）
    P2  段落之间恰好一个空行（多个空行收敛为一个）
  标题 title.md
    H1  标题末尾的点号（。，、；：）删除
        （标题层级跳跃、孤立编号等结构性问题只报警告，不擅自改动）

保护机制：YAML frontmatter、代码围栏、行内代码、URL、Markdown 链接
目标、整句英文的行（无中文字符）均不做中文化处理。

用法：
  zhformat.py 文件...            # 格式化结果输出到 stdout（单文件）
  zhformat.py -i 文件或目录...   # 原地修改（目录递归处理 .md/.Rmd/.markdown）
  zhformat.py --diff 文件...     # 只显示差异，不写文件
  zhformat.py --check 文件...    # 检查模式：有需要修改则退出码为 1
  zhformat.py --lint 文件...     # 结构警告（标题层级等），不改文件

无任何第三方依赖，Python 3.8+ 可直接运行。
"""

import argparse
import difflib
import os
import re
import sys

# ---------------------------------------------------------------------------
# 字符集
# ---------------------------------------------------------------------------

CJK = (
    r'\u2e80-\u2eff'      # 部首补充
    r'\u3000-\u303f'      # CJK 符号和标点（含全角空格）
    r'\u3040-\u30ff'      # 日文假名
    r'\u31c0-\u31ef'
    r'\u3200-\u32ff'
    r'\u3400-\u4dbf'
    r'\u4e00-\u9fff'      # CJK 统一表意文字
    r'\uf900-\ufaff'
    r'\uff00-\uffef'      # 全角形式
)
CJK_RE = re.compile(f'[{CJK}]')

# 全角标点（用于 T2：半角字符与全角标点之间不留空格）
FW_PUNCT = '，。、；：？！""''（）《》〈〉【】…—～·'

# 半角标点 → 全角（M1）
PUNCT_MAP = {',': '，', ';': '；', ':': '：', '!': '！', '?': '？',
             '(': '（', ')': '）'}

# 标题末尾应删除的点号（H1；标号如 ？！）—— 保留
HEADING_TRAILING = '。，、；：,.;:'

# ---------------------------------------------------------------------------
# 保护掩码：行内代码、URL、链接目标、邮箱
# ---------------------------------------------------------------------------

MASK_PATTERNS = [
    re.compile(r'`[^`\n]*`'),                            # 行内代码
    re.compile(r'!?\[[^\]\n]*\]\([^)\n]*\)'),            # [文字](url) / 图片
    re.compile(r'https?://[^\s<>"）)】]+'),               # URL
    re.compile(r'[\w.+-]+@[\w-]+\.[\w.]+'),              # 邮箱
    re.compile(r'\{[:#.\w][^}\n]*\}'),                   # pandoc 属性 {.hline ...}
]

MASK_CHAR = '\x00'


def mask(text):
    """把不应触碰的片段替换为占位符，返回 (text, replacements)。"""
    repl = []

    def _sub(m):
        repl.append(m.group(0))
        return f'{MASK_CHAR}{len(repl) - 1}{MASK_CHAR}'

    for pat in MASK_PATTERNS:
        text = pat.sub(_sub, text)
    return text, repl
    return text


def unmask(text, repl):
    return re.sub(f'{MASK_CHAR}(\\d+){MASK_CHAR}',
                  lambda m: repl[int(m.group(1))], text)


# ---------------------------------------------------------------------------
# 各条规则：输入输出均为单行文本（不含换行符）
# ---------------------------------------------------------------------------

def r_fullwidth_ascii(line):
    """N1：全角数字、全角百分号转半角（全角字母仅在纯技术串中才转换，保守起见不转）。"""
    line = line.translate(str.maketrans(
        '０１２３４５６７８９％', '0123456789%'))
    return line


def r_ellipsis(line):
    """M3：省略号规范为 ……（两个汉字宽、六个点）。"""
    line = re.sub(r'\.{3,}', '……', line)     # ...
    line = re.sub(r'。{3,}', '……', line)     # 。。。
    line = re.sub(r'…{3,}', '……', line)      # ………
    line = re.sub(r'(?<!…)…(?!…)', '……', line)  # 单个 …
    return line


def r_bangs(line):
    """M4：感叹号不得连用。"""
    def _sub(m):
        ctx = line[max(0, m.start() - 1):m.end() + 1]
        return '！' if CJK_RE.search(ctx) else '!'
    return re.sub(r'[!！]{2,}', _sub, line)


def r_dashes(line):
    """M5：中文语境的 -- → ——；单个 — 连用保持规范的两个 ——。"""
    line = re.sub(f'(?<=[{CJK}])--|--(?=[{CJK}])', '——', line)
    line = re.sub(f'(?<=[{CJK}])--(?=[{CJK}])', '——', line)
    # ——— 及以上：按破折号成对处理
    line = re.sub(r'—{3,}', '——', line)
    return line


def r_numeric_range(line):
    """M6：四位数年份式数值区间用波浪连接号（不动 2001-12-25 这类日期）。"""
    return re.sub(r'(?<![\d-])(\d{4})-(\d{4})(?![\d-])', r'\1～\2', line)


def r_thousands(line):
    """N2：五位以上的整数加千分号。跳过小数、日期、时间及已有千分号的数。"""
    def _sub(m):
        s = m.group(0)
        return f'{int(s):,}'
    return re.sub(r'(?<![\d,.\-:/])\d{5,}(?![\d,.\-])', _sub, line)


def r_quotes(line):
    """M2：中文语境的直引号转弯引号，按出现顺序开闭配对。"""
    if not CJK_RE.search(line):
        return line
    out = []
    double_open = False
    single_open = False
    for i, ch in enumerate(line):
        if ch == '"':
            prev = line[i - 1] if i else ''
            nxt = line[i + 1] if i + 1 < len(line) else ''
            if CJK_RE.match(prev + ' ') or CJK_RE.match(' ' + nxt) \
                    or CJK_RE.match(prev) or CJK_RE.match(nxt):
                ch = '“' if not double_open else '”'
                double_open = not double_open
        elif ch == "'":
            prev = line[i - 1] if i else ''
            nxt = line[i + 1] if i + 1 < len(line) else ''
            # 英文撇号（man's）不处理
            if not (prev.isascii() and prev.isalpha()
                    and nxt.isascii() and nxt.isalpha()):
                if CJK_RE.match(prev) or CJK_RE.match(nxt):
                    ch = '‘' if not single_open else '’'
                    single_open = not single_open
        out.append(ch)
    return ''.join(out)


def r_punct(line):
    """M1：与中文相邻的半角标点转全角。判定时越过紧邻的空格
    （如“优势 ( 意识形态 )”中的括号，两侧最近的非空格字符是中文）。"""
    if not CJK_RE.search(line):
        return line
    n = len(line)
    out = list(line)
    for i, ch in enumerate(out):
        prev = out[i - 1] if i else ''
        nxt = line[i + 1] if i + 1 < n else ''
        # 两侧最近的非空格字符（左侧读 out，使同一行内前一个标点的
        # 半角→全角转换能传导，如 “?!” 一次通过变为 “？！”）
        j = i - 1
        while j >= 0 and out[j] == ' ':
            j -= 1
        prev_ns = out[j] if j >= 0 else ''
        k = i + 1
        while k < n and line[k] == ' ':
            k += 1
        next_ns = line[k] if k < n else ''
        if ch in PUNCT_MAP:
            if CJK_RE.match(prev_ns) or CJK_RE.match(next_ns):
                # 数字-数字之间的冒号（8:00）与逗号（1,000）保持半角
                if ch in (':', ',') and prev_ns.isdigit() and next_ns.isdigit():
                    continue
                # 括号成对约束：( 仅在右邻中文时转，) 仅在左邻中文时转，
                # 避免 (PART) 附录 这类只转一边的不对称结果
                if ch == '(' and not CJK_RE.match(next_ns):
                    continue
                if ch == ')' and not CJK_RE.match(prev_ns):
                    continue
                out[i] = PUNCT_MAP[ch]
        elif ch == '.':
            # 句号：前为中文、后不是英文字母（避开 U.S.A. 之类缩写）
            if CJK_RE.match(prev_ns) and not (next_ns.isascii() and next_ns.isalpha()):
                out[i] = '。'
    return ''.join(out)


def r_spacing(line, digit_space=True):
    """T1/T2：中英文之间加空格；半角字符与全角标点之间不留空格。
    全角空格（　）本身即是间隔，两侧不再加空格、已有空格则删除。"""
    if not CJK_RE.search(line):
        return line
    # 全角空格两侧的 ASCII 空格直接删掉
    line = re.sub(r'　 +', '　', line)
    line = re.sub(r' +　', '　', line)
    # 边界判定用的 CJK 字符集不含全角空格
    Z = CJK.replace(r'\u3000', r'\u3001')
    # 先收敛边界处的多余空格
    line = re.sub(f'([{Z}]) +([A-Za-z0-9%])', r'\1\2', line)
    line = re.sub(r'([A-Za-z0-9%]) +([{}])'.format(Z), r'\1\2', line)
    if digit_space:
        line = re.sub(f'([{Z}])([A-Za-z0-9%])', r'\1 \2', line)
        line = re.sub(r'([A-Za-z0-9%])([{}])'.format(Z), r'\1 \2', line)
    else:
        # 只在中英文之间加，中文与数字之间不加（规范允许的另一种统一风格）
        line = re.sub(f'([{Z}])([A-Za-z%])', r'\1 \2', line)
        line = re.sub(r'([A-Za-z%])([{}])'.format(Z), r'\1 \2', line)
        line = re.sub(f'([{Z}]) +([0-9])', r'\1\2', line)
        line = re.sub(r'([0-9]) +([{}])'.format(Z), r'\1\2', line)
    # T2：半角字符与全角标点之间不留空格（两个方向）
    line = re.sub(r'([A-Za-z0-9%]) +([{}])'.format(re.escape(FW_PUNCT)),
                  r'\1\2', line)
    line = re.sub('([{}]) +([A-Za-z0-9%])'.format(re.escape(FW_PUNCT)),
                  r'\1\2', line)
    # M7：全角标点（开/闭引号、括号、点号）与中文之间不留空格，
    # 内外两侧都删（破折号 —— 前后的空格是规范允许的形式，不动；
    # Markdown 行首结构标记 # - * + > 后的空格是语法，不动）
    line = re.sub(r'([“‘（《【「『]) +', r'\1', line)
    line = re.sub(r'(?<![\s#*+>\-—]) +([“‘（《【「『”’）》】」』，。、；：？！…])',
                  r'\1', line)
    line = re.sub(r'([”’）》】」』，。、；：？！…]) +(?=[{}“‘（《【「『])'.format(Z),
                  r'\1', line)
    # M8：标有书名号/引号的并列成分之间不用顿号（GB/T 15834）
    line = re.sub(r'([》”’」』])、(?=[《“‘「『])', r'\1', line)
    return line


# 规则应用顺序：字符归一 → 标点 → 引号 → 空格
LINE_RULES = [
    r_fullwidth_ascii,
    r_ellipsis,
    r_bangs,
    r_dashes,
    r_numeric_range,
    r_thousands,
    r_punct,
    r_quotes,
    r_spacing,
]

# ---------------------------------------------------------------------------
# 结构处理：frontmatter / 代码围栏 / 标题 / 段落
# ---------------------------------------------------------------------------

HEADING_RE = re.compile(r'^(#{1,6})\s+(.*?)\s*$')
# 结构性行：列表、引用、表格、pandoc 块，不做段首去空白等段落规则
STRUCTURAL_RE = re.compile(r'^\s*([-*+>]|\d+[.)]|\||:::)')

LINT_WARNINGS = []


def lint_heading(level, text, lineno, filename):
    """title.md 结构检查：层级跳跃、孤立编号（只警告，不修改）。"""
    LINT_WARNINGS.append((filename, lineno, level, text))


def flush_lint():
    out = []
    prev_level = 0
    for fn, lineno, level, text in LINT_WARNINGS:
        if prev_level and level > prev_level + 1:
            out.append(f'{fn}:{lineno}: 标题层级跳跃 '
                       f'(H{prev_level} 直接到 H{level})：{text}')
        prev_level = level
    return out


def format_text(content, digit_space=True):
    """格式化整篇文档，返回 (新文本, 是否改动)。"""
    lines = content.split('\n')
    out = []
    in_fm = False          # YAML frontmatter
    in_code = False        # 代码围栏
    fm_done = False

    for i, line in enumerate(lines):
        stripped = line.strip()
        # frontmatter：仅当位于文件开头
        if i == 0 and stripped == '---':
            in_fm = True
            out.append(line)
            continue
        if in_fm:
            if stripped == '---':
                in_fm = False
                fm_done = True
            out.append(line)
            continue
        # 代码围栏
        if stripped.startswith('```'):
            in_code = not in_code
            out.append(line)
            continue
        if in_code:
            out.append(line)
            continue
        # 空行：P2 收敛在写出阶段处理
        if not stripped:
            out.append('')
            continue

        new = line
        # P1：段首不留空白（结构性行的缩进保留）
        if not STRUCTURAL_RE.match(new):
            new = new.lstrip(' \t　')

        m = HEADING_RE.match(new)
        if m:
            # H1：标题末尾点号删除（？！等标号保留）
            title = m.group(2).rstrip(HEADING_TRAILING)
            if title != m.group(2):
                new = f'{m.group(1)} {title}'

        masked, repl = mask(new)
        for rule in LINE_RULES:
            if rule is r_spacing:
                masked = rule(masked, digit_space=digit_space)
            else:
                masked = rule(masked)
        new = unmask(masked, repl)
        out.append(new)

    # P2：多个连续空行收敛为一个；文件首尾不留空行
    collapsed = []
    prev_blank = True  # 文件开头视同已有空行，去掉首部空行
    for line in out:
        if line == '':
            if not prev_blank:
                collapsed.append('')
            prev_blank = True
        else:
            collapsed.append(line)
            prev_blank = False
    while collapsed and collapsed[-1] == '':
        collapsed.pop()

    new_content = '\n'.join(collapsed) + '\n'
    return new_content, new_content != content


def collect_lint(content, filename):
    """收集标题层级警告。"""
    del LINT_WARNINGS[:]
    in_fm = in_code = False
    for i, line in enumerate(content.split('\n'), 1):
        s = line.strip()
        if i == 1 and s == '---':
            in_fm = True
            continue
        if in_fm:
            if s == '---':
                in_fm = False
            continue
        if s.startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        m = HEADING_RE.match(line)
        if m:
            lint_heading(len(m.group(1)), m.group(2), i, filename)
    return flush_lint()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

TEXT_EXTS = ('.md', '.markdown', '.Rmd', '.rmd', '.txt')


def iter_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                for f in sorted(files):
                    if f.endswith(TEXT_EXTS):
                        yield os.path.join(root, f)
        else:
            yield p


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog='zhformat',
        description='中文文章编排格式化工具（style-guide/docs 规范）')
    ap.add_argument('paths', nargs='+', help='文件或目录')
    ap.add_argument('-i', '--in-place', action='store_true', help='原地修改')
    ap.add_argument('--diff', action='store_true', help='显示差异，不写文件')
    ap.add_argument('--check', action='store_true',
                    help='检查模式：有文件需要修改时退出码为 1')
    ap.add_argument('--lint', action='store_true',
                    help='只输出结构警告（标题层级等），不改文件')
    ap.add_argument('--no-digit-space', dest='digit_space',
                    action='store_false',
                    help='中文与数字之间不加空格（规范允许的另一种统一风格）')
    ap.add_argument('--no-thousands', dest='thousands',
                    action='store_false', help='不添加千分号')
    args = ap.parse_args(argv)

    if not args.thousands:
        LINE_RULES.remove(r_thousands)

    changed_files = []
    warnings = []

    for path in iter_files(args.paths):
        with open(path, encoding='utf-8') as f:
            content = f.read()

        if args.lint:
            warnings.extend(collect_lint(content, path))
            continue

        new, changed = format_text(content, digit_space=args.digit_space)
        if not changed:
            continue
        changed_files.append(path)

        if args.diff:
            sys.stdout.writelines(difflib.unified_diff(
                content.splitlines(True), new.splitlines(True),
                fromfile=path, tofile=path + ' (formatted)'))
        elif args.in_place:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new)
        elif not args.check:
            if len(list(iter_files(args.paths))) == 1:
                sys.stdout.write(new)
            else:
                sys.stdout.write(f'### {path} 需要格式化（用 -i 写入）\n')

    for w in warnings:
        print(w, file=sys.stderr)

    if args.lint:
        return 0
    if args.check:
        for p in changed_files:
            print(f'需要格式化: {p}', file=sys.stderr)
        return 1 if changed_files else 0
    if args.in_place and changed_files:
        print(f'已格式化 {len(changed_files)} 个文件', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
