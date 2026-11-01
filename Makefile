PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin

SHELL_SOURCES := bin/pushme action/run.sh $(wildcard test/helpers/*.sh)
BATS_SOURCES := $(wildcard test/*.bats)
JSON_SOURCES := $(wildcard .claude-plugin/*.json hooks/*.json examples/*.json test/fixtures/claude/*.json test/fixtures/codex/*.json)
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

# bats' run assigns $output, $stderr and friends behind shellcheck's back;
# releases before 0.10 (Ubuntu's apt package) report them as SC2154.
lint:
	shellcheck $(SHELL_SOURCES)
	shellcheck --severity=warning --exclude=SC2154 $(BATS_SOURCES)
	shfmt $(SHFMT_FLAGS) -d $(SHELL_SOURCES)
	jq empty $(JSON_SOURCES)
