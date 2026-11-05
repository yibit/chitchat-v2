NAME = chat
VERSION := $(shell cat ./VERSION |awk 'NR==1 { print $1; }')
BRANCH = $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
COMMIT = $(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)
RELEASEDATE=$(shell date '+%Y%m%d')
VERSION_TAG = "$(NAME)-$(VERSION)-$(BRANCH)-$(COMMIT)-$(RELEASEDATE)"
MYHOME = $(PWD)

default: usage

usage:
	@echo "Usage:                                              "
	@echo "                                                    "
	@echo "    make command                                    "
	@echo "                                                    "
	@echo "The commands are:                                   "
	@echo "                                                    "
	@echo "    pdf       generate pdf form of the book         "
	@echo "    html      generate gitbook form of the book     "
	@echo "    epub      generate epub form of the book        "
	@echo "    mobi      generate mobi form of the book        "
	@echo "    serve     serve html version of book locally    "
	@echo "    extract   re-extract Rmd chapters from the PDF  "
	@echo "    clean     clean up the project                  "
	@echo "                                                    "

all: distclean pdf html epub mobi

pdf: distclean
	@cd $(NAME) && Rscript -e "bookdown::render_book('index.Rmd', 'bookdown::pdf_book')"
	cp $(NAME)/_book/$(NAME).pdf $(NAME)/_book/$(VERSION_TAG).pdf

html:
	@cd $(NAME) && Rscript -e "bookdown::render_book('index.Rmd', 'bookdown::gitbook')"

epub:
	@cd $(NAME) && Rscript -e "bookdown::render_book('index.Rmd', 'bookdown::epub_book')"

mobi:
	@cd $(NAME) && Rscript -e "bookdown::calibre('_book/$(NAME).epub', 'mobi')"

serve:
	@cd $(NAME) && Rscript -e "bookdown::serve_book(dir = '.', output_dir = '_book', preview = TRUE, in_session = TRUE, quiet = FALSE)"

port=1472
servepy: $(NAME)/_book/index.html
	@cd $(NAME)/_book && python -m http.server $(port)

open: $(NAME)/_book/index.html
	@open $^

openpdf: $(NAME)/_book/$(NAME).pdf
	@open $^

# 从 doc/卢麒元文集 2001-2025.pdf 重新提取章节 Rmd（覆盖 chat/ 下生成的章节文件）
# --date-source：标题后“日期 + 出处”行（如 2006-10-10 香港商报）作日期行处理
# 提取后须重跑 make format 做中文排版规范化
extract:
	python3 tools/extract_pdf.py --date-source

# 按 style-guide/docs 中文编排规范格式化书稿（cn-doc-format skill 的脚本，
# 项目本地副本在 skills/cn-doc-format/，与 ~/.agents/skills 下的是同一份）
ZHFORMAT = skills/cn-doc-format/scripts/zhformat.py
format:
	python3 $(ZHFORMAT) -i $(NAME)/

format-check:
	python3 $(ZHFORMAT) --check $(NAME)/

# cnbook 共享排版包（/Users/flora/books/cnbook）的副本同步。
# chat/lua/cnbook/、chat/latex/cnbook/、chat/css/cnbook.css 均为生成的
# 副本，勿直接编辑；共享包更新后重跑本目标即可。
CNBOOK_DIR = /Users/flora/books/cnbook
sync-cnbook:
	mkdir -p $(NAME)/lua/cnbook $(NAME)/latex/cnbook $(NAME)/css
	cp -f $(CNBOOK_DIR)/lua/*.lua $(NAME)/lua/cnbook/
	cp -f $(CNBOOK_DIR)/latex/*.tex $(NAME)/latex/cnbook/
	cp -f $(CNBOOK_DIR)/css/cnbook.css $(NAME)/css/

.PHONY: clean distclean mobi extract

clean:
	cd $(NAME) && rm -rf $(NAME).* _bookdown_files *.log
	find . -name \*~ -type f |xargs -I {} rm -f {}

distclean: clean
	rm -rf $(NAME)/_book
