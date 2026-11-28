// Requires
import { getDocument, getComputedStylesForNode, removeNode, setAttributeAsText } from './devtools-elements.common';
import { registerInspectorEvents } from './dom-types';
export * from './devtools-elements-interfaces';
export function attachDOMInspectorEventCallbacks(DOMDomainFrontend) {
    registerInspectorEvents(DOMDomainFrontend);
    const originalChildNodeInserted = DOMDomainFrontend.childNodeInserted;
    DOMDomainFrontend.childNodeInserted = (parentId, lastId, node) => {
        originalChildNodeInserted(parentId, lastId, node.toObject());
    };
}
export function attachDOMInspectorCommandCallbacks(DOMDomainBackend) {
    DOMDomainBackend.getDocument = getDocument;
    DOMDomainBackend.removeNode = removeNode;
    DOMDomainBackend.setAttributeAsText = setAttributeAsText;
}
export function attachCSSInspectorCommandCallbacks(CSSDomainBackend) {
    CSSDomainBackend.getComputedStylesForNode = getComputedStylesForNode;
}
//# sourceMappingURL=devtools-elements.js.map