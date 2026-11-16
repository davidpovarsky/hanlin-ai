#if HANLIN_A2UI_POC
import A2UICore
import BasicCatalog

/// Schema-only extension of the exact official v1 catalog. The official SDK still owns
/// validation, bindings, graph identity and rendering dispatch. Basic Catalog is unchanged.
enum HanlinMediaCatalog {
    static let youTube = AnyComponentAPI(name: "YouTube", schema: try! .init(instance: """
    {
      "type":"object",
      "properties":{
        "id":{"type":"string","maxLength":128},
        "component":{"const":"YouTube"},
        "url":{"$ref":"#/$defs/DynamicString"}
      },
      "$defs":{"DynamicString":{"anyOf":[
        {"type":"string","maxLength":2048},
        {"type":"object","properties":{"@path":{"type":"string","maxLength":512}},
         "required":["@path"],"additionalProperties":false}
      ]}},
      "required":["component","url"],
      "additionalProperties":false
    }
    """))

    static func makeCatalog() -> AnyCatalog {
        var catalog = BasicCatalog.makeCatalog(version: .v10)
        catalog.id = HanlinA2UIIngress.mediaCatalogID
        catalog.components[youTube.name] = youTube
        return catalog
    }
}
#endif
