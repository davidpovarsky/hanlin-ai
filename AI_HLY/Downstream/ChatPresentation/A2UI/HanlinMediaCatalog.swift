#if HANLIN_A2UI_POC
import A2UICore
import BasicCatalog

/// Schema-only extension of the exact official v1 catalog. The official SDK still owns
/// validation, bindings, graph identity and rendering dispatch. Basic Catalog is unchanged.
enum HanlinMediaCatalog {
    static let modelGuidance = """
    When rich content is useful, use the existing A2UI 1.0 response parts or present_a2ui tool.
    Approved media catalog: https://hanlin.ai/a2ui/catalogs/media/v1 (includes the official basic catalog).
    ImageGallery has items (1...10), each with a stable id, HTTPS url, HTTPS sourceUrl, nonempty description (alt text), and optional title.
    LinkPreview has HTTPS url and optional title, description, thumbnailUrl. It can retrieve a preview from that source after the user's explicit request.
    YouTube has url; official Image, Video and AudioPlayer retain their official schemas.
    Supply only image and source URLs actually returned by a source or tool. Never invent image URLs, attribution, a license, or claims that a source was verified.
    Preserve each image's source and alt text together; otherwise use ordinary text/source links.
    Use createSurface, updateDataModel and updateComponents envelopes with version 1.0 and the approved catalogId. The root component id is root.
    Media preview, zoom and opening a source are local user actions, not permission to run another tool. Do not embed scripts or arbitrary HTML.
    """

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

    static let imageGallery = AnyComponentAPI(name: "ImageGallery", schema: try! .init(instance: """
    {
      "type":"object",
      "properties":{
        "id":{"type":"string","maxLength":128},
        "component":{"const":"ImageGallery"},
        "items":{"type":"array","minItems":1,"maxItems":10,"items":{
          "type":"object",
          "properties":{
            "id":{"type":"string","minLength":1,"maxLength":128},
            "url":{"$ref":"#/$defs/DynamicString"},
            "sourceUrl":{"$ref":"#/$defs/DynamicString"},
            "title":{"$ref":"#/$defs/DynamicString"},
            "description":{"$ref":"#/$defs/DynamicString"}
          },
          "required":["id","url","sourceUrl","description"],
          "additionalProperties":false
        }}
      },
      "$defs":{"DynamicString":{"anyOf":[
        {"type":"string","maxLength":2048},
        {"type":"object","properties":{"@path":{"type":"string","maxLength":512}},
         "required":["@path"],"additionalProperties":false}
      ]}},
      "required":["component","items"],
      "additionalProperties":false
    }
    """))

    static let linkPreview = AnyComponentAPI(name: "LinkPreview", schema: try! .init(instance: """
    {
      "type":"object",
      "properties":{
        "id":{"type":"string","maxLength":128},
        "component":{"const":"LinkPreview"},
        "url":{"$ref":"#/$defs/DynamicString"},
        "title":{"$ref":"#/$defs/DynamicString"},
        "description":{"$ref":"#/$defs/DynamicString"},
        "thumbnailUrl":{"$ref":"#/$defs/DynamicString"}
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
        catalog.components[imageGallery.name] = imageGallery
        catalog.components[linkPreview.name] = linkPreview
        return catalog
    }
}
#endif
