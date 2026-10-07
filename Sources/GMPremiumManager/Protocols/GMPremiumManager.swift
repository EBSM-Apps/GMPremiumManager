//
//  GMPremiumManager.swift
//  GMPremiumManager
//
//  Created by Mert Serin on 2024-10-13.
//
import Adapty
import AdaptyUI
import StoreKit

public protocol GMPremiumManager: AnyObject {
    // Public API
    var paywalls: PremiumManagerPaywall { get set}
    var configurationBuilder: AdaptyConfiguration.Builder? { get set }

    func activate(appInstanceId: String?) async throws
    func fetchAllPaywalls(for placements: [any Placements], locale: String?, flowConfigurationOptions: PremiumManagerFlowConfigurationOptions) async throws
    func getPaywall(with placement: any Placements) -> PremiumManagerModel?
    func fetchPaywall(for placement: any Placements, locale: String?) async throws -> AdaptyFlow?
    func fetchPaywallConfiguration(
        for paywall: AdaptyFlow,
        locale: String?,
        products: [AdaptyPaywallProduct]?,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions
    ) async throws -> AdaptyUI.FlowConfiguration

    func purchase(with product: AdaptyPaywallProduct) async throws -> AdaptyPurchaseResult
    func restorePurchases() async throws -> AdaptyProfile

    func fetchProfile() async throws -> AdaptyProfile

    /// Logs the user in with your own user id (`Adapty.identify`).
    func identify(customerUserId: String) async throws

    func logPaywallOpen(for paywall: AdaptyFlow) async throws

    /// Observer mode: reports a transaction your own StoreKit code bought and verified, with the
    /// paywall variation that sold it (`Adapty.reportTransaction`).
    func reportTransaction(_ transaction: StoreKit.Transaction, variationId: String?) async throws

    /// Loads one placement's flow, products and Paywall Builder configuration. Nil when the
    /// placement has no flow.
    func fetchPaywallModel(
        for placement: any Placements,
        locale: String?,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions
    ) async throws -> PremiumManagerModel?

    func checkSubscriptionStatus(profile: AdaptyProfile) -> [String: AdaptyProfile.AccessLevel]

    func isActivated() -> Bool
}

public extension GMPremiumManager {
    /// Default for implementations written before `identify` existed.
    func identify(customerUserId: String) async throws {
        try await Adapty.identify(customerUserId)
    }

    /// Default for implementations written before observer-mode reporting existed.
    func reportTransaction(_ transaction: StoreKit.Transaction, variationId: String?) async throws {
        try await Adapty.reportTransaction(transaction, withVariationId: variationId)
    }

    /// Default for implementations written before single-placement loading existed.
    func fetchPaywallModel(
        for placement: any Placements,
        locale: String?,
        flowConfigurationOptions: PremiumManagerFlowConfigurationOptions
    ) async throws -> PremiumManagerModel? {
        guard let paywall = try await fetchPaywall(for: placement, locale: locale) else { return nil }
        let products = try await Adapty.getPaywallProducts(flow: paywall)
        let isPaywallBuilderEnabled = paywall.hasViewConfiguration
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

    func fetchAllPaywalls(
        for placements: [any Placements],
        locale: String? = nil
    ) async throws {
        try await fetchAllPaywalls(
            for: placements,
            locale: locale,
            flowConfigurationOptions: .default
        )
    }

    func fetchPaywallConfiguration(
        for paywall: AdaptyFlow,
        locale: String? = nil,
        products: [AdaptyPaywallProduct]? = nil
    ) async throws -> AdaptyUI.FlowConfiguration {
        try await fetchPaywallConfiguration(
            for: paywall,
            locale: locale,
            products: products,
            flowConfigurationOptions: .default
        )
    }
}
