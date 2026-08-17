import Foundation

func pluralRu(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let absN = abs(n)
    let mod10 = absN % 10
    let mod100 = absN % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return few }
    return many
}
