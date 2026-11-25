export function readNonNegative(text, maximum) {
    const value = text.trim();
    if (!/^\d+(?:\.\d{1,2})?$/.test(value))
        return null;
    const number = Number(value);
    return Number.isFinite(number) && number <= maximum ? number : null;
}
export function splitBill(subtotal, taxPercent, tipPercent, people, wholeDollars) {
    const subtotalCents = Math.round(subtotal * 100);
    const taxCents = Math.round(subtotalCents * taxPercent / 100);
    const tipCents = Math.round(subtotalCents * tipPercent / 100);
    const totalCents = subtotalCents + taxCents + tipCents;
    const lowerShareCents = wholeDollars
        ? Math.ceil(totalCents / people / 100) * 100
        : Math.floor(totalCents / people);
    const higherShareCount = wholeDollars ? 0 : totalCents % people;
    const higherShareCents = lowerShareCents + (higherShareCount > 0 ? 1 : 0);
    return {
        subtotalCents, taxCents, tipCents, totalCents, lowerShareCents,
        higherShareCents, higherShareCount, people,
        extraCollectedCents: wholeDollars ? lowerShareCents * people - totalCents : 0,
    };
}
export function dollars(cents) {
    return '$' + (cents / 100).toFixed(2);
}
//# sourceMappingURL=model.js.map