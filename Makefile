.PHONY: build debug run preview test check gui-check lint stress clean

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

stress:
	bash scripts/test-stress.sh

lint:
	swift format lint --strict --recursive Package.swift Sources Tests Tools/ArchitectureCheck scripts/make-icon.swift
	bash -n scripts/build-app.sh scripts/test.sh scripts/toolchain.sh scripts/check-main-thread.sh scripts/test-stress.sh
	bash scripts/check-main-thread.sh

check: lint test debug
	build/Sillies.app/Contents/MacOS/Sillies --validate-catalog

gui-check: check
	build/Sillies.app/Contents/MacOS/Sillies --smoke-test
	build/Sillies.app/Contents/MacOS/Sillies --presentation-test
	build/Sillies.app/Contents/MacOS/Sillies --window-test --without-accessibility
	build/Sillies.app/Contents/MacOS/Sillies --drag-latency-test --without-accessibility

clean:
	swift package clean
