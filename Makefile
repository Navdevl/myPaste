# SwiftPM build plus .app bundling and signing (no Xcode project).
APP      := myPaste
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
INSTALL  := $(HOME)/Applications/$(APP).app
IDENTITY ?= myPaste Dev
RELEASE  := .build/release
VERSION  := $(shell cat VERSION)
# Monotonic build number: commits on this branch (+ "-dirty" builds get the same number).
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
# Swift Testing lives outside the default search path in a Command Line Tools-only install.
CLT_FW   := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TESTFLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) \
             -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib

.PHONY: all app test uitest install run cert clean version

version:
	@echo $(VERSION) \($(BUILD_NUMBER)\)

all: app

test:
	swift test $(TESTFLAGS)

app:
	swift build -c release --product $(APP)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(RELEASE)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(BUNDLE)/Contents/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	for b in $(RELEASE)/*.bundle; do [ -e "$$b" ] && cp -R "$$b" $(BUNDLE)/Contents/Resources/; done; true
	@if security find-certificate -c "$(IDENTITY)" >/dev/null 2>&1; then \
		codesign --force --deep --sign "$(IDENTITY)" --options runtime $(BUNDLE); \
	else \
		echo "warning: '$(IDENTITY)' cert missing (run make cert); ad-hoc signing"; \
		codesign --force --deep --sign - $(BUNDLE); \
	fi

FAKE     := $(BUILD)/uitest/FakeMaccy.app
LSREG    := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Accessibility-driven UI tests against the freshly built bundle. Quits the installed copy for the
# duration (both would fight over hotkeys and the clipboard) and relaunches it afterwards.
uitest: app
	swift build -c release --product myPasteUITests
	mkdir -p $(FAKE)/Contents/MacOS
	cp Tests/UITests/FakeMaccy/Info.plist $(FAKE)/Contents/Info.plist
	swiftc Tests/UITests/FakeMaccy/main.swift -o $(FAKE)/Contents/MacOS/FakeMaccy
	codesign --force --sign - $(FAKE)
	-pkill -x $(APP); sleep 0.5
	./$(RELEASE)/myPasteUITests $(BUNDLE) $(FAKE); status=$$?; \
		$(LSREG) -u $(FAKE) 2>/dev/null; rm -rf $(FAKE); \
		[ -d $(INSTALL) ] && open $(INSTALL); exit $$status

install: app
	-osascript -e 'tell application id "local.mypaste.app" to quit' 2>/dev/null
	-pkill -x $(APP); sleep 0.5
	mkdir -p $(HOME)/Applications
	rm -rf $(INSTALL)
	cp -R $(BUNDLE) $(INSTALL)
	open $(INSTALL)

run: app
	-pkill -x $(APP); sleep 0.3
	open $(BUNDLE)

cert:
	./scripts/make-cert.sh "$(IDENTITY)"

clean:
	rm -rf $(BUILD) .build
