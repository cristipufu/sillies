# Sourced by build/check scripts. Do not change the user's global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcrun --find xctest >/dev/null 2>&1; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi
