// Russian noun pluralization.
// `one` covers 1, 21, 31, ... (genitive sing.: "лунка")
// `few` covers 2-4, 22-24, ... (genitive plural sing.: "лунки")
// `many` covers 0, 5-20, 25-30, ... (genitive plural: "лунок")
//
// Examples:
//   pluralRu(1,  'лунка', 'лунки', 'лунок') === 'лунка'
//   pluralRu(3,  'лунка', 'лунки', 'лунок') === 'лунки'
//   pluralRu(5,  'лунка', 'лунки', 'лунок') === 'лунок'
//   pluralRu(21, 'лунка', 'лунки', 'лунок') === 'лунка'
//   pluralRu(11, 'лунка', 'лунки', 'лунок') === 'лунок'  // teens are special
export function pluralRu(n: number, one: string, few: string, many: string): string {
  const abs = Math.abs(n)
  const mod10 = abs % 10
  const mod100 = abs % 100
  if (mod10 === 1 && mod100 !== 11) return one
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few
  return many
}
