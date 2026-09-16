export function getFileExtension(path) {
    if (!path) {
        return '';
    }
    const index = path.lastIndexOf('.');
    return index !== -1 ? path.substring(index + 1) : '';
}
//# sourceMappingURL=utils-shared.js.map