import SwiftUI

@main
struct MyTimelineApp: App {
    var body: some Scene {
        WindowGroup {
            // PomodoroTrackerView now manages its own data state internally,
            // so we can create it directly without passing any data.
            PomodoroTrackerView()
        }
    }
}

#Preview {
    PomodoroTrackerView()
}
