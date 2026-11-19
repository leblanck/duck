import OSLog

/// Unified logging. In Console.app, search for `subsystem:local.duck.reader`;
/// or in Terminal: `log show --last 1h --predicate 'subsystem == "local.duck.reader"'`.
enum Log {
    static let library = Logger(subsystem: "local.duck.reader", category: "library")
    static let reader = Logger(subsystem: "local.duck.reader", category: "reader")
}
