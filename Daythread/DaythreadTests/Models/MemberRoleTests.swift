//
//  MemberRoleTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/26/26.
//

import XCTest
@testable import Daythread

final class MemberRoleTests: XCTestCase {

    func testAdminCanEdit() {
        XCTAssertTrue(MemberRole.admin.canEdit)
    }

    func testEditorCanEdit() {
        XCTAssertTrue(MemberRole.editor.canEdit)
    }

    func testViewerCannotEdit() {
        XCTAssertFalse(MemberRole.viewer.canEdit)
    }

    func testOnlyAdminIsAdmin() {
        XCTAssertTrue(MemberRole.admin.isAdmin)
        XCTAssertFalse(MemberRole.editor.isAdmin)
        XCTAssertFalse(MemberRole.viewer.isAdmin)
    }

    func testRawValueRoundTrip() {
        for role in MemberRole.allCases {
            XCTAssertEqual(MemberRole(rawValue: role.rawValue), role)
        }
    }
}
