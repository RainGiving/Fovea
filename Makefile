APP_NAME := Fovea
PLIST := Sources/FoveaApp/Resources/Info.plist
DECLARED_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(PLIST))
VERSION ?= $(DECLARED_VERSION)

.PHONY: build test audit check dmg install default-app clean version release

build:
	./scripts/build-app.sh

test:
	swift test --disable-sandbox

audit:
	swift scripts/audit.swift --strict

check: test audit

dmg:
	./scripts/package-dmg.sh

install:
	./scripts/install-app.sh

default-app:
	swift scripts/set-default-image-app.swift

clean:
	rm -rf .build

version:
	@echo $(VERSION)

release: check
	@test "$(VERSION)" = "$(DECLARED_VERSION)" || { echo "$(PLIST) declares $(DECLARED_VERSION). Update it before packaging $(VERSION)." >&2; exit 1; }
	$(MAKE) dmg
