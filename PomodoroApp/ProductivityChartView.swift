import SwiftUI
import Charts

// A simple enum to switch between weekly, monthly, and yearly views for the bar chart.
enum TimeRange: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    var id: Self { self }
}

// A new enum to switch between the Bar Chart, Heatmap, and Time of Day views.
enum ChartViewType: String, CaseIterable, Identifiable {
    case barChart = "Bar Chart"
    case heatmap = "Heatmap"
    case timeOfDay = "Time of Day"
    var id: Self { self }
}

// A helper struct to hold aggregated data for charting.
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date // Represents the day for weekly/monthly, or the month for yearly.
    let totalMinutes: Int
}

// A helper struct for the time of day chart.
struct TimeOfDayDataPoint: Identifiable {
    let id = UUID()
    let hour: Int // 0-23
    let totalMinutes: Int
}

struct ProductivityChartView: View {
    // The source of truth for all logged data.
    let productivityData: [String: [HourBlock]]
    let allCategories: [String]
    
    @State private var displayDate: Date = Date()
    @State private var viewType: ChartViewType = .barChart
    @State private var timeRange: TimeRange = .weekly
    @State private var selectedCategory: String? = nil
    @Environment(\.dismiss) private var dismiss

    // Custom calendar with Saturday as the first day of the week.
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 7 // 1 = Sunday, 7 = Saturday
        return calendar
    }

    // A computed property that aggregates data for the bar chart.
    private var chartData: [ChartDataPoint] {
        return aggregateData(for: displayDate, in: timeRange, filteredBy: selectedCategory)
    }
    
    // This pre-processes all daily totals for the currently selected category.
    private var dailyTotals: [Date: Int] {
        preprocessedDailyTotals(forCategory: selectedCategory)
    }
    
    // A computed property that aggregates data for the time of day chart.
    private var timeOfDayData: [TimeOfDayDataPoint] {
        aggregateTimeOfDayData(filteredBy: selectedCategory)
    }
    
    // A computed property for the total productive time in the current view.
    private var totalProductiveTime: String {
        let totalMinutes: Int
        switch viewType {
        case .barChart:
            totalMinutes = chartData.reduce(0) { $0 + $1.totalMinutes }
        case .heatmap:
            guard let yearInterval = calendar.dateInterval(of: .year, for: displayDate) else { return "0h 0m" }
            totalMinutes = dailyTotals.filter { yearInterval.contains($0.key) }.reduce(0) { $0 + $1.value }
        case .timeOfDay:
            totalMinutes = timeOfDayData.reduce(0) { $0 + $1.totalMinutes }
        }
        
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }
    
    // A computed property for the formatted date range string.
    private var dateRangeString: String {
        let formatter = DateFormatter()
        
        switch viewType {
        case .heatmap:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: displayDate)
        case .timeOfDay:
            return "All Time"
        case .barChart:
            switch timeRange {
            case .weekly:
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: displayDate) else { return "" }
                formatter.dateFormat = "MMM d"
                let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
                return "\(formatter.string(from: interval.start)) - \(formatter.string(from: endDate))"
            case .monthly:
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: displayDate)
            case .yearly:
                formatter.dateFormat = "yyyy"
                return formatter.string(from: displayDate)
            }
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
            
            // MARK: - Filter Controls
            Picker("View Type", selection: $viewType) {
                ForEach(ChartViewType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                if viewType == .barChart {
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(String?.none)
                    ForEach(allCategories, id: \.self) { category in
                        Text(category).tag(String?.some(category))
                    }
                }
                .pickerStyle(.menu)
            }

            // MARK: - Date Navigation and Total
            HStack {
                Button(action: goToPreviousPeriod) { Image(systemName: "chevron.left") }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(viewType == .timeOfDay ? 0 : 1)
                    .disabled(viewType == .timeOfDay)
                
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
                    .disabled(isCurrentPeriod || viewType == .timeOfDay)
                    .opacity(viewType == .timeOfDay ? 0 : 1)
            }
            
            // MARK: - Main Content (Chart or Heatmap)
            switch viewType {
            case .barChart:
                barChartView
            case .heatmap:
                ProductivityHeatmapView(
                    dailyTotals: dailyTotals,
                    year: displayDate,
                    calendar: calendar
                )
            case .timeOfDay:
                timeOfDayChartView
            }

            Spacer()
        }
        .padding()
    }
    
    private var barChartView: some View {
        Chart(chartData) { dataPoint in
            BarMark(
                x: .value("Date", dataPoint.date, unit: timeRange == .yearly ? .month : .day),
                y: .value("Minutes", dataPoint.totalMinutes)
            )
            .foregroundStyle(dataPoint.totalMinutes > 0 ? Color.green.gradient : Color.gray.opacity(0.3).gradient)
            .cornerRadius(6)
        }
        .chartXAxis {
            switch timeRange {
            case .weekly:
                AxisMarks(values: .stride(by: .day)) {
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            case .monthly:
                AxisMarks(values: .stride(by: .weekOfYear, count: 1)) { value in
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.day(), centered: false)
                }
            case .yearly:
                AxisMarks(values: .stride(by: .month)) {
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .stride(by: 60)) { value in
                AxisGridLine()
                AxisValueLabel { if let intValue = value.as(Int.self) { Text("\(intValue / 60)h") } }
            }
        }
        .frame(height: 300)
    }
    
    private var timeOfDayChartView: some View {
        Chart(timeOfDayData) { dataPoint in
            BarMark(
                x: .value("Hour", dataPoint.hour),
                y: .value("Minutes", dataPoint.totalMinutes)
            )
            .foregroundStyle(dataPoint.totalMinutes > 0 ? Color.green.gradient : Color.gray.opacity(0.3).gradient)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                if let hour = value.as(Int.self) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(formattedHourForAxis(hour))
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .stride(by: 60)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue / 60)h")
                    }
                }
            }
        }
        .frame(height: 300)
    }
    
    // MARK: - Data Aggregation
    
    private func preprocessedDailyTotals(forCategory category: String?) -> [Date: Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        return productivityData.reduce(into: [:]) { (result, data) in
            guard let date = formatter.date(from: data.key) else { return }
            let startOfDay = calendar.startOfDay(for: date)
            
            let allSegments = data.value.flatMap { $0.productiveSegments }
            
            let filteredSegments = allSegments.filter { segment in
                if let selectedCategory = category {
                    return segment.category == selectedCategory
                }
                return true
            }
            
            let totalMinutes = filteredSegments.reduce(0) { $0 + $1.durationMinutes }
            result[startOfDay, default: 0] += totalMinutes
        }
    }
    
    private func aggregateData(for date: Date, in timeRange: TimeRange, filteredBy category: String?) -> [ChartDataPoint] {
        let dailyTotals = preprocessedDailyTotals(forCategory: category)

        switch timeRange {
        case .weekly, .monthly:
            let component: Calendar.Component = timeRange == .weekly ? .weekOfYear : .month
            guard let interval = calendar.dateInterval(of: component, for: date) else { return [] }
            
            var aggregatedData: [ChartDataPoint] = []
            var currentDate = interval.start
            
            while currentDate < interval.end {
                let totalMinutes = dailyTotals[currentDate] ?? 0
                aggregatedData.append(ChartDataPoint(date: currentDate, totalMinutes: totalMinutes))
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                currentDate = nextDate
            }
            return aggregatedData
            
        case .yearly:
            guard let yearInterval = calendar.dateInterval(of: .year, for: date) else { return [] }
            let monthlyTotals: [Date: Int] = dailyTotals.reduce(into: [:]) { result, dailyData in
                guard yearInterval.contains(dailyData.key) else { return }
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: dailyData.key))!
                result[startOfMonth, default: 0] += dailyData.value
            }
            
            var aggregatedData: [ChartDataPoint] = []
            for monthOffset in 0..<12 {
                guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: yearInterval.start) else { continue }
                let totalMinutes = monthlyTotals[monthDate] ?? 0
                aggregatedData.append(ChartDataPoint(date: monthDate, totalMinutes: totalMinutes))
            }
            return aggregatedData
        }
    }
    
    private func aggregateTimeOfDayData(filteredBy category: String?) -> [TimeOfDayDataPoint] {
        var hourlyTotals = Array(repeating: 0, count: 24)
        
        for (_, hourBlocks) in productivityData {
            for block in hourBlocks {
                let filteredSegments = block.productiveSegments.filter { segment in
                    if let selectedCategory = category {
                        return segment.category == selectedCategory
                    }
                    return true
                }
                
                for segment in filteredSegments {
                    hourlyTotals[block.hour] += segment.durationMinutes
                }
            }
        }
        
        return hourlyTotals.enumerated().map { (hour, minutes) in
            TimeOfDayDataPoint(hour: hour, totalMinutes: minutes)
        }
    }
    
    // MARK: - Date Navigation
    
    private var componentForTimeRange: Calendar.Component {
        if viewType == .heatmap { return .year }
        
        switch timeRange {
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
    
    private var isCurrentPeriod: Bool {
        calendar.isDate(displayDate, equalTo: Date(), toGranularity: componentForTimeRange)
    }
    
    private func goToPreviousPeriod() {
        if let newDate = calendar.date(byAdding: componentForTimeRange, value: -1, to: displayDate) {
            displayDate = newDate
        }
    }
    
    private func goToNextPeriod() {
        if let newDate = calendar.date(byAdding: componentForTimeRange, value: 1, to: displayDate), newDate <= Date() {
            displayDate = newDate
        }
    }
    
    // MARK: - Helpers
    
    private func formattedHourForAxis(_ hour: Int) -> String {
        let date = calendar.date(bySetting: .hour, value: hour, of: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Heatmap Subviews

struct TooltipPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ProductivityHeatmapView: View {
    let dailyTotals: [Date: Int]
    let year: Date
    let calendar: Calendar

    @State private var hoveredDate: Date?

    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 2), count: 53)
    private let rows: [GridItem] = Array(repeating: .init(.flexible(), spacing: 2), count: 7)

    private var yearData: (days: [Date], maxMinutes: Int) {
        guard let yearInterval = calendar.dateInterval(of: .year, for: year) else { return ([], 0) }
        
        var days: [Date] = []
        var currentDate = yearInterval.start
        while currentDate < yearInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        let maxMinutes = 12 * 60
        return (days, maxMinutes)
    }

    private var firstDayOffset: Int {
        let firstDay = calendar.dateInterval(of: .year, for: year)!.start
        return (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
    }

    private func tooltipText(for day: Date, minutes: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d/M"
        let dateString = dateFormatter.string(from: day)

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let timeString = "\(hours)h \(remainingMinutes)m"
        
        return "\(dateString): \(timeString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthLabels
            
            HStack(spacing: 4) {
                weekdayLabels
                
                let (days, maxMinutes) = yearData
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: rows, spacing: 2) {
                        ForEach(0..<firstDayOffset, id: \.self) { _ in
                            Color.clear.frame(width: 15, height: 15)
                        }

                        ForEach(days, id: \.self) { day in
                            let minutes = dailyTotals[day] ?? 0
                            let opacity = maxMinutes > 0 ? Double(minutes) / Double(maxMinutes) : 0
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(minutes == 0 ? Color.gray.opacity(0.3) : Color.green.opacity(0.2 + (opacity * 0.8)))
                                .frame(width: 15, height: 15)
                                .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) {
                                    hoveredDate == day ? $0 : nil
                                }
                                .onHover { isHovering in
                                    if isHovering { self.hoveredDate = day }
                                }
                        }
                    }
                    .onHover { isHovering in
                        if !isHovering { self.hoveredDate = nil }
                    }
                }
            }
            HeatmapLegendView(maxMinutes: yearData.maxMinutes)
        }
        .overlayPreferenceValue(TooltipPreferenceKey.self) { anchor in
            if let anchor = anchor, let date = hoveredDate {
                GeometryReader { proxy in
                    let rect = proxy[anchor]
                    let minutes = dailyTotals[date] ?? 0
                    let text = tooltipText(for: date, minutes: minutes)
                    
                    Text(text)
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .shadow(radius: 2)
                        .position(x: rect.midX, y: rect.minY)
                        .offset(y: -15)
                        .allowsHitTesting(false)
                }
                .animation(.easeInOut(duration: 0.1), value: hoveredDate)
            }
        }
        .frame(height: 300)
    }
    
    private var monthLabels: some View {
        HStack {
            Text("J").frame(maxWidth: .infinity); Text("F").frame(maxWidth: .infinity)
            Text("M").frame(maxWidth: .infinity); Text("A").frame(maxWidth: .infinity)
            Text("M").frame(maxWidth: .infinity); Text("J").frame(maxWidth: .infinity)
            Text("J").frame(maxWidth: .infinity); Text("A").frame(maxWidth: .infinity)
            Text("S").frame(maxWidth: .infinity); Text("O").frame(maxWidth: .infinity)
            Text("N").frame(maxWidth: .infinity); Text("D").frame(maxWidth: .infinity)
        }
        .font(.caption).foregroundColor(.secondary).padding(.leading, 30)
    }
    
    private var weekdayLabels: some View {
        VStack(spacing: 12) {
            Text("Sat").font(.caption); Spacer(); Text("Mon").font(.caption); Spacer()
            Text("Wed").font(.caption); Spacer(); Text("Fri").font(.caption)
        }
        .foregroundColor(.secondary)
    }
}

struct HeatmapLegendView: View {
    let maxMinutes: Int
    
    private var maxHours: String {
        String(format: "%.1f", Double(maxMinutes) / 60.0)
    }
    
    var body: some View {
        HStack {
            Text("Less")
            RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.3)).frame(width: 15, height: 15)
            RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.2)).frame(width: 15, height: 15)
            RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.6)).frame(width: 15, height: 15)
            RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(1.0)).frame(width: 15, height: 15)
            Text("More (~\(maxHours)h)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
