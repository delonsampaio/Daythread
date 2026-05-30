//
//  ShareRoleMappingTests.swift
//  DaythreadTests
//
//  Tests for ShareRoleMapping — pure conversion between the app's MemberRole
//  and CloudKit's CKShare.ParticipantPermission, used when creating a share
//  (role → permission) and when a participant joins (permission → role).
//

import XCTest
import CloudKit
@testable import Daythread

final class ShareRoleMappingTests: XCTestCase {

    // MARK: — MemberRole → CKShare permission

    func test_adminMapsToReadWrite() {
        XCTAssertEqual(ShareRoleMapping.permission(for: .admin), .readWrite)
    }

    func test_editorMapsToReadWrite() {
        XCTAssertEqual(ShareRoleMapping.permission(for: .editor), .readWrite)
    }

    func test_viewerMapsToReadOnly() {
        XCTAssertEqual(ShareRoleMapping.permission(for: .viewer), .readOnly)
    }

    // MARK: — CKShare permission → MemberRole (joining participant)

    // The trip owner is always admin regardless of permission.
    func test_owner_mapsToAdmin_regardlessOfPermission() {
        XCTAssertEqual(ShareRoleMapping.role(forPermission: .readWrite, isOwner: true), .admin)
        XCTAssertEqual(ShareRoleMapping.role(forPermission: .readOnly, isOwner: true), .admin)
    }

    // A non-owner with read-write becomes an editor.
    func test_nonOwnerReadWrite_mapsToEditor() {
        XCTAssertEqual(ShareRoleMapping.role(forPermission: .readWrite, isOwner: false), .editor)
    }

    // A non-owner with read-only becomes a viewer.
    func test_nonOwnerReadOnly_mapsToViewer() {
        XCTAssertEqual(ShareRoleMapping.role(forPermission: .readOnly, isOwner: false), .viewer)
    }

    // Unknown / none permission defaults to the safest role: viewer.
    func test_nonOwnerUnknownPermission_defaultsToViewer() {
        XCTAssertEqual(ShareRoleMapping.role(forPermission: .none, isOwner: false), .viewer)
        XCTAssertEqual(ShareRoleMapping.role(forPermission: .unknown, isOwner: false), .viewer)
    }

    // Round trip: an editor's permission maps back to editor for a non-owner.
    func test_roundTrip_editor() {
        let permission = ShareRoleMapping.permission(for: .editor)
        XCTAssertEqual(ShareRoleMapping.role(forPermission: permission, isOwner: false), .editor)
    }

    // Round trip: a viewer's permission maps back to viewer for a non-owner.
    func test_roundTrip_viewer() {
        let permission = ShareRoleMapping.permission(for: .viewer)
        XCTAssertEqual(ShareRoleMapping.role(forPermission: permission, isOwner: false), .viewer)
    }
}
