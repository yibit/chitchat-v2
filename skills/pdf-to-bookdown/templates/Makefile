NAME = @@NAME@@
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
	@echo "    format    normalize Chinese typography          "
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

# 从源 PDF 重新提取章节 Rmd（覆盖书稿目录下生成的章节文件）
# 提取后须重跑 make format 做中文排版规范化
extract:
	python3 @@PDF2BOOK@@ --pdf "@@PDF@@" --name $(NAME) --no-scaffold --no-format @@EXTRACT_FLAGS@@

# 按 style-guide/docs 中文编排规范格式化书稿（cn-doc-format skill 的脚本）
ZHFORMAT = @@ZHFORMAT@@
format:
	python3 $(ZHFORMAT) -i $(NAME)/

format-check:
	python3 $(ZHFORMAT) --check $(NAME)/

# cnbook 共享排版包副本同步（勿直接编辑 lua/latex/css 下的 cnbook 副本）
CNBOOK_DIR = @@CNBOOK@@
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
