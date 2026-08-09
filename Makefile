APP_NAME := Fovea
PLIST := Sources/FoveaApp/Resources/Info.plist
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(PLIST))

.PHONY: build test audit check dmg install clean version release

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

clean:
	rm -rf .build

version:
	@echo $(VERSION)

release: check dmg
	@test -z "$(shell git status --porcelain)" || (echo "Commit or discard local changes before creating a release." >&2; exit 1)
	@if git rev-parse --verify --quiet "refs/tags/v$(VERSION)" >/dev/null; then echo "Tag v$(VERSION) already exists." >&2; exit 1; fi
	git tag -a "v$(VERSION)" -m "$(APP_NAME) $(VERSION)"
	git push origin "v$(VERSION)"
