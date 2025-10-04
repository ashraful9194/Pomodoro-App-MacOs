import SwiftUI
import Combine
import AVFoundation // For sound feedback

// We need to import AppKit for macOS-specific features.
#if os(macOS)
import AppKit
#endif

// MARK: - Data Models & Enums

// ProductiveSegment now requires a non-optional category.
struct ProductiveSegment: Identifiable, Codable, Equatable {
    let id = UUID()
    let startMinute: Int
    let durationMinutes: Int
    let category: String
}

// HourBlock remains structurally the same but now contains the new ProductiveSegment.
struct HourBlock: Identifiable, Codable, Equatable {
    let id = UUID()
    let hour: Int
    var productiveSegments: [ProductiveSegment]
}

// New Enum to manage the timer's current mode.
enum TimerMode {
    case work, shortBreak, longBreak
    
    var title: String {
        switch self {
        case .work: return "Work Session"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

// "tags" has been renamed to "categories" for clarity.
struct AppData: Codable {
    var productivityData: [String: [HourBlock]]
    var productiveSessionCount: Int
    var dailyGoalMinutes: Int
    var categories: [String]
    
    static var `default`: AppData {
        AppData(productivityData: [:], productiveSessionCount: 0, dailyGoalMinutes: 120, categories: ["Work", "Study", "Reading"])
    }
}

// MARK: - Sound Manager

class SoundManager {
    static let shared = SoundManager()
    private var audioPlayer: AVAudioPlayer?
    
    func playSound(named soundName: String) {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else {
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }
}


// MARK: - Main Container View

struct PomodoroTrackerView: View {
    // MARK: - State Properties
    
    @State private var appData: AppData = .default
    
    // Timer state
    @State private var timerMode: TimerMode = .work
    @State private var selectedDuration = 25 * 60
    @State private var timeRemaining = 25 * 60
    @State private var isTimerRunning = false
    
    // UI state
    @State private var displayedDate: Date = Date()
    @State private var showingCustomTimeAlert = false
    @State private var customTimeInput = "25"
    @State private var showingChartView = false
    @State private var currentStreak: Int = 0
    
    // State for the new, integrated category selection.
    @State private var selectedCategoryForSession: String? = nil
    @State private var newCategoryInput: String = ""
    
    // macOS-specific state
    @State private var keepOnTop = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Constants
    private let shortBreakDuration = 5 * 60
    private let longBreakDuration = 15 * 60
    private let sessionsPerLongBreak = 4
    
    private var presetDurationsInMinutes: [Int] { [15, 25, 45, 60] }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            timerControlsView
            Spacer()
            GoalAndStreakView(
                dailyGoalMinutes: $appData.dailyGoalMinutes,
                currentStreak: currentStreak
            )
            timelineView
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: onAppear)
        .onReceive(timer, perform: { _ in handleTimerTick() })
        .alert("Custom Duration", isPresented: $showingCustomTimeAlert) { customDurationAlert }
        .sheet(isPresented: $showingChartView) {
            ProductivityChartView(productivityData: appData.productivityData, allCategories: appData.categories)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                saveData()
            }
        }
        .onChange(of: appData.dailyGoalMinutes) { _ in
            saveData()
            updateStreak()
        }
        .onChange(of: keepOnTop, perform: { isOn in
            #if os(macOS)
            setWindowFloating(isOn)
            #endif
        })
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack {
            HStack {
                #if os(macOS)
                Toggle(isOn: $keepOnTop) { Image(systemName: "pin.fill") }.toggleStyle(.button)
                #endif
                Spacer()
                Text(timerMode.title).font(.largeTitle.bold())
                Spacer()
                Button(action: { showingChartView = true }) {
                    Image(systemName: "chart.bar.xaxis").font(.title2)
                }.buttonStyle(PlainButtonStyle())
            }
            .padding(.top)

            Text(timeString(from: timeRemaining))
                .font(.system(size: 80, weight: .thin, design: .monospaced))
                .padding(.vertical, 5)
            
            // Display the selected category while the timer is running.
            if isTimerRunning && timerMode == .work, let category = selectedCategoryForSession {
                Text("Category: \(category)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .transition(.opacity.animation(.easeInOut))
            } else {
                // Add a placeholder to prevent UI from jumping.
                Text(" ")
                    .font(.headline)
            }
        }
    }
    
    private var timerControlsView: some View {
        VStack {
            if timerMode == .work {
                // Duration selection
                HStack(spacing: 10) {
                    ForEach(presetDurationsInMinutes, id: \.self) { minutes in
                        Button("\(minutes) min") { selectDuration(minutes: minutes) }
                            .buttonStyle(PresetButtonStyle(isSelected: durationInSeconds(minutes) == selectedDuration))
                    }
                    Button("Custom") {
                        customTimeInput = "\(selectedDuration / 60)"
                        showingCustomTimeAlert = true
                    }
                    .buttonStyle(PresetButtonStyle(isSelected: !presetDurationsInMinutes.map { $0 * 60 }.contains(selectedDuration)))
                }
                .padding(.bottom, 20)
                .disabled(isTimerRunning)
                .opacity(isTimerRunning ? 0.5 : 1.0)
                
                // Category selector is now embedded here
                if !isTimerRunning {
                    VStack(spacing: 12) {
                        Text("Select or Add a Category")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appData.categories, id: \.self) { category in
                                    Button(category) {
                                        selectedCategoryForSession = category
                                    }
                                    .buttonStyle(PresetButtonStyle(isSelected: selectedCategoryForSession == category))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 35)

                        HStack {
                            TextField("New Category...", text: $newCategoryInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Add", action: addCategoryAndSelect)
                                .disabled(newCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 20)
                    .transition(.opacity)
                }
            }
            
            HStack(spacing: 20) {
                Button(action: {
                    if isTimerRunning {
                        // Pause action
                        isTimerRunning = false
                        SoundManager.shared.playSound(named: "timerPause")
                    } else {
                        // Start action
                        isTimerRunning = true
                        SoundManager.shared.playSound(named: "timerStart")
                    }
                }) {
                    Text(isTimerRunning ? "Pause" : "Start")
                        .font(.headline).frame(minWidth: 100).padding()
                        .background(isTimerRunning ? Color.orange : Color.green).foregroundColor(.white).cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(timerMode == .work && !isTimerRunning && selectedCategoryForSession == nil)
                
                Button(action: resetTimer) {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline).frame(width: 40, height: 40).padding(5)
                        .background(Color.gray.opacity(0.3)).foregroundColor(.primary).cornerRadius(12)
                }.buttonStyle(PlainButtonStyle())
                
                if timerMode != .work {
                    Button("Skip Break") { skipBreak() }
                        .font(.headline).padding().frame(height: 54)
                        .background(Color.blue.opacity(0.8)).foregroundColor(.white).cornerRadius(12)
                }
            }
        }
        .animation(.easeInOut, value: isTimerRunning)
        .animation(.easeInOut, value: timerMode)
    }

    private var timelineView: some View {
        VStack {
            Divider().padding(.top, 10)
            HStack {
                Button(action: goToPreviousDay) { Image(systemName: "chevron.left") }.buttonStyle(PlainButtonStyle())
                Spacer()
                Text(formattedDate(for: displayedDate)).font(.headline)
                Spacer()
                Button(action: goToNextDay) { Image(systemName: "chevron.right") }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isToday(displayedDate))
            }
            .padding(.top)
            .padding(.horizontal)

            DailyTimelineView(
                hourBlocks: blocksForDisplayedDate(),
                dailyGoalMinutes: appData.dailyGoalMinutes,
                date: displayedDate
            )
        }
        .padding(.bottom)
    }
    
    @ViewBuilder private var customDurationAlert: some View {
        TextField("Minutes", text: $customTimeInput)
        Button("Set") {
            if let minutes = Int(customTimeInput), minutes > 0 {
                selectDuration(minutes: minutes)
            }
        }
        Button("Cancel", role: .cancel) {}
    }
    
    // MARK: - Timer & State Logic
    
    private func onAppear() {
        loadData()
        updateStreak()
    }
    
    private func handleTimerTick() {
        guard isTimerRunning else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            isTimerRunning = false
            moveToNextMode()
        }
    }
    
    private func moveToNextMode() {
        if timerMode == .work {
            SoundManager.shared.playSound(named: "sessionComplete")
            
            // Log the session using the category selected *before* the timer started.
            // The force-unwrap is safe because a session cannot start without a category.
            logProductiveSession(duration: selectedDuration, category: selectedCategoryForSession!)

            appData.productiveSessionCount += 1
            if appData.productiveSessionCount >= sessionsPerLongBreak {
                appData.productiveSessionCount = 0
                timerMode = .longBreak
                timeRemaining = longBreakDuration
            } else {
                timerMode = .shortBreak
                timeRemaining = shortBreakDuration
            }
            isTimerRunning = true // Automatically start the break.
            SoundManager.shared.playSound(named: "timerStart")
            saveData()
        } else { // End of a break
            SoundManager.shared.playSound(named: "breakComplete")
            timerMode = .work
            timeRemaining = selectedDuration
            selectedCategoryForSession = nil // Reset category for the next work session.
        }
    }
    
    private func addCategoryAndSelect() {
        let trimmedCategory = newCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategory.isEmpty else { return }
        
        if !appData.categories.contains(trimmedCategory) {
            appData.categories.append(trimmedCategory)
        }
        selectedCategoryForSession = trimmedCategory
        newCategoryInput = ""
    }
    
    private func resetTimer() {
        isTimerRunning = false
        if timerMode == .work {
            // Also reset the selected category.
            selectedCategoryForSession = nil
        }
        switch timerMode {
        case .work: timeRemaining = selectedDuration
        case .shortBreak: timeRemaining = shortBreakDuration
        case .longBreak: timeRemaining = longBreakDuration
        }
    }
    
    private func selectDuration(minutes: Int) {
        selectedDuration = durationInSeconds(minutes)
        timeRemaining = selectedDuration
        resetTimer()
    }
    
    private func skipBreak() {
        SoundManager.shared.playSound(named: "breakComplete")
        timerMode = .work
        timeRemaining = selectedDuration
        isTimerRunning = false
        selectedCategoryForSession = nil // Reset category
    }
    
    // MARK: - macOS Specific Window Logic
    
    #if os(macOS)
    private func setWindowFloating(_ floating: Bool) {
        if let window = NSApplication.shared.keyWindow {
            window.level = floating ? .floating : .normal
        }
    }
    #endif
    
    // MARK: - Data Persistence Logic
    
    private var dataFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pomodoroData.json")
    }
    
    private func saveData() {
        do {
            let data = try JSONEncoder().encode(appData)
            try data.write(to: dataFileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Error saving data: \(error.localizedDescription)")
        }
    }
    
    private func loadData() {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            appData = .default
            setupInitialData()
            return
        }

        // Define structs for migrating from the previous version with optional tags.
        struct AppDataV2: Codable {
            var productivityData: [String: [HourBlockV2]]
            var productiveSessionCount: Int
            var dailyGoalMinutes: Int
            var tags: [String]
        }
        struct HourBlockV2: Codable, Identifiable {
            let id: UUID
            let hour: Int
            var productiveSegments: [ProductiveSegmentV2]
        }
        struct ProductiveSegmentV2: Codable, Identifiable {
            let id: UUID
            let startMinute: Int
            let durationMinutes: Int
            var tag: String?
        }
        
        do {
            let data = try Data(contentsOf: dataFileURL)
            // Attempt to decode the new format first.
            appData = try JSONDecoder().decode(AppData.self, from: data)
        } catch {
            // If it fails, attempt to decode and migrate the previous format.
            do {
                let data = try Data(contentsOf: dataFileURL)
                let oldData = try JSONDecoder().decode(AppDataV2.self, from: data)
                
                var migratedProductivityData: [String: [HourBlock]] = [:]
                let defaultCategory = "Uncategorized"
                
                for (dateKey, hourBlocksV2) in oldData.productivityData {
                    var newHourBlocks: [HourBlock] = []
                    for blockV2 in hourBlocksV2 {
                        let newSegments = blockV2.productiveSegments.map { segmentV2 -> ProductiveSegment in
                            ProductiveSegment(startMinute: segmentV2.startMinute, durationMinutes: segmentV2.durationMinutes, category: segmentV2.tag ?? defaultCategory)
                        }
                        newHourBlocks.append(HourBlock(hour: blockV2.hour, productiveSegments: newSegments))
                    }
                    migratedProductivityData[dateKey] = newHourBlocks
                }
                
                var migratedCategories = oldData.tags
                if !migratedCategories.contains(defaultCategory) {
                    migratedCategories.append(defaultCategory)
                }
                
                appData = AppData(
                    productivityData: migratedProductivityData,
                    productiveSessionCount: oldData.productiveSessionCount,
                    dailyGoalMinutes: oldData.dailyGoalMinutes,
                    categories: migratedCategories
                )
                
                saveData() // Save the newly migrated data immediately.
                print("Successfully migrated data to new category format.")
                
            } catch {
                print("Could not decode any known data format. Resetting to default. Error: \(error)")
                appData = .default
            }
        }
        
        setupInitialData()
    }
    
    // MARK: - Productivity & Streak Logic
    
    private func logProductiveSession(duration: Int, category: String) {
        let todayKey = dateKey(for: Date())
        let now = Date()
        let calendar = Calendar.current
        let durationMinutes = duration / 60
        guard durationMinutes > 0, let sessionStartDate = calendar.date(byAdding: .second, value: -duration, to: now) else { return }
        
        if appData.productivityData[todayKey] == nil {
            appData.productivityData[todayKey] = (0...23).map { HourBlock(hour: $0, productiveSegments: []) }
        }

        let startHour = calendar.component(.hour, from: sessionStartDate)
        let endHour = calendar.component(.hour, from: now)
        if startHour == endHour {
            if let hourIndex = appData.productivityData[todayKey]?.firstIndex(where: { $0.hour == startHour }) {
                let startMinute = calendar.component(.minute, from: sessionStartDate)
                let newSegment = ProductiveSegment(startMinute: startMinute, durationMinutes: durationMinutes, category: category)
                appData.productivityData[todayKey]?[hourIndex].productiveSegments.append(newSegment)
            }
        } else {
            if let startIndex = appData.productivityData[todayKey]?.firstIndex(where: { $0.hour == startHour }) {
                let startMinute = calendar.component(.minute, from: sessionStartDate)
                let segment = ProductiveSegment(startMinute: startMinute, durationMinutes: 60 - startMinute, category: category)
                appData.productivityData[todayKey]?[startIndex].productiveSegments.append(segment)
            }
            if let endIndex = appData.productivityData[todayKey]?.firstIndex(where: { $0.hour == endHour }) {
                let endMinute = calendar.component(.minute, from: now)
                if endMinute > 0 {
                    let segment = ProductiveSegment(startMinute: 0, durationMinutes: endMinute, category: category)
                    appData.productivityData[todayKey]?[endIndex].productiveSegments.append(segment)
                }
            }
        }
        updateStreak()
    }
    
    private func updateStreak() {
        self.currentStreak = calculateCurrentStreak()
    }
    
    private func calculateCurrentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var dateToCheck = Date()

        if !didMeetGoal(for: Date()) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: dateToCheck) else { return 0 }
            dateToCheck = yesterday
        }
        
        while didMeetGoal(for: dateToCheck) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dateToCheck) else { break }
            dateToCheck = previousDay
        }
        
        return streak
    }

    private func totalMinutes(for date: Date) -> Int {
        let key = dateKey(for: date)
        guard let blocks = appData.productivityData[key] else { return 0 }
        return blocks.flatMap { $0.productiveSegments }.reduce(0) { $0 + $1.durationMinutes }
    }
    
    private func didMeetGoal(for date: Date) -> Bool {
        return totalMinutes(for: date) >= appData.dailyGoalMinutes
    }
    
    // MARK: - Helper Functions
    
    private func setupInitialData() {
        let todayKey = dateKey(for: Date())
        if appData.productivityData[todayKey] == nil {
            appData.productivityData[todayKey] = (0...23).map { HourBlock(hour: $0, productiveSegments: []) }
        }
    }
    
    private func blocksForDisplayedDate() -> [HourBlock] {
        let key = dateKey(for: displayedDate)
        return appData.productivityData[key] ?? (0...23).map { HourBlock(hour: $0, productiveSegments: []) }
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func durationInSeconds(_ minutes: Int) -> Int {
        return minutes * 60
    }
    
    // MARK: - Date Navigation Logic
    
    private func goToPreviousDay() {
        if let newDate = Calendar.current.date(byAdding: .day, value: -1, to: displayedDate) {
            displayedDate = newDate
            let key = dateKey(for: newDate)
            if appData.productivityData[key] == nil {
                appData.productivityData[key] = (0...23).map { HourBlock(hour: $0, productiveSegments: []) }
            }
        }
    }
    
    private func goToNextDay() {
        if let newDate = Calendar.current.date(byAdding: .day, value: 1, to: displayedDate), !isToday(newDate) {
             if newDate < Date() { displayedDate = newDate }
        } else {
            displayedDate = Date()
        }
    }
    
    private func isToday(_ date: Date) -> Bool {
        return Calendar.current.isDateInToday(date)
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func formattedDate(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Helper Subviews & Styles

struct GoalAndStreakView: View {
    @Binding var dailyGoalMinutes: Int
    let currentStreak: Int
    
    private var goalInHours: String {
        String(format: "%.1fh", Double(dailyGoalMinutes) / 60.0)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("🔥 Current Streak").font(.caption).foregroundColor(.secondary)
                Text("\(currentStreak) Days").font(.title2.bold()).foregroundColor(currentStreak > 0 ? .orange : .primary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Daily Goal").font(.caption).foregroundColor(.secondary)
                Stepper("\(goalInHours)", value: $dailyGoalMinutes, in: 30...720, step: 30).frame(width: 150)
            }
        }
        .padding(.vertical, 10)
    }
}


struct PresetButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(isSelected ? .white : .primary).cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct DailyTimelineView: View {
    let hourBlocks: [HourBlock]
    let dailyGoalMinutes: Int
    let date: Date

    private var backgroundColor: Color {
        let calendar = Calendar.current
        let totalMinutes = hourBlocks.flatMap { $0.productiveSegments }.reduce(0) { $0 + $1.durationMinutes }
        let goalMet = totalMinutes >= dailyGoalMinutes
        
        if calendar.isDateInToday(date) {
            return goalMet ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1)
        } else if date < Date() {
            return goalMet ? Color.yellow.opacity(0.25) : Color.red.opacity(0.2)
        } else {
            return Color.secondary.opacity(0.1)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let totalSpacing = spacing * 23
            let blockWidth = (geometry.size.width - totalSpacing) / 24
            HStack(spacing: spacing) {
                ForEach(hourBlocks) { block in
                    HourBlockView(block: block, width: blockWidth)
                }
            }
        }
        .frame(height: 120)
        .background(backgroundColor)
        .cornerRadius(12)
        .padding(.horizontal)
        .animation(.easeInOut, value: backgroundColor)
    }
}

struct HourBlockView: View {
    let block: HourBlock
    let width: CGFloat
    private let totalMinutesInHour = 60.0

    private var formattedHour: (time: String, period: String) {
        let hour = block.hour
        let period = hour >= 12 ? "pm" : "am"
        var displayHour = hour % 12
        if displayHour == 0 { displayHour = 12 }
        return ("\(displayHour)", period)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text(formattedHour.time).font(.system(size: 12, weight: .medium, design: .monospaced))
                Text(formattedHour.period).font(.system(size: 9, weight: .regular, design: .monospaced))
            }
            .foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.6)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.red.opacity(0.7))
                GeometryReader { geometry in
                    ForEach(block.productiveSegments) { segment in
                        Rectangle().fill(Color.green)
                            .frame(width: calculateWidth(for: segment, in: geometry.size))
                            .offset(x: calculateOffset(for: segment, in: geometry.size))
                    }
                }
            }
            .frame(width: width, height: 60).cornerRadius(6).clipped()
            .animation(.easeInOut, value: block.productiveSegments)
        }
    }

    private func calculateWidth(for segment: ProductiveSegment, in size: CGSize) -> CGFloat {
        (size.width / totalMinutesInHour) * CGFloat(segment.durationMinutes)
    }

    private func calculateOffset(for segment: ProductiveSegment, in size: CGSize) -> CGFloat {
        (size.width / totalMinutesInHour) * CGFloat(segment.startMinute)
    }
}

// MARK: - Preview Provider

struct PomodoroTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroTrackerView()
    }
}
