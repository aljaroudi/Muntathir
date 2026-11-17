// Exports Apple's Umm al-Qura month starts so Android uses the same baseline as iOS.
// Run from the repository root: swift shared/scripts/export-ummalqura.swift
// Writes shared/ummalqura.json: the first month's Gregorian start plus each month's
// length as one character ("9" = 29 days, "0" = 30 days). Android's core module ships it.
import Foundation

let zone = TimeZone(identifier: "GMT")!
var hijri = Calendar(identifier: .islamicUmmAlQura)
hijri.timeZone = zone
var gregorian = Calendar(identifier: .gregorian)
gregorian.timeZone = zone

func start(_ index: Int) -> Date {
    hijri.date(from: DateComponents(year: index / 12, month: index % 12 + 1, day: 1))!
}

// One month either side of the supported 1350–1500 range so neighbors always resolve.
let first = 1349 * 12 + 11
let last = 1501 * 12 + 0
var lengths = ""
for index in first ... last {
    let days = gregorian.dateComponents([.day], from: start(index), to: start(index + 1)).day!
    precondition(days == 29 || days == 30, "Unexpected month length \(days)")
    lengths += days == 29 ? "9" : "0"
}
let parts = gregorian.dateComponents([.year, .month, .day], from: start(first))
let json = """
{
  "source": "Apple Foundation Calendar(identifier: .islamicUmmAlQura), GMT",
  "first": { "year": \(first / 12), "month": \(first % 12 + 1) },
  "start": "\(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))",
  "lengths": "\(lengths)"
}

"""
let url = URL(fileURLWithPath: "shared/ummalqura.json")
try json.write(to: url, atomically: true, encoding: .utf8)
print("Wrote \(lengths.count) months to \(url.path)")
