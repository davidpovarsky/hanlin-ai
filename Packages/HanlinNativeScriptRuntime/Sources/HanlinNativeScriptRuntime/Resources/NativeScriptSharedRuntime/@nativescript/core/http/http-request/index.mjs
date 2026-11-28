import { ImageSource } from '../../image-source';
import { File } from '../../file-system';
import { requestInternal } from '../http-request-internal';
import { getFilenameFromUrl, parseJSON } from './http-request-common';
const contentHandler = {
    toArrayBuffer() {
        return interop.bufferFromData(this.raw);
    },
    toString(encoding) {
        const str = this.toNativeString(encoding);
        if (typeof str === 'string') {
            return str;
        }
        else {
            throw new Error('Response content may not be converted to string');
        }
    },
    toJSON(encoding) {
        return parseJSON(this.toNativeString(encoding));
    },
    toImage() {
        return this.toNativeImage().then((value) => new ImageSource(value));
    },
    toFile(destinationFilePath) {
        if (!destinationFilePath) {
            destinationFilePath = getFilenameFromUrl(this.requestURL);
        }
        if (this.raw instanceof NSData) {
            // ensure destination path exists by creating any missing parent directories
            const file = File.fromPath(destinationFilePath);
            this.raw.writeToFileAtomically(destinationFilePath, true);
            return file;
        }
        else {
            throw new Error(`Cannot save file with path: ${destinationFilePath}.`);
        }
    },
};
export function request(options) {
    return requestInternal(options, contentHandler);
}
//# sourceMappingURL=index.ios.js.map