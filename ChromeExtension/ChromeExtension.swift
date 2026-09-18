import Foundation
import TunaKit

@objc(ChromeExtension)
public final class ChromeExtension: Extension {
  public override var declaration: ExtensionDeclaration? {
    ExtensionDeclaration(
      metadata: ExtensionMetadata(
        displayName: "Google Chrome",
        author: "Tuna",
        description: "Chrome bookmarks, profiles, and browser commands.",
        iconName: "globe"
      ),
      compatibility: ExtensionDeclarationCompatibility(minTuna: "0.96", minTunaKit: "1.22.0"),
      catalogs: [
        CatalogDeclaration(
          id: "chrome.bookmarks", type: ChromeBookmarksCatalog.self, name: "Chrome Bookmarks",
          presentation: .source, enabledByDefault: true),
        CatalogDeclaration(
          id: "chrome.bookmarks.browse", type: ChromeBookmarksBrowseCatalog.self,
          name: "Chrome Bookmarks", presentation: .browseRoot(contents: "chrome.bookmarks"),
          enabledByDefault: true),
        CatalogDeclaration(
          id: "chrome.profiles", type: ChromeProfilesCatalog.self, name: "Chrome Profiles",
          presentation: .source, enabledByDefault: true),
        CatalogDeclaration(
          id: "chrome.profiles.browse", type: ChromeProfilesBrowseCatalog.self,
          name: "Chrome Profiles", presentation: .browseRoot(contents: "chrome.profiles"),
          enabledByDefault: true),
        CatalogDeclaration(
          id: "chrome.utilities", type: ChromeUtilitiesCatalog.self, name: "Chrome Utilities",
          presentation: .source, enabledByDefault: true),
      ],
      actionCatalogs: [
        ActionCatalogDeclaration(
          id: "chrome.actions", type: ChromeActionsCatalog.self, name: "Chrome Actions")
      ],
      typeRegistrations: [
        TypeRegistrationDefinition(
          typeID: .chromeURL,
          displayName: "Chrome URLs",
          inheritsFrom: [.url]
        )
      ],
      defaultActionRankings: [
        DefaultActionRankingDefinition(
          typeID: .chromeURL,
          actions: [
            ActionReference(catalogIdentifier: "chrome.actions", actionID: "open-in-chrome"),
            ActionReference(catalogIdentifier: "chrome.actions", actionID: "copy-url"),
          ]
        )
      ],
      appBrowseEnrichments: [
        AppBrowseEnrichmentDefinition(
          bundleIdentifiers: [ChromeBrowser.bundleIdentifier],
          entries: [
            AppBrowseEnrichmentEntryDefinition(
              catalogIdentifier: "chrome.bookmarks.browse", title: "Bookmarks"),
            AppBrowseEnrichmentEntryDefinition(
              catalogIdentifier: "chrome.profiles.browse", title: "Profiles"),
          ]
        )
      ],
      appActionEnrichments: [
        AppActionEnrichmentDefinition(
          bundleIdentifiers: [ChromeBrowser.bundleIdentifier],
          catalogIdentifiers: ["chrome.actions"]
        )
      ]
    )
  }
}

extension TypeID {
  static let chromeURL = TypeID("com.tuna.type.chrome-url")
}
