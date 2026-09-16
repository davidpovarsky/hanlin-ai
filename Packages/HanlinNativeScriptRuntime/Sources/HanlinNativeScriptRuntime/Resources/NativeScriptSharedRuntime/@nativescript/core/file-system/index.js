const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
import { FileSystemAccess, FileSystemAccess29 } from './file-system-access';
import { SDK_VERSION } from '../utils/constants';
import { getNativeApp } from '../application/helpers-common';
// The FileSystemAccess implementation, used through all the APIs.
let fileAccess;
/**
 * Returns FileSystemAccess, a shared singleton utility class to provide methods to access and work with the file system. This is used under the hood of all the file system apis in @nativescript/core and provided as a lower level convenience if needed.
 * @returns FileSystemAccess
 */
export function getFileAccess() {
    if (!fileAccess) {
        if (__ANDROID__ && SDK_VERSION >= 29) {
            fileAccess = new FileSystemAccess29();
        }
        else {
            fileAccess = new FileSystemAccess();
        }
    }
    return fileAccess;
}
function createFile(info) {
    const file = new File();
    file._path = info.path;
    file._name = info.name;
    file._extension = info.extension;
    return file;
}
function createFolder(info) {
    const documents = knownFolders.documents();
    if (info.path === documents.path) {
        return documents;
    }
    const temp = knownFolders.temp();
    if (info.path === temp.path) {
        return temp;
    }
    const folder = new Folder();
    folder._path = info.path;
    folder._name = info.name;
    return folder;
}
export class FileSystemEntity {
    get parent() {
        const onError = function (error) {
            throw error;
        };
        const folderInfo = getFileAccess().getParent(this.path, onError);
        if (!folderInfo) {
            return undefined;
        }
        return createFolder(folderInfo);
    }
    remove() {
        return new Promise((resolve, reject) => {
            let hasError = false;
            const localError = function (error) {
                hasError = true;
                reject(error);
            };
            this.removeSync(localError);
            if (!hasError) {
                resolve(true);
            }
        });
    }
    removeSync(onError) {
        if (this._isKnown) {
            if (onError) {
                onError({ message: 'Cannot delete known folder.' });
            }
            return;
        }
        const fileAccess = getFileAccess();
        if (this instanceof File) {
            fileAccess.deleteFile(this.path, onError);
        }
        else if (this instanceof Folder) {
            fileAccess.deleteFolder(this.path, onError);
        }
    }
    rename(newName) {
        return new Promise((resolve, reject) => {
            let hasError = false;
            const localError = function (error) {
                hasError = true;
                reject(error);
            };
            this.renameSync(newName, localError);
            if (!hasError) {
                resolve(true);
            }
        });
    }
    renameSync(newName, onError) {
        if (this._isKnown) {
            if (onError) {
                onError(new Error('Cannot rename known folder.'));
            }
            return;
        }
        const localError = function (error) {
            if (onError) {
                onError(error);
            }
            return null;
        };
        const fileAccess = getFileAccess();
        // call rename for FileSystemAccess29
        if (fileAccess.__skip) {
            fileAccess.rename(this.path, newName, localError);
            const fileInfo = getFileAccess().getFile(this.path, null);
            if (fileInfo) {
                this._name = fileInfo.name;
                this._extension = fileInfo.extension;
            }
            return;
        }
        const parentFolder = this.parent;
        if (!parentFolder) {
            if (onError) {
                onError(new Error('No parent folder.'));
            }
            return;
        }
        const path = parentFolder.path;
        const newPath = fileAccess.joinPath(path, newName);
        fileAccess.rename(this.path, newPath, localError);
        this._path = newPath;
        this._name = newName;
        if (this instanceof File) {
            this._extension = fileAccess.getFileExtension(newPath);
        }
    }
    get name() {
        return this._name;
    }
    get path() {
        return this._path;
    }
    get lastModified() {
        return getFileAccess().getLastModified(this.path);
    }
}
export var AndroidDirectory;
(function (AndroidDirectory) {
    AndroidDirectory["ALARMS"] = "alarms";
    AndroidDirectory["AUDIOBOOKS"] = "audiobooks";
    AndroidDirectory["DCIM"] = "dcim";
    AndroidDirectory["DOCUMENTS"] = "documents";
    AndroidDirectory["DOWNLOADS"] = "downloads";
    AndroidDirectory["MOVIES"] = "movies";
    AndroidDirectory["MUSIC"] = "music";
    AndroidDirectory["NOTIFICATIONS"] = "notifications";
    AndroidDirectory["PICTURES"] = "pictures";
    AndroidDirectory["PODCASTS"] = "podcasts";
    AndroidDirectory["RINGTONES"] = "ringtones";
    AndroidDirectory["SCREENSHOTS"] = "screenshots";
})(AndroidDirectory || (AndroidDirectory = {}));
function getAndroidDirectory(value) {
    switch (value) {
        case AndroidDirectory.ALARMS:
            return {
                path: android.os.Environment.DIRECTORY_ALARMS,
                column: android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.AUDIOBOOKS:
            return {
                path: android.os.Environment.DIRECTORY_AUDIOBOOKS,
                column: android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.DCIM:
            return {
                path: android.os.Environment.DIRECTORY_DCIM,
                column: android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.DOCUMENTS:
            return {
                path: android.os.Environment.DIRECTORY_DOCUMENTS,
                column: android.provider.MediaStore.Files.getContentUri('external'),
            };
        case AndroidDirectory.DOWNLOADS:
            return {
                path: android.os.Environment.DIRECTORY_DOWNLOADS,
                column: android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.MOVIES:
            return {
                path: android.os.Environment.DIRECTORY_MOVIES,
                column: android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.MUSIC:
            return {
                path: android.os.Environment.DIRECTORY_MUSIC,
                column: android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.NOTIFICATIONS:
            return {
                path: android.os.Environment.DIRECTORY_NOTIFICATIONS,
                column: android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.PICTURES:
            return {
                path: android.os.Environment.DIRECTORY_PICTURES,
                column: android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.PODCASTS:
            return {
                path: android.os.Environment.DIRECTORY_PODCASTS,
                column: android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.RINGTONES:
            return {
                path: android.os.Environment.DIRECTORY_RINGTONES,
                column: android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            };
        case AndroidDirectory.SCREENSHOTS:
            return {
                path: android.os.Environment.DIRECTORY_SCREENSHOTS,
                column: android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            };
        default:
            return null;
    }
}
class Android {
    createFile(options) {
        if (!__ANDROID__) {
            throw new Error(`createFile is available on Android only!`);
        }
        const context = getNativeApp().getApplicationContext();
        const meta = new android.content.ContentValues();
        meta.put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, options.name);
        meta.put(android.provider.MediaStore.MediaColumns.MIME_TYPE, options.mime);
        //meta.put(android.provider.MediaStore.MediaColumns.DATE_ADDED, java.lang.System.currentTimeMillis() as any);
        const externalDirectory = getAndroidDirectory(options.directory);
        if (SDK_VERSION >= 29) {
            const relativePath = options?.relativePath ? `/${options.relativePath}` : '';
            meta.put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, `${externalDirectory.path}${relativePath}`);
            // todo
            //	meta.put(android.provider.MediaStore.MediaColumns.IS_PENDING, java.lang.Integer.valueOf(1));
        }
        else {
            const relativePath = options?.relativePath ? `${options.relativePath}/` : '';
            const directory = android.os.Environment.getExternalStoragePublicDirectory(externalDirectory.path);
            const file = new java.io.File(directory, `${relativePath}${options.name}`);
            meta.put(android.provider.MediaStore.MediaColumns.DATA, file.getAbsolutePath());
        }
        const uri = context.getContentResolver().insert(externalDirectory.column, meta);
        return File.fromPath(uri.toString());
    }
}
const ad = new Android();
class iOS {
}
const ios = new iOS();
export class File extends FileSystemEntity {
    static get ios() {
        return ios;
    }
    static get android() {
        return ad;
    }
    static fromPath(path, copy = false) {
        const onError = function (error) {
            throw error;
        };
        if (__ANDROID__ && copy) {
            if (path.startsWith('content:')) {
                const fileInfo = getFileAccess().getFile(path, onError);
                // falls back to creating a temp file without a known extension.
                if (!fileInfo) {
                    const tempFile = `${knownFolders.temp().path}/${java.util.UUID.randomUUID().toString()}`;
                    org.nativescript.widgets.Async.File.copySync(path, tempFile, getNativeApp().getApplicationContext());
                    path = tempFile;
                }
                else {
                    const ext = fileInfo.extension;
                    const name = `${fileInfo.name.replace(`.${ext}`, '')}.${ext}`;
                    const tempFile = `${knownFolders.temp().path}/${name}`;
                    getFileAccess().copySync(path, tempFile);
                    path = tempFile;
                }
            }
        }
        const fileInfo = getFileAccess().getFile(path, onError);
        if (!fileInfo) {
            return undefined;
        }
        return createFile(fileInfo);
    }
    static exists(path) {
        return getFileAccess().fileExists(path);
    }
    get extension() {
        return this._extension;
    }
    get isLocked() {
        // !! is a boolean conversion/cast, handling undefined as well
        return !!this._locked;
    }
    get size() {
        return getFileAccess().getFileSize(this.path);
    }
    append(content) {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .appendAsync(this.path, content)
                .then(() => {
                resolve();
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    appendSync(content, onError) {
        this._checkAccess();
        try {
            this._locked = true;
            const that = this;
            const localError = function (error) {
                that._locked = false;
                if (onError) {
                    onError(error);
                }
            };
            getFileAccess().appendSync(this.path, content, localError);
        }
        finally {
            this._locked = false;
        }
    }
    appendText(content, encoding) {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .appendTextAsync(this.path, content, encoding)
                .then(() => {
                resolve(true);
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    appendTextSync(content, onError, encoding) {
        this._checkAccess();
        try {
            this._locked = true;
            const that = this;
            const localError = function (error) {
                that._locked = false;
                if (onError) {
                    onError(error);
                }
            };
            getFileAccess().appendTextSync(this.path, content, localError, encoding);
        }
        finally {
            this._locked = false;
        }
    }
    copy(dest) {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .copyAsync(this.path, dest)
                .then((result) => {
                resolve(result);
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    copySync(dest, onError) {
        this._checkAccess();
        this._locked = true;
        const that = this;
        const localError = (error) => {
            that._locked = false;
            if (onError) {
                onError(error);
            }
        };
        const content = getFileAccess().copySync(this.path, dest, localError);
        this._locked = false;
        return content;
    }
    read() {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .readAsync(this.path)
                .then((result) => {
                resolve(result);
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    readSync(onError) {
        this._checkAccess();
        this._locked = true;
        const that = this;
        const localError = (error) => {
            that._locked = false;
            if (onError) {
                onError(error);
            }
        };
        const content = getFileAccess().readSync(this.path, localError);
        this._locked = false;
        return content;
    }
    write(content) {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .writeAsync(this.path, content)
                .then(() => {
                resolve();
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    writeSync(content, onError) {
        this._checkAccess();
        try {
            this._locked = true;
            const that = this;
            const localError = function (error) {
                that._locked = false;
                if (onError) {
                    onError(error);
                }
            };
            getFileAccess().writeSync(this.path, content, localError);
        }
        finally {
            this._locked = false;
        }
    }
    readText(encoding) {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .readTextAsync(this.path, encoding)
                .then((result) => {
                resolve(result);
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    readTextSync(onError, encoding) {
        this._checkAccess();
        this._locked = true;
        const that = this;
        const localError = (error) => {
            that._locked = false;
            if (onError) {
                onError(error);
            }
        };
        const content = getFileAccess().readTextSync(this.path, localError, encoding);
        this._locked = false;
        return content;
    }
    writeText(content, encoding) {
        return new Promise((resolve, reject) => {
            try {
                this._checkAccess();
            }
            catch (ex) {
                reject(ex);
                return;
            }
            this._locked = true;
            getFileAccess()
                .writeTextAsync(this.path, content, encoding)
                .then(() => {
                resolve(true);
                this._locked = false;
            }, (error) => {
                reject(error);
                this._locked = false;
            });
        });
    }
    writeTextSync(content, onError, encoding) {
        this._checkAccess();
        try {
            this._locked = true;
            const that = this;
            const localError = function (error) {
                that._locked = false;
                if (onError) {
                    onError(error);
                }
            };
            getFileAccess().writeTextSync(this.path, content, localError, encoding);
        }
        finally {
            this._locked = false;
        }
    }
    _checkAccess() {
        if (this.isLocked) {
            throw new Error('Cannot access a locked file.');
        }
    }
}
export class Folder extends FileSystemEntity {
    static fromPath(path) {
        const onError = function (error) {
            throw error;
        };
        const folderInfo = getFileAccess().getFolder(path, onError);
        if (!folderInfo) {
            return undefined;
        }
        return createFolder(folderInfo);
    }
    static exists(path) {
        return getFileAccess().folderExists(path);
    }
    contains(name) {
        const fileAccess = getFileAccess();
        const path = fileAccess.joinPath(this.path, name);
        if (fileAccess.fileExists(path)) {
            return true;
        }
        return fileAccess.folderExists(path);
    }
    clear() {
        return new Promise((resolve, reject) => {
            let hasError = false;
            const onError = function (error) {
                hasError = true;
                reject(error);
            };
            this.clearSync(onError);
            if (!hasError) {
                resolve(true);
            }
        });
    }
    clearSync(onError) {
        getFileAccess().emptyFolder(this.path, onError);
    }
    get isKnown() {
        return this._isKnown;
    }
    getFile(name) {
        const fileAccess = getFileAccess();
        const path = fileAccess.joinPath(this.path, name);
        const onError = function (error) {
            throw error;
        };
        const fileInfo = fileAccess.getFile(path, onError);
        if (!fileInfo) {
            return undefined;
        }
        return createFile(fileInfo);
    }
    getFolder(name) {
        const fileAccess = getFileAccess();
        const path = fileAccess.joinPath(this.path, name);
        const onError = function (error) {
            throw error;
        };
        const folderInfo = fileAccess.getFolder(path, onError);
        if (!folderInfo) {
            return undefined;
        }
        return createFolder(folderInfo);
    }
    getEntities() {
        return new Promise((resolve, reject) => {
            let hasError = false;
            const localError = function (error) {
                hasError = true;
                reject(error);
            };
            const entities = this.getEntitiesSync(localError);
            if (!hasError) {
                resolve(entities);
            }
        });
    }
    getEntitiesSync(onError) {
        const fileInfos = getFileAccess().getEntities(this.path, onError);
        if (!fileInfos) {
            return null;
        }
        const entities = new Array();
        for (let i = 0; i < fileInfos.length; i++) {
            if (fileInfos[i].extension) {
                entities.push(createFile(fileInfos[i]));
            }
            else {
                entities.push(createFolder(fileInfos[i]));
            }
        }
        return entities;
    }
    eachEntity(onEntity) {
        if (!onEntity) {
            return;
        }
        const onSuccess = function (fileInfo) {
            let entity;
            if (fileInfo.extension) {
                entity = createFile(fileInfo);
            }
            else {
                entity = createFolder(fileInfo);
            }
            return onEntity(entity);
        };
        const onError = function (error) {
            throw error;
        };
        getFileAccess().eachEntity(this.path, onSuccess, onError);
    }
}
export var knownFolders;
(function (knownFolders) {
    let _documents;
    let _externalDocuments;
    let _temp;
    let _app;
    function documents() {
        if (!_documents) {
            const path = getFileAccess().getDocumentsFolderPath();
            _documents = new Folder();
            _documents._path = path;
            _documents._isKnown = true;
        }
        return _documents;
    }
    knownFolders.documents = documents;
    function externalDocuments() {
        if (!_externalDocuments) {
            const path = getFileAccess().getExternalDocumentsFolderPath();
            _externalDocuments = new Folder();
            _externalDocuments._path = path;
            _externalDocuments._isKnown = true;
        }
        return _externalDocuments;
    }
    knownFolders.externalDocuments = externalDocuments;
    function temp() {
        if (!_temp) {
            const path = getFileAccess().getTempFolderPath();
            _temp = new Folder();
            _temp._path = path;
            _temp._isKnown = true;
        }
        return _temp;
    }
    knownFolders.temp = temp;
    function currentApp() {
        if (!_app) {
            const path = getFileAccess().getCurrentAppPath();
            _app = new Folder();
            _app._path = path;
            _app._isKnown = true;
        }
        return _app;
    }
    knownFolders.currentApp = currentApp;
    let ios;
    (function (ios) {
        function _checkPlatform(knownFolderName) {
            if (!__APPLE__) {
                throw new Error(`The "${knownFolderName}" known folder is available on iOS only!`);
            }
        }
        let _library;
        function library() {
            _checkPlatform('library');
            if (!_library) {
                const existingFolderInfo = getExistingFolderInfo(5 /* NSSearchPathDirectory.LibraryDirectory */);
                if (existingFolderInfo) {
                    _library = existingFolderInfo.folder;
                    _library._path = existingFolderInfo.path;
                    _library._isKnown = true;
                }
            }
            return _library;
        }
        ios.library = library;
        let _developer;
        function developer() {
            _checkPlatform('developer');
            if (!_developer) {
                const existingFolderInfo = getExistingFolderInfo(6 /* NSSearchPathDirectory.DeveloperDirectory */);
                if (existingFolderInfo) {
                    _developer = existingFolderInfo.folder;
                    _developer._path = existingFolderInfo.path;
                    _developer._isKnown = true;
                }
            }
            return _developer;
        }
        ios.developer = developer;
        let _desktop;
        function desktop() {
            _checkPlatform('desktop');
            if (!_desktop) {
                const existingFolderInfo = getExistingFolderInfo(12 /* NSSearchPathDirectory.DesktopDirectory */);
                if (existingFolderInfo) {
                    _desktop = existingFolderInfo.folder;
                    _desktop._path = existingFolderInfo.path;
                    _desktop._isKnown = true;
                }
            }
            return _desktop;
        }
        ios.desktop = desktop;
        let _downloads;
        function downloads() {
            _checkPlatform('downloads');
            if (!_downloads) {
                const existingFolderInfo = getExistingFolderInfo(15 /* NSSearchPathDirectory.DownloadsDirectory */);
                if (existingFolderInfo) {
                    _downloads = existingFolderInfo.folder;
                    _downloads._path = existingFolderInfo.path;
                    _downloads._isKnown = true;
                }
            }
            return _downloads;
        }
        ios.downloads = downloads;
        let _movies;
        function movies() {
            _checkPlatform('movies');
            if (!_movies) {
                const existingFolderInfo = getExistingFolderInfo(17 /* NSSearchPathDirectory.MoviesDirectory */);
                if (existingFolderInfo) {
                    _movies = existingFolderInfo.folder;
                    _movies._path = existingFolderInfo.path;
                    _movies._isKnown = true;
                }
            }
            return _movies;
        }
        ios.movies = movies;
        let _music;
        function music() {
            _checkPlatform('music');
            if (!_music) {
                const existingFolderInfo = getExistingFolderInfo(18 /* NSSearchPathDirectory.MusicDirectory */);
                if (existingFolderInfo) {
                    _music = existingFolderInfo.folder;
                    _music._path = existingFolderInfo.path;
                    _music._isKnown = true;
                }
            }
            return _music;
        }
        ios.music = music;
        let _pictures;
        function pictures() {
            _checkPlatform('pictures');
            if (!_pictures) {
                const existingFolderInfo = getExistingFolderInfo(19 /* NSSearchPathDirectory.PicturesDirectory */);
                if (existingFolderInfo) {
                    _pictures = existingFolderInfo.folder;
                    _pictures._path = existingFolderInfo.path;
                    _pictures._isKnown = true;
                }
            }
            return _pictures;
        }
        ios.pictures = pictures;
        let _sharedPublic;
        function sharedPublic() {
            _checkPlatform('sharedPublic');
            if (!_sharedPublic) {
                const existingFolderInfo = getExistingFolderInfo(21 /* NSSearchPathDirectory.SharedPublicDirectory */);
                if (existingFolderInfo) {
                    _sharedPublic = existingFolderInfo.folder;
                    _sharedPublic._path = existingFolderInfo.path;
                    _sharedPublic._isKnown = true;
                }
            }
            return _sharedPublic;
        }
        ios.sharedPublic = sharedPublic;
        function getExistingFolderInfo(pathDirectory /* NSSearchPathDirectory */) {
            const fileAccess = getFileAccess();
            const folderPath = fileAccess.getKnownPath(pathDirectory);
            const folderInfo = fileAccess.getExistingFolder(folderPath);
            if (folderInfo) {
                return {
                    folder: createFolder(folderInfo),
                    path: folderPath,
                };
            }
            return undefined;
        }
    })(ios = knownFolders.ios || (knownFolders.ios = {}));
})(knownFolders || (knownFolders = {}));
export var path;
(function (path_1) {
    function normalize(path) {
        return getFileAccess().normalizePath(path);
    }
    path_1.normalize = normalize;
    function join(...paths) {
        const fileAccess = getFileAccess();
        return fileAccess.joinPaths(paths);
    }
    path_1.join = join;
    path_1.separator = getFileAccess().getPathSeparator();
})(path || (path = {}));
//# sourceMappingURL=index.js.map