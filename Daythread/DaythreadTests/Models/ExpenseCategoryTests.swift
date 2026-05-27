//
//  ExpenseCategoryTests.swift
//  DaythreadTests
//
//  Created by Delon Sampaio on 5/26/26.
//

import XCTest
@testable import Daythread

final class ExpenseCategoryTests: XCTestCase {

    func testAllCasesHaveDisplayName() {
        for category in ExpenseCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category) has empty displayName")
        }
    }

    func testAllCasesHaveSystemImage() {
        for category in ExpenseCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty, "\(category) has empty systemImage")
        }
    }

    func testRawValueRoundTrip() {
        for category in ExpenseCategory.allCases {
            XCTAssertEqual(ExpenseCategory(rawValue: category.rawValue), category)
        }
    }
}
