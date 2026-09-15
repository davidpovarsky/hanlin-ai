import { ColorBase } from './color-common';
export class Color extends ColorBase {
    get ios() {
        if (!this._ios) {
            // iOS Color is using floating-point values in the [0, 1] range, so divide the components by 255
            this._ios = UIColor.alloc().initWithRedGreenBlueAlpha(this.r / 255, this.g / 255, this.b / 255, this.a / 255);
        }
        return this._ios;
    }
    static fromIosColor(value) {
        const r = new interop.Reference();
        const g = new interop.Reference();
        const b = new interop.Reference();
        const a = new interop.Reference();
        value.getRedGreenBlueAlpha(r, g, b, a);
        return new Color(Math.round(a.value * 255), Math.round(r.value * 255), Math.round(g.value * 255), Math.round(b.value * 255));
    }
}
//# sourceMappingURL=index.ios.js.map