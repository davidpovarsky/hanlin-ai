const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
const __UI_USE_XML_PARSER__ = globalThis.__UI_USE_XML_PARSER__ !== undefined ? globalThis.__UI_USE_XML_PARSER__ : true;
import { debug } from '../../utils/debug';
import { isDefined } from '../../utils/types';
import { sanitizeModuleName } from '../../utils/common';
import { setPropertyValue, getComponentModule } from './component-builder';
import { platformNames } from '../../platform/common';
import { resolveModuleName } from '../../module-name-resolver';
import { ScopeError, SourceError, Source } from '../../utils/debug-source';
import * as xml from '../../xml';
import { isString, isObject } from '../../utils/types';
import { Device } from '../../platform/device';
import { profile } from '../../profiling';
// Note: after all circulars are resolve, try importing this from single place or see if globals/index.ts properly handles it
if (typeof global.__metadata === 'undefined') {
    /**
     * TS decorator metadata helper.
     * @param metadataKey   the metadata key (e.g. "design:type")
     * @param metadataValue the metadata value (e.g. the constructor function)
     * @returns a decorator function, or undefined if Reflect.metadata isn’t available
     */
    global.__metadata = (metadataKey, metadataValue) => {
        if (typeof Reflect === 'object' &&
            // @ts-expect-error
            typeof Reflect.metadata === 'function') {
            // Delegate to the reflect-metadata shim
            // @ts-expect-error
            return Reflect.metadata(metadataKey, metadataValue);
        }
        // no-op if no Reflect.metadata
    };
}
export const ios = platformNames.ios.toLowerCase();
export const android = platformNames.android.toLowerCase();
export const visionos = platformNames.visionos.toLowerCase();
export const apple = platformNames.apple.toLowerCase();
export const defaultNameSpaceMatcher = /tns\.xsd$/i;
export class Builder {
    /**
     * Creates view from navigation entry
     * @param entry NavigationEntry
     */
    static createViewFromEntry(entry) {
        if (entry.create) {
            const view = entry.create();
            if (!view) {
                throw new Error('Failed to create View with entry.create() function.');
            }
            return view;
        }
        else if (entry.moduleName) {
            const moduleName = sanitizeModuleName(entry.moduleName);
            const resolvedCodeModuleName = resolveModuleName(moduleName, ''); //`${moduleName}.xml`;
            const moduleExports = resolvedCodeModuleName ? global.loadModule(resolvedCodeModuleName) : null;
            if (moduleExports && moduleExports.createPage) {
                // Exports has a createPage() method
                const view = moduleExports.createPage();
                const resolvedCssModuleName = resolveModuleName(moduleName, 'css'); //entry.moduleName + ".css";
                if (resolvedCssModuleName) {
                    view.addCssFile(resolvedCssModuleName);
                }
                return view;
            }
            else {
                let componentView;
                if (__UI_USE_XML_PARSER__) {
                    const componentModule = loadInternal(moduleName, moduleExports);
                    componentView = componentModule && componentModule.component;
                }
                else {
                    const resolvedXmlModuleName = resolveModuleName(moduleName, 'xml');
                    const componentModule = resolvedXmlModuleName ? global.loadModule(resolvedXmlModuleName) : null;
                    if (componentModule?.default) {
                        componentView = new componentModule.default();
                    }
                    else {
                        throw new Error('Failed to load component from module: ' + moduleName);
                    }
                }
                return componentView;
            }
        }
        throw new Error('Failed to load page XML file for module: ' + entry.moduleName);
    }
    static parse(value, context) {
        if (typeof value === 'function') {
            return value();
        }
        else {
            const exports = context ? getExports(context) : undefined;
            const componentModule = parseInternal(value, exports);
            return componentModule && componentModule.component;
        }
    }
    /**
     * Loads component from module with context
     * @param moduleName the module name
     * @param exports the context of the component to be loaded
     */
    static load(pathOrOptions, context) {
        let componentModule;
        if (typeof pathOrOptions === 'string') {
            const moduleName = sanitizeModuleName(pathOrOptions);
            componentModule = loadInternal(moduleName, context);
        }
        else {
            componentModule = loadCustomComponent(pathOrOptions.path, pathOrOptions.name, pathOrOptions.attributes, pathOrOptions.exports, pathOrOptions.page, true);
        }
        return componentModule && componentModule.component;
    }
    /**
     * Creates an array of KeyedTemplates from string
     * @param value The xml of the template to be parsed
     * @param exports Current context of the template
     */
    static parseMultipleTemplates(value, context) {
        const dummyComponent = `<ListView><ListView.itemTemplates>${value}</ListView.itemTemplates></ListView>`;
        return parseInternal(dummyComponent, context).component['itemTemplates'];
    }
}
/**
 * UI plugin developers can add to these to define their own custom types if needed
 */
Builder.knownTemplates = new Set(['itemTemplate']);
Builder.knownMultiTemplates = new Set(['itemTemplates']);
Builder.knownCollections = new Set(['items', 'spans', 'actionItems']);
/**
 * @deprecated Use Builder.parse() instead.
 */
export function parse(value, context) {
    console.log('parse() is deprecated. Use Builder.parse() instead.');
    return Builder.parse(value, context);
}
/**
 * @deprecated Use Builder.parseMultipleTemplates() instead.
 */
export function parseMultipleTemplates(value, context) {
    console.log('parseMultipleTemplates() is deprecated. Use Builder.parseMultipleTemplates() instead.');
    return Builder.parseMultipleTemplates(value, context);
}
/**
 * @deprecated Use Builder.load() instead.
 */
export async function load(pathOrOptions, context) {
    console.log('load() is deprecated. Use Builder.load() instead.');
    return await Builder.load(pathOrOptions, context);
}
/**
 * @deprecated Use Builder.createViewFromEntry() instead.
 */
export function createViewFromEntry(entry) {
    console.log('createViewFromEntry() is deprecated. Use Builder.createViewFromEntry() instead.');
    return Builder.createViewFromEntry(entry);
}
function loadInternal(moduleName, moduleExports) {
    let componentModule;
    const resolvedXmlModule = resolveModuleName(moduleName, 'xml');
    if (resolvedXmlModule) {
        const text = global.loadModule(resolvedXmlModule);
        componentModule = parseInternal(text, moduleExports, resolvedXmlModule, moduleName);
    }
    const componentView = componentModule && componentModule.component;
    if (componentView) {
        // Save exports to root component (will be used for templates).
        componentView.exports = moduleExports;
        // Save _moduleName - used for livesync
        componentView._moduleName = moduleName;
    }
    if (!componentModule) {
        throw new Error('Failed to load component from module: ' + moduleName);
    }
    return componentModule;
}
export function loadCustomComponent(componentNamespace, componentName, attributes, context, parentPage, isRootComponent = true, moduleNamePath) {
    if (!parentPage && context) {
        // Read the parent page that was passed down below
        // https://github.com/NativeScript/NativeScript/issues/1639
        parentPage = context['_parentPage'];
        delete context['_parentPage'];
    }
    let result;
    componentNamespace = sanitizeModuleName(componentNamespace);
    const moduleName = `${componentNamespace}/${componentName}`;
    const resolvedCodeModuleName = resolveModuleName(moduleName, '');
    const resolvedXmlModuleName = resolveModuleName(moduleName, 'xml');
    let resolvedCssModuleName = resolveModuleName(moduleName, 'css');
    if (resolvedXmlModuleName) {
        // Custom components with XML
        let subExports = context;
        if (resolvedCodeModuleName) {
            // Component has registered code module.
            subExports = global.loadModule(resolvedCodeModuleName);
        }
        // Pass the parent page down the chain in case of custom components nested on many levels. Use the context for piggybacking.
        // https://github.com/NativeScript/NativeScript/issues/1639
        if (!subExports) {
            subExports = {};
        }
        subExports['_parentPage'] = parentPage;
        result = loadInternal(moduleName, subExports);
        // Attributes will be transferred to the custom component
        if (isDefined(result) && isDefined(result.component) && isDefined(attributes)) {
            for (const attr in attributes) {
                setPropertyValue(result.component, subExports, context, attr, attributes[attr]);
            }
        }
    }
    else {
        // Custom components without XML
        result = getComponentModule(componentName, componentNamespace, attributes, context, moduleNamePath, isRootComponent);
        // The namespace is the JS module and the (componentName is the name of the class in the module)
        // So if there is no componentNamespace/componentName.{qualifiers}.css we should also look for
        // componentNamespace.{qualifiers}.css
        if (!resolvedCssModuleName) {
            resolvedCssModuleName = resolveModuleName(componentNamespace, 'css');
        }
    }
    // Add CSS from webpack module if exists.
    if (parentPage && resolvedCssModuleName) {
        parentPage.addCssFile(resolvedCssModuleName);
    }
    return result;
}
export function getExports(instance) {
    const isView = !!instance._domId;
    if (!isView) {
        return instance.exports || instance;
    }
    let exportObject = instance.exports;
    let parent = instance.parent;
    while (exportObject === undefined && parent) {
        exportObject = parent.exports;
        parent = parent.parent;
    }
    return exportObject;
}
function parseInternal(value, context, xmlModule, moduleName) {
    if (__UI_USE_XML_PARSER__) {
        let start;
        let ui;
        const errorFormat = debug && xmlModule ? xml2ui.SourceErrorFormat(xmlModule) : xml2ui.PositionErrorFormat;
        const componentSourceTracker = debug && xmlModule
            ? xml2ui.ComponentSourceTracker(xmlModule)
            : () => {
                // no-op
            };
        (start = new xml2ui.XmlStringParser(errorFormat)).pipe(new xml2ui.PlatformFilter()).pipe(new xml2ui.XmlStateParser((ui = new xml2ui.ComponentParser(context, errorFormat, componentSourceTracker, moduleName))));
        start.parse(value);
        return ui.rootComponentModule;
    }
    else {
        return null;
    }
}
export var xml2ui;
(function (xml2ui) {
    class XmlProducerBase {
        pipe(next) {
            this._next = next;
            return next;
        }
        next(args) {
            this._next.parse(args);
        }
    }
    xml2ui.XmlProducerBase = XmlProducerBase;
    class XmlStringParser extends XmlProducerBase {
        constructor(error) {
            super();
            this.error = error || PositionErrorFormat;
        }
        parse(value) {
            if (__UI_USE_XML_PARSER__) {
                const xmlParser = new xml.XmlParser((args) => {
                    try {
                        this.next(args);
                    }
                    catch (e) {
                        throw this.error(e, args.position);
                    }
                }, (e, p) => {
                    throw this.error(e, p);
                }, true);
                if (isString(value)) {
                    xmlParser.parse(value);
                }
                else if (isObject(value) && isString(value.default)) {
                    xmlParser.parse(value.default);
                }
            }
        }
    }
    xml2ui.XmlStringParser = XmlStringParser;
    function PositionErrorFormat(e, p) {
        return new ScopeError(e, 'Parsing XML at ' + p.line + ':' + p.column);
    }
    xml2ui.PositionErrorFormat = PositionErrorFormat;
    function SourceErrorFormat(uri) {
        return (e, p) => {
            console.error(uri, e?.message ?? e);
            // Stash for dev tooling: callers up the stack frequently swallow this
            // error (e.g. deferred Application.run paths), leaving nothing but the
            // console line above. The NativeScript Vite dev overlay reads this to
            // surface the failure when the app root never commits during boot.
            try {
                globalThis.__NS_LAST_XML_ERROR__ = { uri, message: (e && e.message) || String(e), time: Date.now() };
            }
            catch { }
            const source = p ? new Source(uri, p.line, p.column) : new Source(uri, -1, -1);
            e = new SourceError(e, source, 'Building UI from XML.');
            return e;
        };
    }
    xml2ui.SourceErrorFormat = SourceErrorFormat;
    function ComponentSourceTracker(uri) {
        return (component, p) => {
            if (!Source.get(component)) {
                const source = p ? new Source(uri, p.line, p.column) : new Source(uri, -1, -1);
                Source.set(component, source);
            }
        };
    }
    xml2ui.ComponentSourceTracker = ComponentSourceTracker;
    class PlatformFilter extends XmlProducerBase {
        parse(args) {
            if (args.eventType === xml.ParserEventType.StartElement) {
                if (PlatformFilter.isPlatform(args.elementName)) {
                    if (this.currentPlatformContext) {
                        throw new Error("Already in '" + this.currentPlatformContext + "' platform context and cannot switch to '" + args.elementName + "' platform! Platform tags cannot be nested.");
                    }
                    this.currentPlatformContext = args.elementName;
                    return;
                }
            }
            if (args.eventType === xml.ParserEventType.EndElement) {
                if (PlatformFilter.isPlatform(args.elementName)) {
                    this.currentPlatformContext = undefined;
                    return;
                }
            }
            if (this.currentPlatformContext && !PlatformFilter.isCurentPlatform(this.currentPlatformContext)) {
                return;
            }
            this.next(args);
        }
        static isPlatform(value) {
            if (value) {
                const toLower = value.toLowerCase();
                return toLower === android || toLower === ios || toLower === visionos || toLower === apple;
            }
            return false;
        }
        static isCurentPlatform(value) {
            value = value && value.toLowerCase();
            return value === apple ? __APPLE__ : value === Device.os.toLowerCase();
        }
    }
    xml2ui.PlatformFilter = PlatformFilter;
    class XmlArgsReplay extends XmlProducerBase {
        constructor(args, errorFormat) {
            super();
            this.args = args;
            this.error = errorFormat;
        }
        replay() {
            this.args.forEach((args) => {
                try {
                    this.next(args);
                }
                catch (e) {
                    throw this.error(e, args.position);
                }
            });
        }
    }
    xml2ui.XmlArgsReplay = XmlArgsReplay;
    /**
     * It is a state pattern
     * https://en.wikipedia.org/wiki/State_pattern
     */
    class XmlStateParser {
        constructor(state) {
            this.state = state;
        }
        parse(args) {
            this.state = this.state.parse(args);
        }
    }
    xml2ui.XmlStateParser = XmlStateParser;
    class TemplateParser {
        constructor(parent, templateProperty, setTemplateProperty = true) {
            this.parent = parent;
            this._context = templateProperty.context;
            this._recordedXmlStream = new Array();
            this._templateProperty = templateProperty;
            this._nestingLevel = 0;
            this._state = 0 /* TemplateParser.State.EXPECTING_START */;
            this._setTemplateProperty = setTemplateProperty;
        }
        parse(args) {
            if (args.eventType === xml.ParserEventType.StartElement) {
                this.parseStartElement(args.prefix, args.namespace, args.elementName, args.attributes);
            }
            else if (args.eventType === xml.ParserEventType.EndElement) {
                this.parseEndElement(args.prefix, args.elementName);
            }
            this._recordedXmlStream.push(args);
            return this._state === 2 /* TemplateParser.State.FINISHED */ ? this.parent : this;
        }
        get elementName() {
            return this._templateProperty.elementName;
        }
        parseStartElement(prefix, namespace, elementName, attributes) {
            if (this._state === 0 /* TemplateParser.State.EXPECTING_START */) {
                this._state = 1 /* TemplateParser.State.PARSING */;
            }
            else if (this._state === 2 /* TemplateParser.State.FINISHED */) {
                throw new Error('Template must have exactly one root element but multiple elements were found.');
            }
            this._nestingLevel++;
        }
        parseEndElement(prefix, elementName) {
            if (this._state === 0 /* TemplateParser.State.EXPECTING_START */) {
                throw new Error('Template must have exactly one root element but none was found.');
            }
            else if (this._state === 2 /* TemplateParser.State.FINISHED */) {
                throw new Error('No more closing elements expected for this template.');
            }
            this._nestingLevel--;
            if (this._nestingLevel === 0) {
                this._state = 2 /* TemplateParser.State.FINISHED */;
                if (this._setTemplateProperty && this._templateProperty.name in this._templateProperty.parent.component) {
                    const template = this.buildTemplate();
                    this._templateProperty.parent.component[this._templateProperty.name] = template;
                }
            }
        }
        buildTemplate() {
            if (__UI_USE_XML_PARSER__) {
                const context = this._context;
                const errorFormat = this._templateProperty.errorFormat;
                const sourceTracker = this._templateProperty.sourceTracker;
                const template = profile('Template()', () => {
                    let start;
                    let ui;
                    (start = new xml2ui.XmlArgsReplay(this._recordedXmlStream, errorFormat))
                        // No platform filter, it has been filtered already
                        .pipe(new XmlStateParser((ui = new ComponentParser(context, errorFormat, sourceTracker))));
                    start.replay();
                    return ui.rootComponentModule.component;
                });
                return template;
            }
            else {
                return null;
            }
        }
    }
    xml2ui.TemplateParser = TemplateParser;
    class MultiTemplateParser {
        get value() {
            return this._value;
        }
        constructor(parent, templateProperty) {
            this.parent = parent;
            this.templateProperty = templateProperty;
            this._childParsers = new Array();
        }
        parse(args) {
            if (args.eventType === xml.ParserEventType.StartElement && args.elementName === 'template') {
                const childParser = new TemplateParser(this, this.templateProperty, false);
                childParser['key'] = args.attributes['key'];
                this._childParsers.push(childParser);
                return childParser;
            }
            if (args.eventType === xml.ParserEventType.EndElement) {
                const name = ComponentParser.getComplexPropertyName(args.elementName);
                if (name === this.templateProperty.name) {
                    const templates = new Array();
                    for (let i = 0; i < this._childParsers.length; i++) {
                        templates.push({
                            key: this._childParsers[i]['key'],
                            createView: this._childParsers[i].buildTemplate(),
                        });
                    }
                    this._value = templates;
                    return this.parent.parse(args);
                }
            }
            return this;
        }
    }
    xml2ui.MultiTemplateParser = MultiTemplateParser;
    class ComponentParser {
        constructor(context, errorFormat, sourceTracker, moduleName) {
            this.moduleName = moduleName;
            this.parents = new Array();
            this.complexProperties = new Array();
            this.context = context;
            this.error = errorFormat;
            this.sourceTracker = sourceTracker;
        }
        buildComponent(args) {
            if (args.prefix && args.namespace) {
                // Custom components
                return loadCustomComponent(args.namespace, args.elementName, args.attributes, this.context, this.currentRootView, !this.currentRootView, this.moduleName);
            }
            else {
                // Default components
                let namespace = args.namespace;
                if (defaultNameSpaceMatcher.test(namespace || '')) {
                    //Ignore the default ...tns.xsd namespace URL
                    namespace = undefined;
                }
                return getComponentModule(args.elementName, namespace, args.attributes, this.context, this.moduleName, !this.currentRootView);
            }
        }
        parse(args) {
            // Get the current parent.
            const parent = this.parents[this.parents.length - 1];
            const complexProperty = this.complexProperties[this.complexProperties.length - 1];
            // Create component instance from every element declaration.
            if (args.eventType === xml.ParserEventType.StartElement) {
                if (ComponentParser.isComplexProperty(args.elementName)) {
                    const name = ComponentParser.getComplexPropertyName(args.elementName);
                    const complexProperty = {
                        parent: parent,
                        name: name,
                        items: [],
                    };
                    this.complexProperties.push(complexProperty);
                    if (ComponentParser.isKnownTemplate(name, parent.exports)) {
                        return new TemplateParser(this, {
                            context: (parent ? getExports(parent.component) : null) || this.context,
                            parent: parent,
                            name: name,
                            elementName: args.elementName,
                            templateItems: [],
                            errorFormat: this.error,
                            sourceTracker: this.sourceTracker,
                        });
                    }
                    if (ComponentParser.isKnownMultiTemplate(name, parent.exports)) {
                        const parser = new MultiTemplateParser(this, {
                            context: (parent ? getExports(parent.component) : null) || this.context,
                            parent: parent,
                            name: name,
                            elementName: args.elementName,
                            templateItems: [],
                            errorFormat: this.error,
                            sourceTracker: this.sourceTracker,
                        });
                        complexProperty.parser = parser;
                        return parser;
                    }
                }
                else {
                    const componentModule = this.buildComponent(args);
                    if (componentModule) {
                        this.sourceTracker(componentModule.component, args.position);
                        if (parent) {
                            if (complexProperty && complexProperty.parent == parent) {
                                // Add component to complex property of parent component.
                                ComponentParser.addToComplexProperty(parent, complexProperty, componentModule);
                            }
                            else if (parent.component._addChildFromBuilder) {
                                parent.component._addChildFromBuilder(args.elementName, componentModule.component);
                            }
                        }
                        else if (this.parents.length === 0) {
                            // Set root component.
                            this.rootComponentModule = componentModule;
                            if (this.rootComponentModule) {
                                this.currentRootView = this.rootComponentModule.component;
                                if (this.currentRootView.exports) {
                                    this.context = this.currentRootView.exports;
                                }
                            }
                        }
                        // Add the component instance to the parents scope collection.
                        this.parents.push(componentModule);
                    }
                }
            }
            else if (args.eventType === xml.ParserEventType.EndElement) {
                if (ComponentParser.isComplexProperty(args.elementName)) {
                    if (complexProperty) {
                        if (complexProperty.parser) {
                            parent.component[complexProperty.name] = complexProperty.parser.value;
                        }
                        else if (parent && parent.component._addArrayFromBuilder) {
                            // If parent is AddArrayFromBuilder call the interface method to populate the array property.
                            parent.component._addArrayFromBuilder(complexProperty.name, complexProperty.items);
                            complexProperty.items = [];
                        }
                    }
                    // Remove the last complexProperty from the complexProperties collection (move to the previous complexProperty scope).
                    this.complexProperties.pop();
                }
                else {
                    // Remove the last parent from the parents collection (move to the previous parent scope).
                    this.parents.pop();
                }
            }
            return this;
        }
        static isComplexProperty(name) {
            return isString(name) && name.indexOf('.') !== -1;
        }
        static getComplexPropertyName(fullName) {
            let name;
            if (isString(fullName)) {
                const names = fullName.split('.');
                name = names[names.length - 1];
            }
            return name;
        }
        static isKnownTemplate(name, exports) {
            return Builder.knownTemplates.has(name);
        }
        static isKnownMultiTemplate(name, exports) {
            return Builder.knownMultiTemplates.has(name);
        }
        static addToComplexProperty(parent, complexProperty, elementModule) {
            // If property name is known collection we populate array with elements.
            const parentComponent = parent.component;
            if (ComponentParser.isKnownCollection(complexProperty.name, parent.exports)) {
                complexProperty.items.push(elementModule.component);
            }
            else if (parentComponent._addChildFromBuilder) {
                parentComponent._addChildFromBuilder(complexProperty.name, elementModule.component);
            }
            else {
                // Or simply assign the value;
                parentComponent[complexProperty.name] = elementModule.component;
            }
        }
        static isKnownCollection(name, context) {
            return Builder.knownCollections.has(name);
        }
    }
    ComponentParser.KNOWNCOLLECTIONS = 'knownCollections';
    ComponentParser.KNOWNTEMPLATES = 'knownTemplates';
    ComponentParser.KNOWNMULTITEMPLATES = 'knownMultiTemplates';
    __decorate([
        profile,
        __metadata("design:type", Function),
        __metadata("design:paramtypes", [xml.ParserEvent]),
        __metadata("design:returntype", Object)
    ], ComponentParser.prototype, "buildComponent", null);
    xml2ui.ComponentParser = ComponentParser;
})(xml2ui || (xml2ui = {}));
//# sourceMappingURL=index.js.map