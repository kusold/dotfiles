// EventKit probe for NextEvent.spoon: prints today's remaining events as JSON.
//
// This exists as a separate signed app bundle rather than Lua in the spoon because
// Hammerspoon cannot be granted calendar access at all: its Info.plist carries no
// NSCalendarsUsageDescription, so macOS refuses the request without prompting, and
// hs.sqlite3 on the Calendar store is refused by TCC with SQLITE_AUTH. The bundle
// around this binary is what holds the grant.

import EventKit
import Foundation

// startsAt/endsAt rather than start/end: `end` is a Lua keyword, and the consumer
// would otherwise have to spell every access e["end"].
struct Event: Encodable {
    let title: String
    let startsAt: Double
    let endsAt: Double
    let calendar: String
    let location: String?
    let url: String?
    let inProgress: Bool
}

struct Payload: Encodable {
    let now: Double
    let events: [Event]
}

// Where to leave the JSON. Launched through LaunchServices there is no stdout to
// inherit, so a path argument is how the caller gets the answer back; run by hand
// with no argument it just prints.
let outPath: String? = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

func emit(_ json: String) {
    guard let path = outPath else {
        print(json)
        return
    }
    // Written beside the target and renamed, so a reader polling the file never sees
    // a half-written payload and mistakes it for a malformed one.
    let tmp = path + ".tmp"
    do {
        try json.write(toFile: tmp, atomically: false, encoding: .utf8)
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                  withItemAt: URL(fileURLWithPath: tmp))
        if FileManager.default.fileExists(atPath: tmp) {
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
        }
    } catch {
        FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    }
}

func fail(_ reason: String, _ code: Int32) -> Never {
    emit("{\"error\":\"\(reason)\"}")
    exit(code)
}

let store = EKEventStore()
var granted = false
let sem = DispatchSemaphore(value: 0)

store.requestFullAccessToEvents { ok, _ in
    granted = ok
    sem.signal()
}

// A first run pops the TCC prompt, and an unattended one would otherwise hang here
// holding a Hammerspoon task open forever.
if sem.wait(timeout: .now() + 25) == .timedOut {
    fail("access-timeout", 3)
}
guard granted else { fail("no-access", 2) }

let now = Date()
let cal = Calendar.current
guard let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
    fail("bad-day-bounds", 4)
}

// predicateForEvents matches anything *overlapping* the window, so this also catches
// a meeting already under way; inProgress is what separates the two downstream.
let matched = store.events(matching: store.predicateForEvents(withStart: now,
                                                              end: dayEnd,
                                                              calendars: nil))

var seen = Set<String>()
var events: [Event] = []

for e in matched.sorted(by: { $0.startDate < $1.startDate }) {
    if e.isAllDay { continue }
    if e.status == .canceled { continue }

    // An invitation this account has declined is not an upcoming commitment. The
    // organiser's own copy has no attendee entry for the current user, so a nil
    // match here has to mean "not declined" rather than "unknown".
    if let mine = e.attendees?.first(where: { $0.isCurrentUser }),
       mine.participantStatus == .declined { continue }

    // The same Google calendar is subscribed several times over in this account, so
    // one meeting arrives once per subscription. Title plus start is what identifies
    // the duplicates; ISO strings would compare identically but cost a formatter.
    let key = "\(e.title ?? "")|\(e.startDate.timeIntervalSince1970)"
    if seen.contains(key) { continue }
    seen.insert(key)

    events.append(Event(title: e.title ?? "(no title)",
                        startsAt: e.startDate.timeIntervalSince1970,
                        endsAt: e.endDate.timeIntervalSince1970,
                        calendar: e.calendar.title,
                        location: e.location,
                        url: e.url?.absoluteString,
                        inProgress: e.startDate <= now && e.endDate > now))
}

let data = try JSONEncoder().encode(Payload(now: now.timeIntervalSince1970, events: events))
emit(String(data: data, encoding: .utf8) ?? "{\"error\":\"encode\"}")
