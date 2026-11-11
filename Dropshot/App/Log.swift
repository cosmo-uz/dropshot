import os

enum Log {
    private static let subsystem = "app.dropshot.Dropshot"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let system = Logger(subsystem: subsystem, category: "system")
}
