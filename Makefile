BUSTED  ?= $(HOME)/.luarocks/bin/busted
LUACHECK ?= $(HOME)/.luarocks/bin/luacheck

.PHONY: test lint package

test:
	$(BUSTED)

lint:
	$(LUACHECK) .

package:
	@echo "package: implemented in Task 11" && exit 1
