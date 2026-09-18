import AppKit
import Foundation
import TunaKit

public final class TwoDoCatalog: NSObject, Catalog {
  public let identifier: String
  public let name: String
  public let objects: [CatalogItem] = [TwoDoFocusListItem()]

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    super.init()
  }

  public func scan() async {
    reportScanFinished()
  }
}

final class TwoDoFocusListItem: CatalogItem, CopyRepresentationProviding,
  TextValueProviding, @unchecked Sendable
{
  init() {
    super.init(id: "twodo.focus.today", title: "2Do Today", type: .entity)
    typeID = .twoDoFocusList
  }

  var textValue: String { TwoDoURLBuilder.todayURL.absoluteString }
  var copyRepresentation: String? { textValue }

  override var detail: String? { "Open the Today Focus List in 2Do" }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol("sun.max")
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }
}

extension TypeID {
  static let twoDoFocusList = TypeID("com.tuna.type.twodo-focus-list")
}
