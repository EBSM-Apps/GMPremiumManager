import Adapty
import AdaptyUI
import XCTest
@testable import GMPremiumManager

/// Records identify calls; everything that would reach Adapty's servers throws.
private final class FakeImplementation: GMPremiumManager, @unchecked Sendable {
    struct Unused: Error {}

    var paywalls: PremiumManagerPaywall = [:]
    var configurationBuilder: AdaptyConfiguration.Builder?
    var activated = false
    var activateCalls = 0
    var identified: [String] = []

    func activate(appInstanceId: String?) async throws {
        activateCalls += 1
        // Long enough for a second caller to arrive mid-activation.
        try await Task.sleep(nanoseconds: 50_000_000)
        activated = true
    }
    func fetchAllPaywalls(for placements: [any Placements], locale: String?, flowConfigurationOptions: PremiumManagerFlowConfigurationOptions) async throws {}
    func getPaywall(with placement: any Placements) -> PremiumManagerModel? { nil }
    func fetchPaywall(for placement: any Placements, locale: String?) async throws -> AdaptyFlow? { nil }
    func fetchPaywallConfiguration(for paywall: AdaptyFlow, locale: String?, products: [AdaptyPaywallProduct]?, flowConfigurationOptions: PremiumManagerFlowConfigurationOptions) async throws -> AdaptyUI.FlowConfiguration { throw Unused() }
    func purchase(with product: AdaptyPaywallProduct) async throws -> AdaptyPurchaseResult { throw Unused() }
    func restorePurchases() async throws -> AdaptyProfile { throw Unused() }
    func fetchProfile() async throws -> AdaptyProfile { throw Unused() }
    func logPaywallOpen(for paywall: AdaptyFlow) async throws {}
    func checkSubscriptionStatus(profile: AdaptyProfile) -> [String: AdaptyProfile.AccessLevel] { [:] }
    func isActivated() -> Bool { activated }
    func identify(customerUserId: String) async throws { identified.append(customerUserId) }
}

final class GMPremiumManagerTests: XCTestCase {
    /// Configure without a user id (anonymous), then log in before activation:
    /// the id is applied once Adapty is active.
    func testIdentifyBeforeActivationAppliesAfterActivate() async throws {
        let fake = FakeImplementation()
        let manager = PremiumManager(key: "public_live_test", implementation: fake)
        try await manager.identify(customerUserId: "user-1")
        XCTAssertEqual(fake.identified, [], "nothing reaches Adapty before activation")
        try await manager.activate(appInstanceId: nil)
        XCTAssertEqual(fake.identified, ["user-1"])
    }

    /// After activation, identify goes straight to Adapty.
    func testIdentifyAfterActivation() async throws {
        let fake = FakeImplementation()
        let manager = PremiumManager(key: "public_live_test", customerUserId: "user-1", implementation: fake)
        try await manager.activate(appInstanceId: nil)
        XCTAssertEqual(fake.identified, [], "the configured id needs no identify")
        try await manager.identify(customerUserId: "user-2")
        XCTAssertEqual(fake.identified, ["user-2"])
    }

    /// A second activate while the first runs (an app building its purchase
    /// client twice at launch) waits for it: Adapty throws
    /// `activateOnceError` on a second `Adapty.activate`.
    func testConcurrentActivateActivatesOnce() async throws {
        let fake = FakeImplementation()
        let manager = PremiumManager(key: "public_live_test", implementation: fake)
        async let first: Void = manager.activate(appInstanceId: nil)
        async let second: Void = manager.activate(appInstanceId: nil)
        _ = try await (first, second)
        XCTAssertEqual(fake.activateCalls, 1)
    }
}
