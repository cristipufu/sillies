BUILD_DIR ?= build

.PHONY: build debug run preview test check gui-check playful-gui-check lint stress race-check clean

build:
	SILLIES_BUILD_DIRECTORY="$(abspath $(BUILD_DIR))" bash scripts/build-app.sh release

debug:
	SILLIES_BUILD_DIRECTORY="$(abspath $(BUILD_DIR))" bash scripts/build-app.sh debug

run: build
	open $(BUILD_DIR)/Sillies.app

preview: debug
	open $(BUILD_DIR)/Sillies.app --args --preview

test:
	bash scripts/test.sh

stress:
	bash scripts/test-stress.sh

race-check:
	bash scripts/test-races.sh

lint:
	swift format lint --strict --recursive Package.swift Sources Tests Tools/ArchitectureCheck Tools/SpeechBenchmark Tools/TextModelBenchmark scripts/make-icon.swift
	bash -n scripts/build-app.sh scripts/test.sh scripts/toolchain.sh scripts/check-main-thread.sh scripts/test-stress.sh scripts/test-races.sh scripts/test-downloaded-speech.sh
	python3 -B -m unittest discover -s Tests -p 'test_*.py'
	bash scripts/check-main-thread.sh

check: lint test debug
	$(BUILD_DIR)/Sillies.app/Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference --self-test
	$(BUILD_DIR)/Sillies.app/Contents/MacOS/Sillies --validate-catalog
	$(BUILD_DIR)/Sillies.app/Contents/MacOS/Sillies --app-window-test --without-accessibility

gui-check: check
	$(BUILD_DIR)/Sillies.app/Contents/MacOS/Sillies --smoke-test
	$(BUILD_DIR)/Sillies.app/Contents/MacOS/Sillies --presentation-test
	$(BUILD_DIR)/Sillies.app/Contents/MacOS/Sillies --window-test --without-accessibility
	$(BUILD_DIR)/Sillies.app/Contents/MacOS/Sillies --drag-latency-test --without-accessibility

playful-gui-check: debug
	python3 scripts/test-playful-scenes.py

clean:
	swift package clean
