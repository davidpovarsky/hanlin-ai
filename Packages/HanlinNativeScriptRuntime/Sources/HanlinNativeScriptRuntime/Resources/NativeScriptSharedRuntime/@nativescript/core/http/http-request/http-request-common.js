import { knownFolders, path } from '../../file-system';
export function getFilenameFromUrl(url) {
    const slashPos = url.lastIndexOf('/') + 1;
    const questionMarkPos = url.lastIndexOf('?');
    let actualFileName;
    if (questionMarkPos !== -1) {
        actualFileName = url.substring(slashPos, questionMarkPos);
    }
    else {
        actualFileName = url.substring(slashPos);
    }
    const result = path.join(knownFolders.documents().path, actualFileName);
    return result;
}
export function parseJSON(source) {
    const src = source.trim();
    const lastIndex = src.lastIndexOf(')');
    if (lastIndex === src.length - 1) {
        return JSON.parse(src.substring(src.indexOf('(') + 1, lastIndex));
    }
    return JSON.parse(src);
}
//# sourceMappingURL=http-request-common.js.map