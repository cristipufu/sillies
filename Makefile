.PHONY: build debug run preview test check gui-check lint clean

build:
	bash scripts/build-app.sh release

debug:
	bash scripts/build-app.sh debug

run: build
	open build/Sillies.app

preview: debug
	open build/Sillies.app --args --preview

test:
	bash scripts/test.sh

lint:
	swift format lint --strict --recursive Package.swift Sources Tests scripts/make-icon.swift
	bash -n scripts/build-app.sh scripts/test.sh scripts/toolchain.sh

check: lint test debug
	build/Sillies.app/Contents/MacOS/Sillies --validate-catalog

gui-check: check
	build/Sillies.app/Contents/MacOS/Sillies --smoke-test
	build/Sillies.app/Contents/MacOS/Sillies --presentation-test
	build/Sillies.app/Contents/MacOS/Sillies --window-test --without-accessibility
	build/Sillies.app/Contents/MacOS/Sillies --drag-latency-test --without-accessibility

clean:
	swift package clean
