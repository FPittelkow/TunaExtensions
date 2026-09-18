import Foundation
import TunaKit

@objc(TwoDoExtension)
public final class TwoDoExtension: Extension {
  public override var declaration: ExtensionDeclaration? {
    ExtensionDeclaration(
      metadata: ExtensionMetadata(
        displayName: "2Do",
        author: "TunaExtensions Contributors",
        description: "Open the Today Focus List in 2Do.",
        iconName: "checkmark.circle"
      ),
      compatibility: ExtensionDeclarationCompatibility(minTuna: "0.95", minTunaKit: "1.21.0"),
      catalogs: [
        CatalogDeclaration(
          id: "twodo", type: TwoDoCatalog.self, name: "2Do Focus Lists", presentation: .source,
          enabledByDefault: true, initialGlobalScope: .all)
      ],
      actionCatalogs: [
        ActionCatalogDeclaration(
          id: "twodo.actions", type: TwoDoActionsCatalog.self, name: "2Do Actions")
      ],
      typeRegistrations: [
        TypeRegistrationDefinition(
          typeID: .twoDoFocusList, displayName: "2Do Focus Lists", inheritsFrom: [.entity])
      ],
      defaultActionRankings: [
        DefaultActionRankingDefinition(
          typeID: .twoDoFocusList,
          actions: [ActionReference(catalogIdentifier: "twodo.actions", actionID: "show-in-2do")])
      ]
    )
  }
}
