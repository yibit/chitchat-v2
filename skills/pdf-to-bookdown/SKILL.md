---
name: pdf-to-bookdown
description: 把带书签大纲的 PDF 文集/合集转换为一个完整的 bookdown 中文图书工程——自动生成项目骨架（Makefile、_bookdown.yml/_output.yml、latex/css/lua 排版文件、封面）、按分册书签（如 *2001 年份标记）切分章节为 Rmd（PART 分册页 + 每篇一章）、做部首字符归一与段落重组、再调用 cn-doc-format 完成中文排版规范化，最后 make pdf 成书。结构参照 zhong-v2/chitchat 项目。凡是用户说"把这个 PDF 做成一本书""解析文集 PDF 成 Rmd""按 zhong-v2 结构建书""创建一个类似 chitchat 的项目"时，必须使用本 skill，不要手写临时脚本拼凑。
---

# pdf-to-bookdown：PDF 文集 → bookdown 图书工程

给定一个带书签大纲的 PDF（如某人的文集，书签按 `*2001`、`*2006` 等
标记分册，其余书签为文章标题），一键生成可 `make pdf` 成书的完整
bookdown 工程。

## 使用方式

```bash
P2B=/Users/flora/.agents/skills/pdf-to-bookdown/scripts/pdf2book.py

python3 $P2B --pdf "path/to/文集.pdf" --dir 项目根目录 --name 书稿目录名 \
    --title "书名" --author "作者" --motto "献词页寄语"

cd 项目根目录 && make pdf
```

一条命令完成：工程骨架（scaffold）→ 章节提取（extract）→ 中文排版
格式化（format，调用 cn-doc-format skill 的 zhformat.py）。

已有工程只需重新提取时：

```bash
python3 $P2B --pdf "文集.pdf" --name 书稿目录名 --no-scaffold --no-format
# 然后在项目根目录：make format && make pdf
```

## 参数

| 参数 | 默认 | 说明 |
|------|------|------|
| `--pdf` | （必填） | 源 PDF 路径 |
| `--name` | （必填） | 书稿目录名，也是 bookdown 的 book_filename |
| `--dir` | `.` | 项目根目录（Makefile 放这里） |
| `--title` / `--author` / `--motto` | 占位 | 书名 / 作者 / 献词页寄语 |
| `--part-regex` | `^\*(\d{4})$` | 分册书签模式（一个分组）；其余书签为章节 |
| `--cnbook` | `/Users/flora/books/cnbook` | 共享排版包路径，不存在则跳过并警告 |
| `--zhformat` | cn-doc-format skill 路径 | 中文排版格式化脚本 |
| `--no-scaffold` / `--no-extract` / `--no-format` / `--no-appendix` | 关闭对应阶段 | |
| `--date-source` | 关 | 可选特性：标题后第一行若为“日期 + 出处”（如 `2006-10-10 香港商报`），或带圆括号副标题前缀（如 `（副标题）2006-12-13 香港商报`），整行作为日期行（`.hline`）处理；生成的 Makefile 会记住该开关 |

## 生成物

```
项目根目录/
├── Makefile              # make pdf/html/epub/mobi/serve/extract/format/sync-cnbook
├── VERSION
└── 书稿目录名/
    ├── index.Rmd         # 元数据 + 序言占位（需手工撰写）
    ├── 2001-00.Rmd …     # 分册页 # (PART) 2001 {-}（首个含 \mainmatter）
    ├── 2001-01-标题.Rmd … # 章节正文，标题下日期为 {.hline align=right}
    ├── hmm.Rmd / references.Rmd   # 附录与参考文献
    ├── _bookdown.yml / _output.yml / .Rprofile
    ├── latex/（preamble.tex、template.tex、cnbook/ 副本）
    ├── lua/cnbook/、css/（cnbook.css + style.css）
    └── images/cover.png  # PDF 首页（macOS sips 导出）
```

## 提取引擎已处理的 PDF 坑（Pages/Word 中文版导出）

1. **文章同页连排**：书签页码相同，按"标题行位置"在连续行流中切分，
   不能按页码区间。
2. **竖排标题**：被拆成多行（极端逐字一行），拼接去空白后与书签标题
   相等才算命中；竖排中 `广` 常变成部首 `⼲`，匹配时按等价类处理。
3. **部首字符**：独体字被替换为康熙部首（U+2F00–2FDF，NFKC 可解）与
   部首补充块（U+2E80–2EFF，内置手工映射表）；个别 NFKC 结果是繁体
   形，按简体覆盖。
4. **段落重组**：行尾"空格+换行"是段落结束标记；无此标记的实录类
   文章按句末标点兜底（最长段超 1200 字符时触发）。
5. **页码页脚**：页首/页尾纯数字行剔除。
6. **文件名净化**：ASCII 空格与标点替换为 `-`（bookdown 的
   check_special_chars 要求）；全角标点保留。

提取结果会列出"待人工核查"清单（标题未命中、正文为空等），务必过目。

## 手工收尾

骨架生成后需要人工处理的部分：

- `index.Rmd`：撰写序言（源 PDF 若有前言页，整理进去）
- 作者简介：如需，参照 chitchat 的 `00-author.Rmd` 新建
- `hmm.Rmd`：填写整理说明与版本记录
- 非 `*YYYY` 形式的分册标记：用 `--part-regex` 指定

## 配套

- 中文排版格式化规则详见 cn-doc-format skill（本 skill 的 format 阶段
  就是调用它）。
- cnbook 排版包副本（`lua/cnbook/`、`latex/cnbook/`、`css/cnbook.css`）
  勿直接编辑；更新后 `make sync-cnbook`。
- 参考实现：`/Users/flora/books/chitchat`（卢麒元文集）。
