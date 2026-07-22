#!/usr/bin/env swift

import Darwin
import EventKit
import Foundation

// Read-only EventKit diagnostic for comparing what Zebra can acquire with what
// the Reminders app displays. This script never saves, updates, or deletes data.

let store = EKEventStore()

func authorizationName(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"
    case .authorized: return "authorized"
    @unknown default: return "unknown(\(status.rawValue))"
    }
}

func sourceTypeName(_ type: EKSourceType) -> String {
    switch type {
    case .local: return "local"
    case .exchange: return "exchange"
    case .calDAV: return "calDAV"
    case .mobileMe: return "mobileMe"
    case .subscribed: return "subscribed"
    case .birthdays: return "birthdays"
    @unknown default: return "unknown(\(type.rawValue))"
    }
}

func requestAccessIfNeeded() -> (granted: Bool, error: String?) {
    let current = EKEventStore.authorizationStatus(for: .reminder)
    if #available(macOS 14.0, *) {
        if current == .fullAccess { return (true, nil) }
    } else if current == .authorized {
        return (true, nil)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    var failure: String?

    if #available(macOS 14.0, *) {
        store.requestFullAccessToReminders { allowed, error in
            granted = allowed
            failure = error.map { String(describing: $0) }
            semaphore.signal()
        }
    } else {
        store.requestAccess(to: .reminder) { allowed, error in
            granted = allowed
            failure = error.map { String(describing: $0) }
            semaphore.signal()
        }
    }

    guard semaphore.wait(timeout: .now() + 120) == .success else {
        return (false, "authorization_timeout")
    }
    return (granted, failure)
}

func fetchReminders(in calendars: [EKCalendar]) -> (reminders: [EKReminder], error: String?) {
    guard !calendars.isEmpty else { return ([], nil) }
    let semaphore = DispatchSemaphore(value: 0)
    var fetched: [EKReminder] = []
    let predicate = store.predicateForReminders(in: calendars)
    store.fetchReminders(matching: predicate) { reminders in
        fetched = reminders ?? []
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 120) == .success else {
        return ([], "fetch_timeout")
    }
    return (fetched, nil)
}

func iso8601(_ components: DateComponents?) -> String? {
    guard let components, let date = Calendar.current.date(from: components) else { return nil }
    return ISO8601DateFormatter().string(from: date)
}

let access = requestAccessIfNeeded()
let status = EKEventStore.authorizationStatus(for: .reminder)
guard access.granted else {
    let failure: [String: Any] = [
        "ok": false,
        "authorizationStatus": authorizationName(status),
        "error": access.error ?? "reminders_access_not_granted",
    ]
    let data = try JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(1)
}

let calendars = store.calendars(for: .reminder)
var calendarResults: [[String: Any]] = []
var totalReminderCount = 0

for calendar in calendars {
    let result = fetchReminders(in: [calendar])
    totalReminderCount += result.reminders.count
    let reminders: [[String: Any]] = result.reminders.map { reminder in
        var value: [String: Any] = [
            "id": reminder.calendarItemIdentifier,
            "title": reminder.title ?? "",
            "isCompleted": reminder.isCompleted,
            "priority": reminder.priority,
            "calendarID": reminder.calendar.calendarIdentifier,
            "calendarTitle": reminder.calendar.title,
        ]
        if let notes = reminder.notes { value["notes"] = notes }
        if let dueDate = iso8601(reminder.dueDateComponents) { value["dueDate"] = dueDate }
        return value
    }

    var calendarValue: [String: Any] = [
        "id": calendar.calendarIdentifier,
        "title": calendar.title,
        "type": calendar.type.rawValue,
        "allowsContentModifications": calendar.allowsContentModifications,
        "source": [
            "id": calendar.source.sourceIdentifier,
            "title": calendar.source.title,
            "type": sourceTypeName(calendar.source.sourceType),
            "typeRawValue": calendar.source.sourceType.rawValue,
        ],
        "reminderCount": reminders.count,
        "openReminderCount": reminders.filter { ($0["isCompleted"] as? Bool) == false }.count,
        "reminders": reminders,
    ]
    if let error = result.error { calendarValue["error"] = error }
    calendarResults.append(calendarValue)
}

let output: [String: Any] = [
    "ok": true,
    "authorizationStatus": authorizationName(status),
    "calendarCount": calendarResults.count,
    "reminderCount": totalReminderCount,
    "calendars": calendarResults,
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
