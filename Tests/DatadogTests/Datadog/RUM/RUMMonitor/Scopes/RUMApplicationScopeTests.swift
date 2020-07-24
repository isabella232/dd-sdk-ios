/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMApplicationScopeTests: XCTestCase {
    func testRootContext() {
        let scope = RUMApplicationScope(
            rumApplicationID: "abc-123",
            dependencies: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewURI)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstViewIsStarted_itStartsNewSession() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny())

        XCTAssertNil(scope.sessionScope)
        XCTAssertTrue(scope.process(command: .startView(id: UIViewController(), attributes: [:], time: .mockAny())))
        XCTAssertNotNil(scope.sessionScope)
    }

    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny())
        var currentTime = Date()
        let view = UIViewController()

        _ = scope.process(command: .startView(id: view, attributes: [:], time: currentTime))
        let firstSessionUUID = try XCTUnwrap(scope.sessionScope?.context.sessionID)
        let firstsSessionViewScopes = try XCTUnwrap((scope.sessionScope as? RUMSessionScope)?.viewScopes)

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        _ = scope.process(command: .addUserAction(userAction: .tap, attributes: [:], time: currentTime))
        let secondSessionUUID = try XCTUnwrap(scope.sessionScope?.context.sessionID)
        let secondSessionViewScopes = try XCTUnwrap((scope.sessionScope as? RUMSessionScope)?.viewScopes)

        XCTAssertNotEqual(firstSessionUUID, secondSessionUUID)
        XCTAssertEqual(firstsSessionViewScopes.count, secondSessionViewScopes.count)
        XCTAssertTrue((secondSessionViewScopes.first as? RUMViewScope)?.identity === view)
    }

    func testUntilSessionIsStarted_itIgnoresOtherCommands() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny())

        XCTAssertTrue(scope.process(command: .stopView(id: UIViewController(), attributes: [:], time: .mockAny())))
        XCTAssertTrue(scope.process(command: .addUserAction(userAction: .tap, attributes: [:], time: .mockAny())))
        XCTAssertTrue(scope.process(command: .startResource(resourceName: .mockAny(), attributes: [:], time: .mockAny())))
        XCTAssertNil(scope.sessionScope)
    }
}