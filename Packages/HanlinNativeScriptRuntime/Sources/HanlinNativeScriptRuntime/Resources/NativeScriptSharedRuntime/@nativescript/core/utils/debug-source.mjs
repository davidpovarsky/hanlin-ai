import { getNativeApp } from '../application/helpers-common';
// console.log('__dirname:', global.__dirname);
function getCurrentAppPath() {
    if (__APPLE__) {
        const currentDir = global.__dirname;
        const tnsModulesIndex = currentDir.indexOf('/tns_modules');
        // Module not hosted in ~/tns_modules when bundled. Use current dir.
        let appPath = currentDir;
        if (tnsModulesIndex !== -1) {
            // Strip part after tns_modules to obtain app root
            appPath = currentDir.substring(0, tnsModulesIndex);
        }
        return appPath;
    }
    else {
        const dir = getNativeApp().getApplicationContext().getFilesDir();
        return `${dir.getCanonicalPath()}/app`;
    }
}
let applicationRootPath;
function ensureAppRootPath() {
    if (!applicationRootPath) {
        applicationRootPath = getCurrentAppPath();
        applicationRootPath = applicationRootPath.substring(0, applicationRootPath.length - 'app/'.length);
    }
}
export class Source {
    constructor(uri, line, column) {
        ensureAppRootPath();
        if (uri.length > applicationRootPath.length && uri.substring(0, applicationRootPath.length) === applicationRootPath) {
            this._uri = 'file://' + uri.substring(applicationRootPath.length);
        }
        else {
            this._uri = uri;
        }
        this._line = line;
        this._column = column;
    }
    get uri() {
        return this._uri;
    }
    get line() {
        return this._line;
    }
    get column() {
        return this._column;
    }
    toString() {
        return this._uri + ':' + this._line + ':' + this._column;
    }
    static get(object) {
        return object[Source._source];
    }
    static set(object, src) {
        object[Source._source] = src;
    }
}
Source._source = Symbol('source');
export class ScopeError extends Error {
    constructor(inner, message) {
        let formattedMessage;
        if (message && inner.message) {
            formattedMessage = message + '\n > ' + inner.message.replace('\n', '\n  ');
        }
        else {
            formattedMessage = message || inner.message || undefined;
        }
        super(formattedMessage);
        this.stack = __ANDROID__ ? 'Error: ' + this.message + '\n' + inner.stack.substr(inner.stack.indexOf('\n') + 1) : inner.stack;
        this.message = formattedMessage;
    }
}
export class SourceError extends ScopeError {
    constructor(child, source, message) {
        super(child, message ? message + ' @' + source + '' : source + '');
    }
}
//# sourceMappingURL=debug-source.js.map