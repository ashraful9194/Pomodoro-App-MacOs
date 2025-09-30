import SwiftUI
import Charts

// A simple enum to switch between weekly and monthly views.
enum TimeRange: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    var id: Self { self }
}

// A helper struct to hold aggregated data for charting.
struct DailyProductivity: Identifiable {
    let id = UUID()
    let date: Date
    let totalMinutes: Int
}

struct ProductivityChartView: View {
    // The source of truth for all logged data.
    let productivityData: [String: [HourBlock]]
    
    @State private var displayDate: Date = Date()
    @State private var timeRange: TimeRange = .weekly
    @Environment(\.dismiss) private var dismiss

    // A computed property that aggregates data based on the selected time range.
    private var chartData: [DailyProductivity] {
        return aggregateData(for: displayDate, in: timeRange)
    }
    
    // A computed property for the total productive time in the current view.
    private var totalProductiveTime: String {
        let totalMinutes = chartData.reduce(0) { $0 + $1.totalMinutes }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }
    
    // A computed property for the formatted date range string.
    private var dateRangeString: String {
        let calendar = Calendar.current
        let component: Calendar.Component = timeRange == .weekly ? .weekOfYear : .month
        guard let interval = calendar.dateInterval(of: component, for: displayDate) else { return "" }
        
        let formatter = DateFormatter()
        
        if timeRange == .weekly {
            formatter.dateFormat = "MMM d"
            // The interval's end is the start of the next period, so subtract one day for display.
            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: endDate))"
        } else { // Monthly
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: displayDate)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Header
            HStack {
                Text("Productivity Stats")
                    .font(.largeTitle.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // MARK: - Time Range Picker
            Picker("Time Range", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            
            // MARK: - Date Navigation and Total
            HStack {
                Button(action: goToPreviousPeriod) { Image(systemName: "chevron.left") }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                VStack {
                    Text(dateRangeString)
                        .font(.headline)
                    Text("Total: \(totalProductiveTime)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: goToNextPeriod) { Image(systemName: "chevron.right") }
                .buttonStyle(PlainButtonStyle())
                .disabled(isCurrentPeriod)
            }
            
            // MARK: - Chart
            Chart(chartData) { dataPoint in
                BarMark(
                    x: .value("Day", dataPoint.date, unit: .day),
                    y: .value("Minutes", dataPoint.totalMinutes)
                )
                // Use a different color for days with no activity
                .foregroundStyle(dataPoint.totalMinutes > 0 ? Color.green.gradient : Color.gray.opacity(0.3).gradient)
                .cornerRadius(6)
            }
            .chartXAxis {
                if timeRange == .weekly {
                    // For the weekly view, show the initial of each weekday.
                    AxisMarks(values: .stride(by: .day)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                } else { // Monthly
                    // For the monthly view, labeling every day is too cluttered.
                    // Instead, we'll place a label at the start of each week, showing the day number.
                    AxisMarks(values: .stride(by: .weekOfYear, count: 1)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.day(), centered: false)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue / 60)h")
                        }
                    }
                }
            }
            .frame(height: 300)

            Spacer()
        }
        .padding()
    }

    // MARK: - Data Aggregation
    
    /// Aggregates productivity data for every day within a given time range (week or month).
    private func aggregateData(for date: Date, in timeRange: TimeRange) -> [DailyProductivity] {
        let calendar = Calendar.current
        let component: Calendar.Component = timeRange == .weekly ? .weekOfYear : .month
        guard let interval = calendar.dateInterval(of: component, for: date) else { return [] }
        
        // 1. Pre-process all productivity data into a dictionary for fast lookups.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dailyTotals: [Date: Int] = productivityData.reduce(into: [:]) { (result, data) in
            guard let date = formatter.date(from: data.key) else { return }
            let startOfDay = calendar.startOfDay(for: date)
            let totalMinutes = data.value.flatMap { $0.productiveSegments }.reduce(0) { $0 + $1.durationMinutes }
            result[startOfDay, default: 0] += totalMinutes
        }
        
        // 2. Create a data point for every single day in the requested interval.
        var allDaysData: [DailyProductivity] = []
        var currentDate = interval.start
        
        while currentDate < interval.end {
            let totalMinutes = dailyTotals[currentDate] ?? 0
            allDaysData.append(DailyProductivity(date: currentDate, totalMinutes: totalMinutes))
            
            // Move to the next day.
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return allDaysData
    }
    
    // MARK: - Date Navigation
    
    private var isCurrentPeriod: Bool {
        Calendar.current.isDate(displayDate, equalTo: Date(), toGranularity: timeRange == .weekly ? .weekOfYear : .month)
    }
    
    private func goToPreviousPeriod() {
        let component: Calendar.Component = timeRange == .weekly ? .weekOfYear : .month
        if let newDate = Calendar.current.date(byAdding: component, value: -1, to: displayDate) {
            displayDate = newDate
        }
    }
    
    private func goToNextPeriod() {
        let component: Calendar.Component = timeRange == .weekly ? .weekOfYear : .month
        if let newDate = Calendar.current.date(byAdding: component, value: 1, to: displayDate), newDate <= Date() {
            displayDate = newDate
        }
    }
}
