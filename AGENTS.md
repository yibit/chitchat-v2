# AGENTS.md — 卢麒元文集（2001—2025）

本文档供 AI 编码助手阅读。假设读者对该项目一无所知。

---

## 项目概述

本项目是《卢麒元文集（2001—2025）》的数字出版工程。内容从
`doc/卢麒元文集 2001-2025.pdf`（3229 页，macOS Pages 导出）解析而来，
共 21 个年份分册（2001、2006—2025）、883 篇文章，使用 R + bookdown
构建为标准图书。项目结构与排版格式参照《中庸》精讲项目
（`/Users/flora/books/zhong-v2`），排版包来自共享包 cnbook
（`/Users/flora/books/cnbook`）。

项目仅供作者自学整理使用。

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 图书渲染 | R、bookdown、knitr、rmarkdown |
| PDF 引擎 | XeLaTeX（`ctexbook` 文档类，支持中文 CJK） |
| HTML 输出 | bookdown::gitbook |
| EPUB/MOBI | bookdown::epub_book + Calibre (`ebook-convert`) |
| PDF 提取 | Python 3 + pypdf（`tools/extract_pdf.py`） |
| 排版格式化 | Python 3 标准库（`skills/cn-doc-format/scripts/zhformat.py`） |
| 本地预览 | Python `http.server`（端口 1472）或 R `bookdown::serve_book()` |

---

## 目录结构

```
.
├── Makefile              # 构建编排入口
├── VERSION               # 版本号（如 v1.0.0）
├── README.md             # 项目简介与工具指南
├── doc/                  # 原始素材
│   ├── 卢麒元文集 2001-2025.pdf   # 源文档
│   └── 卢麒元文集 2001-2025.pdf.pages-cache.json   # 逐页文本缓存（extract 生成，勿手改）
├── tools/
│   └── extract_pdf.py    # PDF → Rmd 提取脚本
├── skills/
│   ├── cn-doc-format/    # 中文排版格式化 skill 本地副本
│   │   ├── SKILL.md
│   │   └── scripts/zhformat.py
│   └── pdf-to-bookdown/  # PDF 文集 → bookdown 工程 skill 本地副本
│       ├── SKILL.md      #   （本项目的通用化版本，用于创建同类工程）
│       ├── scripts/pdf2book.py
│       └── templates/
└── chat/                 # 图书主工程（bookdown）
    ├── index.Rmd         # 书名页元数据 + 序言（手工维护，extract 不覆盖）
    ├── 00-author.Rmd     # 作者简介（手工维护）
    ├── 2001-00.Rmd … 2025-00.Rmd        # 年份分册页：# (PART) YYYY {-}
    │                                   #   首个分册页（2001-00.Rmd）顶部有 \mainmatter
    ├── 2001-01-*.Rmd … 2025-11-*.Rmd    # 883 篇正文（extract 生成）
    ├── hmm.Rmd           # 附录：整理说明 + 版本修订记录（手工维护）
    ├── references.Rmd    # 参考文献（生成 packages.bib，手工维护）
    ├── _bookdown.yml     # bookdown 配置
    ├── _output.yml       # 输出格式配置（gitbook/pdf_book/epub_book）
    ├── .Rprofile         # R 区域设置（macOS 下设为中文）
    ├── css/              # style.css（本项目）+ cnbook.css（共享包副本）
    ├── latex/            # preamble.tex、template.tex、before/after_body.tex
    │   └── cnbook/       # cnbook 共享排版包副本（勿直接编辑）
    ├── lua/cnbook/       # Pandoc Lua 过滤器（共享包副本，勿直接编辑）
    ├── images/cover.png  # 封面（sips 从 PDF 首页导出）
    └── _book/            # 构建产物（PDF/HTML/EPUB/TEX 等）
```

另有 `hmm.Rmd`（附录：整理说明与版本记录，以 `\cleardoublepage` 开篇）
和 `references.Rmd`（生成 packages.bib 的参考文献章），均为手工维护，
extract 不覆盖。

---

## 构建命令

所有构建入口都在项目根目录的 `Makefile` 中。

```bash
make            # 查看可用命令
make pdf        # 生成 PDF（约 3 分钟，产物 _book/chat.pdf + 版本化副本）
make html       # 生成 gitbook 版 HTML
make epub       # 生成 EPUB
make mobi       # 生成 MOBI（依赖 Calibre）
make serve      # R serve_book 本地预览（热更新）
make servepy    # Python http.server 预览（端口 1472）
make extract    # 从 PDF 重新提取章节 Rmd（覆盖生成文件）
make format     # 中文排版规范化（cn-doc-format）
make format-check  # 检查模式，不写入
make sync-cnbook   # 同步 cnbook 共享排版包副本
make clean / make distclean   # 清理中间文件 / 含 _book
```

### 工作流约定（重要）

`make extract` 会**覆盖** chat/ 下所有 `YYYY-NN-*.Rmd` 生成文件
（不含 index.Rmd、00-author.Rmd），且输出是未规范化的原始文本。
正确的完整流程：

```bash
make extract && make format && make pdf
```

---

## 内容管线与关键约定

### 1. PDF 提取（tools/extract_pdf.py）

- **分册与章节**：书签大纲是扁平结构，`*YYYY` 为年份分册标记（→
  `# (PART) YYYY {-}` 分册页 `YYYY-00.Rmd`），其余书签为文章。
- **同页连排**：文章不一定另起一页，同一页可能有多篇，必须按"标题行
  位置"在连续行流中切分，不能按书签页码区间切分。标题竖排会被拆成
  多行（极端情况逐字一行），拼接（去空白）后与书签标题相等即命中；
  竖排标题中 `广` 会被 Pages 写成部首 `⼲`，匹配时按等价类处理。
- **字符归一**：正文大量独体字被替换为康熙部首（U+2F00–2FDF，NFKC 可
  解）和部首补充块（U+2E80–2EFF，需手工映射）字符，映射表在脚本
  `RADICAL_OVERRIDES` 中，已按上下文逐一核实（如 `⺩`→王、`⻑`→長）。
  注意个别 NFKC 结果是繁体形（⾞→車），按简体书稿覆盖为简体。
- **段落重组**：行尾"空格+换行"是段落结束标记；讲座实录类文章无此标
  记，按句末标点兜底（`FALLBACK_MAX` 阈值触发）。
- **页脚**：页首/页尾的纯数字行为书页码，剔除。
- **文件名净化**：bookdown 的 `check_special_chars` 不接受文件名中的
  ASCII 空格和标点（`(`、`)`、空格等），`safe_name` 统一替换为 `-`；
  全角标点（《》：，）不受影响。
- **缓存**：首次运行将逐页文本写入 `doc/<PDF文件名>.pages-cache.json`
  （约 100 秒，与 pdf-to-bookdown skill 同一约定），
  之后重跑秒级完成。PDF 更换后需删除缓存再跑。
- **日期出处行（可选特性）**：`--date-source`（Makefile 的 extract 目标
  已带）：标题后第一行若为"日期 + 出处"（如 `2006-10-10 香港商报`），
  或带圆括号副标题前缀（如 `（从保尔森访华看中美关系二之一）2006-12-13
  香港商报`），整行作日期行（.hline）处理。本集市商报专栏 29 篇、
  带副标题 2 篇适用。

### 2. 中文排版格式化（cn-doc-format）

- 脚本：`skills/cn-doc-format/scripts/zhformat.py`，与
  `~/.agents/skills/cn-doc-format/` 是同一份，改动需两边同步。
- 依据 `style-guide/docs` 规范，规则清单与保护机制见该 skill 的
  SKILL.md 和 README.md。
- 格式化是幂等的：`--check` 退出码为 0 表示全部合规。

### 3. cnbook 共享排版包

`chat/lua/cnbook/`、`chat/latex/cnbook/`、`chat/css/cnbook.css` 是
`/Users/flora/books/cnbook` 的同步副本（`make sync-cnbook`），
**勿直接编辑**；要改请到 cnbook 仓库改完再同步。项目特有定制放在
`chat/latex/preamble.tex`（中文字体钉死 Songti SC Light + Bold、
链接转脚注、`\frontmatter`）、`chat/css/style.css`。

### 4. Rmd 排版标记（继承 zhong-v2 惯例）

- 日期行：`[2006-9-14]{.hline align=right}`（标题下右对齐，
  由 `lua/cnbook/hline.lua` 处理）；`.hline` 支持
  `align/color/bold` 属性（如 `{.hline align=right bold=true}` 整行加粗），
  行内加粗/着色用 `.c`（如 `[文字]{.c color=Maroon bold=true}`）
- 献词页：`latex/before_body.tex`（封面寄语"做好今天的每一件事，
  善待身边的每一个人。"）

---

## 测试说明

**本项目没有自动化测试。** 验证方式：

- `make format-check`：格式化幂等性检查（退出码 0 = 合规）
- `make pdf` 后检查 `_book/chat.pdf` 页数（正常约 3900+ 页）与目录
- 抽查章节文件内容（首篇 `2001-01-苏联解体十年祭.Rmd`、同页连排的
  `2006-31/32`、竖排长标题的 `2017-31`、无日期篇 `2014-02-c.Rmd`）

---

## 已知注意事项

1. **并发访问**：曾有外部进程（疑似云同步）改动本目录文件名/文件的
   迹象；`make pdf` 期间不要读写 `_book/`，否则 `rm -rf` 可能因并发
   失败（"Directory not empty"），重跑即可。
2. **git 可选**：Makefile 的 `BRANCH`/`COMMIT` 对非 git 目录有容错
   （回退 main/nogit）。
3. **讲座实录类文章**的段落边界是推断的，可能与原书略有出入。
4. **依赖**：R + bookdown、TinyTeX（xelatex）、pypdf；EPUB→MOBI 需
   Calibre 的 `ebook-convert`。

---

## 修改建议

- **改正文内容**：优先改 `doc/` 源 PDF 后重跑 `make extract && make
  format`；直接改 `chat/2*.Rmd` 会在下次 extract 时被覆盖。
- **改序言/作者简介**：编辑 `chat/index.Rmd`、`chat/00-author.Rmd`
  （extract 不覆盖）。
- **改图书元数据/样式**：`chat/index.Rmd`、`_bookdown.yml`、
  `_output.yml`、`chat/css/style.css`、`chat/latex/preamble.tex`。
- **改提取逻辑**：`tools/extract_pdf.py`，改后 `make extract &&
  make format`，抽查上述测试章节。
- **改格式化规则**：`skills/cn-doc-format/scripts/zhformat.py`，
  同步到 `~/.agents/skills/cn-doc-format/`，用 `--diff` 抽查后再 `-i`。
- **改 PDF 转书流程**：`skills/pdf-to-bookdown/scripts/pdf2book.py`，
  同步到 `~/.agents/skills/pdf-to-bookdown/`。
- **改构建流程**：根目录 `Makefile`。
