PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin

SHELL_SOURCES := bin/pushme $(wildcard test/helpers/*.sh)
BATS_SOURCES := $(wildcard test/*.bats)
SHFMT_FLAGS := -i 2 -ci

.PHONY: install test lint

install:
	install -d "$(BINDIR)"
	install -m 0755 bin/pushme "$(BINDIR)/pushme"
	@echo "インストールしました: $(BINDIR)/pushme"
	@case ":$$PATH:" in \
	  *":$(BINDIR):"*) ;; \
	  *) echo "注意: $(BINDIR) が PATH に入っていません。シェルの設定ファイルに次の行を追加してください:"; \
	     echo "  export PATH=\"$(BINDIR):\$$PATH\"" ;; \
	esac

test:
	bats test

lint:
	shellcheck $(SHELL_SOURCES)
	shellcheck --severity=warning $(BATS_SOURCES)
	shfmt $(SHFMT_FLAGS) -d $(SHELL_SOURCES)
