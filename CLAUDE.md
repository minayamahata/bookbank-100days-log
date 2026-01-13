# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build (Debug)
xcodebuild build -scheme BookBank -configuration Debug

# Build (Release)
xcodebuild build -scheme BookBank -configuration Release

# Run all tests
xcodebuild test -scheme BookBank -configuration Debug

# Run unit tests only
xcodebuild test -scheme BookBank -configuration Debug -only-testing=BookBankTests

# Run UI tests only
xcodebuild test -scheme BookBank -configuration Debug -only-testing=BookBankUITests

# Open in Xcode
open BookBank.xcodeproj
```

## Architecture

BookBank is an iOS app built with SwiftUI targeting iOS 26.2+.

**Project Structure:**
- `BookBank/` - Main app target with SwiftUI views
- `BookBankTests/` - Unit tests using Swift Testing framework
- `BookBankUITests/` - UI tests using XCTest framework

**Entry Point:** `BookBankApp.swift` contains the `@main` entry point with a `WindowGroup` containing `ContentView`.

**Key Swift Settings:**
- Swift 5.0 with MainActor default isolation
- Approachable Concurrency enabled
- No external dependencies (native Apple frameworks only)

**Bundle ID:** `ayame-inc.BookBank`

## Design Policy
- 設計資料（docs配下）は、最終仕様ではなく思考整理のための事前設計である
- 設計に不備・矛盾・改善点がある場合は、必ず指摘し、理由と代替案を提示すること
- 「設計どおりに実装」よりも、「iOS / SwiftData として健全な設計」を優先する
- 非エンジニアによる設計であることを前提に、保守性・拡張性を重視した提案を行う
