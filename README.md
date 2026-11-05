# 卢麒元文集（2001—2025）

卢麒元先生二十五年间的财经评论与时政分析文集的数字出版工程。
从 `doc/卢麒元文集 2001-2025.pdf`（3229 页）解析生成，使用 R + bookdown
构建为标准图书，排版格式与《中庸》精讲项目（zhong-v2）一致。

## 内容概要

- **规模**：21 个年份分册（2001、2006—2025），共 883 篇文章
- **体裁**：财经评论为主，兼有时政分析、演讲实录、访谈问答
- **主线**：财政与货币主权、人民币与美元博弈、超级地租与直接税改革、
  新社会主义论、中美关系与百年变局
- **结构**：序言《做一个耕读的行者》、作者简介、按年份分 PART 的正文

## 目录结构

```
├── Makefile              # 构建编排入口（make 查看全部命令）
├── VERSION               # 版本号
├── README.md
├── doc/                  # 原始素材
│   └── 卢麒元文集 2001-2025.pdf
├── tools/
│   └── extract_pdf.py    # PDF → Rmd 提取脚本
├── skills/
│   ├── cn-doc-format/    # 中文排版格式化 skill（本地副本）
│   └── pdf-to-bookdown/  # PDF 文集→bookdown 工程 skill（本地副本）
└── chat/                 # 图书主工程（bookdown）
    ├── index.Rmd         # 元数据 + 序言
    ├── 00-author.Rmd     # 作者简介
    ├── 2001-00.Rmd …     # 年份分册页（PART；2001-00.Rmd 顶部有 \mainmatter）
    ├── 2001-01-*.Rmd …   # 883 篇正文
    ├── hmm.Rmd           # 附录：整理说明 + 版本修订记录
    ├── references.Rmd    # 参考文献（生成 packages.bib）
    ├── _bookdown.yml / _output.yml
    ├── latex/ lua/ css/  # cnbook 排版包副本 + 项目定制
    ├── images/cover.png  # 封面（取自 PDF 首页）
    └── _book/            # 构建产物
```

## 构建命令

```bash
make            # 查看全部命令
make pdf        # 生成 PDF（XeLaTeX / ctexbook，约 3 分钟）
make html       # 生成 gitbook 版 HTML
make epub       # 生成 EPUB
make mobi       # 生成 MOBI（需 Calibre）
make serve      # 本地预览 HTML
make clean      # 清理中间文件
```

## 工具指南

### 1. PDF 提取：`tools/extract_pdf.py`

把 PDF 解析为章节 Rmd。依赖 `pypdf`，纯 Python 标准库以外的唯一依赖。

```bash
make extract            # 等价于 python3 tools/extract_pdf.py --date-source
```

`--date-source` 是可选特性：标题后第一行若为“日期 + 出处”
（如 `2006-10-10 香港商报`）或带圆括号副标题前缀（如
`（从保尔森访华看中美关系二之一）2006-12-13 香港商报`），整行作日期行
（.hline）处理；本集市商报专栏的 29 篇及带副标题的 2 篇需要它。

要点：

- 按书签大纲切分：`*2001` 等年份标记 → PART，其余书签 → 章节；
  文章可能同页连排，按标题行位置（而非页码区间）切分
- 康熙部首字符（`⼈⺠` 等 172 个）归一为标准汉字，映射表经逐一上下文核实
- 段落重组：行尾空格为段落结束标记；讲座实录类无标记的文章按句末标点兜底
- 文件名净化：ASCII 空格与标点统一替换为 `-`（bookdown 不接受）
- 首次运行将逐页文本缓存到 `doc/<PDF文件名>.pages-cache.json`，重跑秒级完成
- **注意**：`make extract` 会覆盖 chat/ 下生成的章节文件，之后须重跑 `make format`

### 2. 中文排版格式化：`cn-doc-format`

依据 `style-guide/docs` 中文写作规范（标题、文本、段落、数值、标点符号）
的自动格式化工具。脚本无第三方依赖，可独立运行，也是 agent skill
（`~/.agents/skills/cn-doc-format/`，项目内副本在 `skills/cn-doc-format/`）。

```bash
ZF=skills/cn-doc-format/scripts/zhformat.py

python3 $ZF --diff chat/2001-01-*.Rmd   # 预览差异
python3 $ZF -i chat/                    # 原地格式化（目录递归）
python3 $ZF --check chat/               # 检查模式（需改动则退出码为 1）
python3 $ZF --lint chat/                # 结构警告（标题层级跳跃等）

make format                             # 项目内快捷方式
make format-check
```

自动修正的规则：中英文/数字之间加空格、中文语境半角标点转全角、
直引号转弯引号并配对、`...`/`。。。` → `……`、连用感叹号归一、
`--` → `——`、年份区间 `2009-2011` → `2009～2011`、全角数字转半角、
五位以上数字加千分号、段首去空白、多个空行收敛为一个、标题末尾点号删除。

保护不改动的内容：YAML frontmatter、代码围栏、行内代码、URL、
Markdown 链接目标、`{.hline}` 等 pandoc 属性、整行英文。

### 3. 同类项目创建：`pdf-to-bookdown` skill

本项目就是 `pdf-to-bookdown` skill 的参考实现。要把另一个带书签大纲的
PDF 文集做成同样的书：

```bash
python3 skills/pdf-to-bookdown/scripts/pdf2book.py \
    --pdf "文集.pdf" --dir 新项目目录 --name 书稿目录名 \
    --title "书名" --author "作者"
cd 新项目目录 && make pdf
```

### 4. cnbook 排版包同步

`chat/lua/cnbook/`、`chat/latex/cnbook/`、`chat/css/cnbook.css` 是共享排版包
（`/Users/flora/books/cnbook`）的副本，勿直接编辑；共享包更新后执行：

```bash
make sync-cnbook
```

## 工作流约定

修改内容的正确顺序：

```bash
make extract   # 1. 从 PDF 重新生成章节（会覆盖）
make format    # 2. 中文排版规范化
make pdf       # 3. 构建成品
```

只改样式或配置（`_output.yml`、`latex/preamble.tex` 等）时直接 `make pdf` 即可。
