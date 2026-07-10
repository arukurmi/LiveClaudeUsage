PREFIX  ?= $(HOME)/.local
BIN      = $(PREFIX)/bin/claudebar
PLIST    = $(HOME)/Library/LaunchAgents/com.arukurmi.claudebar.plist
LABEL    = com.arukurmi.claudebar
UID     := $(shell id -u)

.PHONY: build test demo install uninstall

build:
	swift build -c release

test:
	swift run claudebar-tests

demo: build
	.build/release/claudebar --demo

install: build
	mkdir -p $(PREFIX)/bin $(HOME)/Library/LaunchAgents
	cp .build/release/claudebar $(BIN)
	sed 's|__BIN__|$(BIN)|' resources/$(LABEL).plist > $(PLIST)
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		launchctl print gui/$(UID)/$(LABEL) >/dev/null 2>&1 || break; \
		sleep 1; \
	done
	launchctl bootstrap gui/$(UID) $(PLIST)
	@echo "claudebar installed and running (starts at login)."

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	rm -f $(PLIST) $(BIN)
	@echo "claudebar uninstalled."
