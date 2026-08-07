//
//  BookBankUITestsLaunchTests.swift
//  BookBankUITests
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import XCTest

final class BookBankUITestsLaunchTests: XCTestCase {

    /// Xcodeテンプレートの既定は `true`（UI構成ごとに `testLaunch` を繰り返す）だが、
    /// 起動時のスプラッシュが5秒あるためスキーム全体のテストが15分近くかかっていた。
    /// 起動スモークとしては1回で足りるので繰り返さない
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
