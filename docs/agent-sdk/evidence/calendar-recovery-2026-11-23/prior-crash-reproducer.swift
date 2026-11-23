import Foundation
if CommandLine.arguments[1] == "interval" {
 let start = Date(timeIntervalSince1970: 10000000)
 let end = Date(timeIntervalSince1970: 0)
 print(DateInterval(start: start, end: end))
} else {
 let minutes = Int(CommandLine.arguments[2])!
 print(TimeInterval(minutes * 60))
}
