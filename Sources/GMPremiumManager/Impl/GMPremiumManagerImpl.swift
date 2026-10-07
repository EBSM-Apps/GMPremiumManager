//
//  File.swift
//  GMPremiumManager
//
//  Created by Mert Serin on 2024-10-13.
//

import Foundation
import Adapty
import AdaptyUI
import StoreKit

final public class GMPremiumManagerImpl: GMPremiumManager {
    public var paywalls: PremiumManagerPaywall = [:]
    public var configurationBuilder: AdaptyConfiguration.Builder?

    private var isAdaptyActivated: Bool = false

    public init() {

    }

    /// Adapty and AdaptyUI each take one `activate` per process (a second
    /// throws `activateOnceError` / `activateOnce`), so a retry after a later
    /// step failed picks up from that step.
    public func activate(appInstanceId: String?) async throws {
        guard let configurationBuilder else { return }
        if await !Adapty.isActivated {
            try await Adapty.activate(with: configurationBuilder.build())
        }

        if let appInstanceId = appInstanceId {
            try await Adapty.setIntegrationIdentifier(.firebaseAppInstanceId(appInstanceId))
        }

        do {
            try await AdaptyUI.activate()
        } catch AdaptyUIError.activateOnce {
            // Active since an earlier attempt.
        }
        self.isAdaptyActivated = true
    }

    public func fetchAllPaywalls(
        for placements: [any Placements],
        locale: String? = nil,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions = .default
    ) async throws {
        do {
            let fetchedPaywalls = try await withThrowingTaskGroup(of: (String, PremiumManagerModel?).self) { group in
                for placement in placements {
                    group.addTask {
                        // A placement without a flow is skipped; a products failure fails the fetch.
                        guard let paywall = try? await self.fetchPaywall(for: placement, locale: locale) else {
                            return (placement.id, nil)
                        }
                        return (placement.id, try await self.model(for: paywall, locale: locale, flowConfigurationOptions: flowConfigurationOptions))
                    }
                }

                var results: [String: PremiumManagerModel] = [:]
                for try await (placement, model) in group {
                    if let model {
                        results[placement] = model
                    }
                }
                return results
            }

            self.paywalls = fetchedPaywalls
        } catch {
            throw PremiumManagerError.paywallFetchingError
        }
    }

    public func fetchPaywallModel(
        for placement: any Placements,
        locale: String? = nil,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions = .default
    ) async throws -> PremiumManagerModel? {
        guard let paywall = try await fetchPaywall(for: placement, locale: locale) else { return nil }
        return try await model(for: paywall, locale: locale, flowConfigurationOptions: flowConfigurationOptions)
    }

    private func model(
        for paywall: AdaptyFlow,
        locale: String?,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions
    ) async throws -> PremiumManagerModel {
        let isPaywallBuilderEnabled = paywall.hasViewConfiguration
        let products = try await Adapty.getPaywallProducts(flow: paywall)
        let configuration = isPaywallBuilderEnabled ? try? await fetchPaywallConfiguration(
            for: paywall,
            locale: locale,
            products: products,
            flowConfigurationOptions: flowConfigurationOptions
        ) : nil
        return PremiumManagerModel(paywall: paywall,
                                   products: products,
                                   rcConfigs: paywall.remoteConfigs,
                                   locale: locale,
                                   isPaywallBuilderEnabled: isPaywallBuilderEnabled,
                                   configuration: configuration)
    }

    public func getPaywall(with placement: any Placements) -> PremiumManagerModel? {
        return paywalls[placement.id] ?? nil
    }

    public func fetchPaywall(for placement: any Placements, locale: String? = nil) async throws -> AdaptyFlow? {
        try await Adapty.getFlow(placementId: placement.id)
    }

    public func fetchPaywallConfiguration(
        for paywall: AdaptyFlow,
        locale: String? = nil,
        products: [AdaptyPaywallProduct]? = nil,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions = .default
    ) async throws -> AdaptyUI.FlowConfiguration {
        try await AdaptyUI.getFlowConfiguration(
            forFlow: paywall,
            locale: locale,
            loadTimeout: flowConfigurationOptions.loadTimeout,
            products: products,
            observerModeResolver: flowConfigurationOptions.observerModeResolver,
            tagResolver: flowConfigurationOptions.tagResolver,
            timerResolver: flowConfigurationOptions.timerResolver,
            assetsResolver: flowConfigurationOptions.assetsResolver,
            systemRequestsHandler: flowConfigurationOptions.systemRequestsHandler
        )
    }

    public func logPaywallOpen(for paywall: AdaptyFlow) async throws {
        try await Adapty.logShowFlow(paywall)
    }

    public func reportTransaction(_ transaction: StoreKit.Transaction, variationId: String?) async throws {
        try await Adapty.reportTransaction(transaction, withVariationId: variationId)
    }

    public func purchase(with product: AdaptyPaywallProduct) async throws -> AdaptyPurchaseResult {
        do {
            return try await Adapty.makePurchase(product: product)
        } catch {
            throw error
        }
    }

    public func fetchProfile() async throws -> AdaptyProfile {
        return try await Adapty.getProfile()
    }

    public func restorePurchases() async throws -> AdaptyProfile {
        return try await Adapty.restorePurchases()
    }

    public func checkSubscriptionStatus(profile: AdaptyProfile) -> [String: AdaptyProfile.AccessLevel] {
        return profile.accessLevels
    }

    public func identify(customerUserId: String) async throws {
        try await Adapty.identify(customerUserId)
    }

    public func isActivated() -> Bool {
        return isAdaptyActivated
    }
}
