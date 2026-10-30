.PHONY: build debug run preview test check gui-check playful-gui-check lint stress race-check clean

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

race-check:
	bash scripts/test-races.sh

lint:
	swift format lint --strict --recursive Package.swift Sources Tests Tools/ArchitectureCheck Tools/SpeechBenchmark scripts/make-icon.swift
	bash -n scripts/build-app.sh scripts/test.sh scripts/toolchain.sh scripts/check-main-thread.sh scripts/test-stress.sh scripts/test-races.sh scripts/test-downloaded-speech.sh
	bash scripts/check-main-thread.sh

check: lint test debug
	build/Sillies.app/Contents/MacOS/Sillies --validate-catalog

gui-check: check
	build/Sillies.app/Contents/MacOS/Sillies --smoke-test
	build/Sillies.app/Contents/MacOS/Sillies --presentation-test
	build/Sillies.app/Contents/MacOS/Sillies --window-test --without-accessibility
	build/Sillies.app/Contents/MacOS/Sillies --drag-latency-test --without-accessibility

playful-gui-check: debug
	python3 scripts/test-playful-scenes.py

clean:
	swift package clean
