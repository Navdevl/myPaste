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

.PHONY: all app dist test uitest install run cert clean version

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
	cp -R Resources/Sounds $(BUNDLE)/Contents/Resources/Sounds
	for b in $(RELEASE)/*.bundle; do [ -e "$$b" ] && cp -R "$$b" $(BUNDLE)/Contents/Resources/; done; true
	@if security find-certificate -c "$(IDENTITY)" >/dev/null 2>&1; then \
		codesign --force --deep --sign "$(IDENTITY)" --options runtime $(BUNDLE); \
	else \
		echo "warning: '$(IDENTITY)' cert missing (run make cert); ad-hoc signing"; \
		codesign --force --deep --sign - $(BUNDLE); \
	fi

# Downloadable build for GitHub Releases: one universal (Apple silicon + Intel) binary, ad-hoc signed
# (a self-signed identity would mean nothing on someone else's Mac). scripts/install.sh fetches it.
DIST     := $(BUILD)/dist
dist: app
	swift build -c release --product $(APP) --triple x86_64-apple-macosx14.0
	lipo -create .build/arm64-apple-macosx/release/$(APP) .build/x86_64-apple-macosx/release/$(APP) \
		-output $(BUNDLE)/Contents/MacOS/$(APP)
	codesign --force --deep --sign - $(BUNDLE)
	rm -rf $(DIST) && mkdir -p $(DIST)
	ditto -c -k --keepParent $(BUNDLE) $(DIST)/$(APP).zip
	@lipo -archs $(BUNDLE)/Contents/MacOS/$(APP); echo "Wrote $(DIST)/$(APP).zip"

# Accessibility-driven UI tests against the freshly built bundle. Quits the installed copy for the
# duration (both would fight over hotkeys and the clipboard) and relaunches it afterwards.
uitest: app
	swift build -c release --product myPasteUITests
	-pkill -x $(APP); sleep 0.5
	./$(RELEASE)/myPasteUITests $(BUNDLE); status=$$?; \
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
