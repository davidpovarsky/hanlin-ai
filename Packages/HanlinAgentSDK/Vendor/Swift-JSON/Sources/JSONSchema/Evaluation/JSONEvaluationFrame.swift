// SPDX-License-Identifier: Apache-2.0
import JSON

/// Continuations are lazy: a container schedules one child, rather than retaining every pending child.
package struct JSONEvaluationFrame {
    package enum Step {
        case references(Int)
        case composition(JSONSchemaPlan.Keyword, Int, Int)
        case condition
        case properties(Int, Int, Bool)
        case patterns(Int, Int, Bool)
        case additionalProperties(Int)
        case propertyNames(Int)
        case dependentSchemas(Int)
        case prefixItems(Int)
        case items(Int)
        case contains(Int, Int)
        case unevaluatedProperties(Int)
        case unevaluatedItems(Int)
        case finish
    }
    package enum Return {
        case reference
        case composition(JSONSchemaPlan.Keyword)
        case condition
        case property(JSONSchemaPlan.Keyword, JSONKey)
        case propertyName
        case dependency
        case item(JSONSchemaPlan.Keyword, Int)
        case contains(Int)
    }
    package struct Outcome {
        var valid = true
        var evaluated = JSONAnnotationState()
        var issues: [JSONValidationIssue] = []
        var annotations: [JSONEvaluationAnnotation] = []
        var diagnosticsComplete = true
        var ownedIssueBytes: UInt64 = 0
        var ownedAnnotationOutputBytes: UInt64 = 0
        var ownedAnnotationBytes: UInt64 = 0
    }
    package struct ApplicatorAnnotation { let keyword: JSONSchemaPlan.Keyword; var locations = JSONAnnotationState() }
    package var applicatorAnnotations: [ApplicatorAnnotation] = []
    package let node: Int
    package let instance: JSON
    package let path: [JSONLocationComponent]
    package let trace: [JSONKey]
    package let scope: [Int]
    package var steps: [Step] = []
    package var returning: Return?
    package var outcome = Outcome()
    package var branch = Outcome()
    package var staticProperties = JSONAnnotationState()
    package var containsMatches = JSONAnnotationState()
    package var pending: Return?
    package var ownedBytes: UInt64 = 0
}
