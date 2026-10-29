# SwiftPM build. The local Command Line Tools ship two stale files from an older install
# (include/swift/module.modulemap and PackageDescription's .private.swiftinterface) that break
# compilation; build/clt-overlay.yaml hides them per-invocation, no sudo needed.
APP      := myPaste
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
INSTALL  := $(HOME)/Applications/$(APP).app
IDENTITY ?= myPaste Dev
OVERLAY  := $(CURDIR)/$(BUILD)/clt-overlay.yaml
PD_SRC   := /Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule
PD_COPY  := $(BUILD)/PackageDescription.swiftmodule
SPMFLAGS := -Xmanifest -vfsoverlay -Xmanifest $(OVERLAY) -Xswiftc -vfsoverlay -Xswiftc $(OVERLAY)
RELEASE  := .build/release
# Swift Testing lives outside the default search path in a Command Line Tools-only install.
CLT_FW   := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TESTFLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) \
             -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib

.PHONY: all app test install run cert clean overlay

all: app

# PackageDescription with the current public interface standing in for the stale private one.
overlay:
	@mkdir -p $(PD_COPY)
	@for a in arm64 x86_64; do \
		cp $(PD_SRC)/$$a-apple-macos.swiftinterface $(PD_COPY)/$$a-apple-macos.swiftinterface; \
		cp $(PD_SRC)/$$a-apple-macos.swiftinterface $(PD_COPY)/$$a-apple-macos.private.swiftinterface; \
		cp $(PD_SRC)/$$a-apple-macos.swiftdoc $(PD_COPY)/ 2>/dev/null || true; \
	done
	@sed "s|@ROOT@|$(CURDIR)|" build-support/clt-overlay.yaml.in > $(OVERLAY)

test: overlay
	swift test $(SPMFLAGS) $(TESTFLAGS)

app: overlay
	swift build -c release --product $(APP) $(SPMFLAGS)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(RELEASE)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	for b in $(RELEASE)/*.bundle; do [ -e "$$b" ] && cp -R "$$b" $(BUNDLE)/Contents/Resources/; done; true
	@if security find-certificate -c "$(IDENTITY)" >/dev/null 2>&1; then \
		codesign --force --deep --sign "$(IDENTITY)" --options runtime $(BUNDLE); \
	else \
		echo "warning: '$(IDENTITY)' cert missing (run make cert); ad-hoc signing"; \
		codesign --force --deep --sign - $(BUNDLE); \
	fi

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
