#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --show-sdk-path)" \
    Sources/Core/*.swift Sources/App/MediaTools.swift Tests/TestRunner.swift \
    -o build/tests/QingYouTests
build/tests/QingYouTests

# 应用状态与异步拖放也在临时目录验证，不启动界面、不触碰个人配置。
APP_SOURCES=()
for SOURCE in Sources/App/*.swift; do
    if [ "$SOURCE" != "Sources/App/EntryPoint.swift" ]; then APP_SOURCES+=("$SOURCE"); fi
done
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --show-sdk-path)" \
    Sources/Core/*.swift "${APP_SOURCES[@]}" Tests/AppIntegrationTests.swift \
    -o build/tests/QingYouAppTests
build/tests/QingYouAppTests

# 新工作台单独验证真实像素、元数据和 PDF 输出；仍只使用临时目录。
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --show-sdk-path)" \
    Sources/Core/*.swift "${APP_SOURCES[@]}" Tests/WorkspaceTests.swift \
    -o build/tests/QingYouWorkspaceTests
build/tests/QingYouWorkspaceTests

# 实际菜单、跨进程标识及图标体积回归，使用隔离配置与临时文件。
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -sdk "$(xcrun --show-sdk-path)" \
    Sources/Core/*.swift Sources/FinderExtension/*.swift Tests/FinderMenuTests.swift \
    -o build/tests/QingYouFinderTests
build/tests/QingYouFinderTests
