import Testing
import Foundation
@testable import SocialAccountVaultCore

@Suite("Navigation and Platform Enum Tests")
struct NavigationTests {

    @Test("Verify all 11 sidebar navigation destinations exist")
    func testNavigationItemsCount() {
        let items = NavigationItem.allCases
        #expect(items.count == 11)

        let expectedCases: [NavigationItem] = [
            .dashboard,
            .allAccounts,
            .youtube,
            .instagram,
            .tiktok,
            .facebook,
            .email,
            .affiliateMonetization,
            .websiteDomain,
            .archive,
            .settings
        ]
        #expect(items == expectedCases)
    }

    @Test("Verify SF Symbols exist for every navigation destination")
    func testNavigationIconNames() {
        for item in NavigationItem.allCases {
            #expect(!item.iconName.isEmpty)
        }
    }

    @Test("Verify core 8 digital platforms exist with correct default orders")
    func testPlatformTypes() {
        let platforms = PlatformType.allCases
        #expect(platforms.count == 8)

        let expected: [PlatformType] = [
            .youtube,
            .instagram,
            .tiktok,
            .facebook,
            .email,
            .shopeeAffiliate,
            .googleAdSense,
            .websiteDomain
        ]
        #expect(platforms == expected)

        for (index, platform) in platforms.enumerated() {
            #expect(platform.defaultOrder == index + 1)
            #expect(!platform.iconName.isEmpty)
            #expect(platform.defaultDashboardURL.hasPrefix("https://"))
        }
    }

    @Test("Verify navigation section groupings")
    func testNavigationSectionGroups() {
        #expect(NavigationItem.dashboard.sectionGroup == .overview)
        #expect(NavigationItem.allAccounts.sectionGroup == .overview)

        #expect(NavigationItem.youtube.sectionGroup == .platforms)
        #expect(NavigationItem.instagram.sectionGroup == .platforms)
        #expect(NavigationItem.tiktok.sectionGroup == .platforms)
        #expect(NavigationItem.facebook.sectionGroup == .platforms)
        #expect(NavigationItem.email.sectionGroup == .platforms)
        #expect(NavigationItem.affiliateMonetization.sectionGroup == .platforms)
        #expect(NavigationItem.websiteDomain.sectionGroup == .platforms)

        #expect(NavigationItem.archive.sectionGroup == .system)
        #expect(NavigationItem.settings.sectionGroup == .system)
    }

    @Test("Verify affiliate & monetization groups Shopee and AdSense")
    func testAffiliateMonetizationMapping() {
        let targets = NavigationItem.affiliateMonetization.targetPlatformTypes
        #expect(targets.count == 2)
        #expect(targets.contains(.shopeeAffiliate))
        #expect(targets.contains(.googleAdSense))
    }

    @Test("Verify navigation view model state updates")
    @MainActor
    func testNavigationViewModel() {
        let viewModel = NavigationViewModel(selectedItem: .dashboard)
        #expect(viewModel.selectedItem == .dashboard)

        viewModel.select(.youtube)
        #expect(viewModel.selectedItem == .youtube)

        viewModel.searchText = "my_channel"
        #expect(viewModel.searchText == "my_channel")

        viewModel.clearSearch()
        #expect(viewModel.searchText.isEmpty)
    }

    @Test("Verify MainNavigationView presentation platform context mapping")
    @MainActor
    func testMainNavigationViewPlatformContextMapping() {
        #expect(MainNavigationView.defaultPlatform(for: nil) == .youtube)
        #expect(MainNavigationView.defaultPlatform(for: .dashboard) == .youtube)
        #expect(MainNavigationView.defaultPlatform(for: .allAccounts) == .youtube)
        #expect(MainNavigationView.defaultPlatform(for: .youtube) == .youtube)
        #expect(MainNavigationView.defaultPlatform(for: .instagram) == .instagram)
        #expect(MainNavigationView.defaultPlatform(for: .tiktok) == .tiktok)
        #expect(MainNavigationView.defaultPlatform(for: .facebook) == .facebook)
        #expect(MainNavigationView.defaultPlatform(for: .email) == .email)
        #expect(MainNavigationView.defaultPlatform(for: .affiliateMonetization) == .shopeeAffiliate)
        #expect(MainNavigationView.defaultPlatform(for: .websiteDomain) == .websiteDomain)
        #expect(MainNavigationView.defaultPlatform(for: .archive) == .youtube)
        #expect(MainNavigationView.defaultPlatform(for: .settings) == .youtube)
    }

    @Test("Verify AddAccountView view model and platform initialization")
    @MainActor
    func testAddAccountViewPlatformInitialization() {
        let viewDefault = AddAccountView(initialPlatform: .youtube)
        #expect(viewDefault.mode == .create(initialPlatform: .youtube))
        #expect(viewDefault.isEditMode == false)

        let viewDomain = AddAccountView(initialPlatform: .websiteDomain)
        #expect(viewDomain.mode == .create(initialPlatform: .websiteDomain))
        #expect(viewDomain.isEditMode == false)

        let viewShopee = AddAccountView(initialPlatform: .shopeeAffiliate)
        #expect(viewShopee.mode == .create(initialPlatform: .shopeeAffiliate))
        #expect(viewShopee.isEditMode == false)
    }

    @Test("Verify DashboardPlaceholderView initialization and navigation routing closure")
    @MainActor
    func testDashboardNavigationRouting() {
        var navigatedDestination: NavigationItem?
        let dashboard = DashboardPlaceholderView { destination in
            navigatedDestination = destination
        }
        #expect(navigatedDestination == nil)

        dashboard.onNavigate?(.allAccounts)
        #expect(navigatedDestination == .allAccounts)

        dashboard.onNavigate?(.youtube)
        #expect(navigatedDestination == .youtube)

        dashboard.onNavigate?(.affiliateMonetization)
        #expect(navigatedDestination == .affiliateMonetization)
    }
}
