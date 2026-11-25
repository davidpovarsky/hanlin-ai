export interface BillSplit {
  subtotalCents: number;
  taxCents: number;
  tipCents: number;
  totalCents: number;
  lowerShareCents: number;
  higherShareCents: number;
  higherShareCount: number;
  people: number;
  extraCollectedCents: number;
}

export function readNonNegative(text: string, maximum: number): number | null {
  const value = text.trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(value)) return null;
  const number = Number(value);
  return Number.isFinite(number) && number <= maximum ? number : null;
}

export function splitBill(
  subtotal: number,
  taxPercent: number,
  tipPercent: number,
  people: number,
  wholeDollars: boolean,
): BillSplit {
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

export function dollars(cents: number): string {
  return '$' + (cents / 100).toFixed(2);
}
