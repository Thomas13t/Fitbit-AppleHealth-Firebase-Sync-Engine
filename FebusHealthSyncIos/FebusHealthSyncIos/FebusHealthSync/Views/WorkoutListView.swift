import SwiftUI
import FirebaseAuth

enum WorkoutSortType: String, CaseIterable {
    case date = "Date"
    case type = "Type"
}

enum WorkoutDateFilter: String, CaseIterable {
    case all = "All Time"
    case today = "Today"
    case last7 = "Last 7 Days"
    case last30 = "Last 30 Days"
}

enum WorkoutTypeFilter: String, CaseIterable {
    case all = "All Types"
    case running = "Running"
    case cycling = "Cycling"
    case walking = "Walking"
    case other = "Other"
}

struct WorkoutListView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var syncManager: SyncManager
    
    @State private var recentWorkouts: [WorkoutData] = []
    @State private var isLoading = false
    @State private var sortType: WorkoutSortType = .date
    @State private var dateFilter: WorkoutDateFilter = .all
    @State private var typeFilter: WorkoutTypeFilter = .all
    
    private let firestoreService = FirestoreService()
    
    var filteredAndSortedWorkouts: [WorkoutData] {
        var filtered = recentWorkouts
        
        let now = Date()
        let calendar = Calendar.current
        
        // Apply Date Filter
        switch dateFilter {
        case .all: break
        case .today:
            filtered = filtered.filter { calendar.isDateInToday($0.startDate) }
        case .last7:
            if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) {
                filtered = filtered.filter { $0.startDate >= sevenDaysAgo }
            }
        case .last30:
            if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) {
                filtered = filtered.filter { $0.startDate >= thirtyDaysAgo }
            }
        }
        
        // Apply Type Filter
        switch typeFilter {
        case .all: break
        case .running:
            filtered = filtered.filter { $0.workoutActivityType == 37 }
        case .cycling:
            filtered = filtered.filter { $0.workoutActivityType == 13 }
        case .walking:
            filtered = filtered.filter { $0.workoutActivityType == 52 }
        case .other:
            filtered = filtered.filter { ![37, 13, 52].contains($0.workoutActivityType) }
        }
        
        // Apply Sorting
        switch sortType {
        case .date:
            return filtered.sorted { $0.startDate > $1.startDate }
        case .type:
            return filtered.sorted { $0.workoutActivityType < $1.workoutActivityType }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 8) {
                    // Filters
                    HStack {
                        Picker("Date Filter", selection: $dateFilter) {
                            ForEach(WorkoutDateFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.cyan)
                        
                        Spacer()
                        
                        Picker("Type Filter", selection: $typeFilter) {
                            ForEach(WorkoutTypeFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.cyan)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Segmented Control
                    Picker("Sort by", selection: $sortType) {
                        ForEach(WorkoutSortType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .colorScheme(.dark)
                    
                    if isLoading && recentWorkouts.isEmpty {
                        Spacer()
                        ProgressView("Fetching workouts...")
                            .foregroundColor(.white)
                        Spacer()
                    } else if recentWorkouts.isEmpty {
                        Spacer()
                        Text("No recent workouts found in Firebase.")
                            .foregroundColor(.secondary)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(filteredAndSortedWorkouts) { workout in
                                    WorkoutCardView(workout: workout)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Recent Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: HomeDashboardView()) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(.cyan)
                    }
                }
            }
            .task {
                await fetchWorkouts()
            }
            .refreshable {
                await fetchWorkouts()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func fetchWorkouts() async {
        guard let userId = authService.currentUser?.uid else { return }
        
        isLoading = true
        do {
            recentWorkouts = try await firestoreService.fetchRecentWorkouts(userId: userId, limit: 50)
        } catch {
            print("Error fetching workouts: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Workout Card View

struct WorkoutCardView: View {
    let workout: WorkoutData
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon Background
            ZStack {
                Circle()
                    .fill(activityColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: activityIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(activityColor)
            }
            
            // Middle: Type and Date
            VStack(alignment: .leading, spacing: 4) {
                Text(activityName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Right: Duration and Energy
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "stopwatch")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(formattedDuration)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                if let dist = workout.totalDistanceMeters, dist > 0, [13, 37, 52].contains(workout.workoutActivityType) {
                    HStack(spacing: 4) {
                        Image(systemName: "ruler")
                            .font(.caption2)
                            .foregroundColor(.green)
                        let km = dist / 1000
                        Text(km >= 1 ? String(format: "%.2f km", km) : "\(Int(dist)) m")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }

                if let cals = workout.totalEnergyBurnedKcal, cals > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                        Text("\(Int(cals)) kcal")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.1))
                .shadow(color: activityColor.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // Simple helper properties
    var formattedDuration: String {
        let mins = Int(workout.durationSeconds) / 60
        let secs = Int(workout.durationSeconds) % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remainMins = mins % 60
            return "\(hrs)h \(remainMins)m"
        }
        return String(format: "%d:%02d", mins, secs)
    }
    
    var activityName: String {
        // Standard HKWorkoutActivityType mappings
        switch workout.workoutActivityType {
        case 13: return "Cycling"
        case 16: return "Elliptical"
        case 20: return "Functional Strength"
        case 35: return "Rowing"
        case 37: return "Outdoor Run"
        case 52: return "Walking"
        case 57: return "Yoga Flow"
        case 82: return "HIIT Session"
        default: return "Workout"
        }
    }
    
    var activityIcon: String {
        switch workout.workoutActivityType {
        case 13: return "bicycle"
        case 16: return "figure.elliptical"
        case 20: return "dumbbell.fill"
        case 35: return "figure.rowing"
        case 37: return "figure.run"
        case 52: return "figure.walk"
        case 57: return "figure.mind.and.body"
        case 82: return "flame.fill"
        default: return "figure.run"
        }
    }
    
    var activityColor: Color {
        switch workout.workoutActivityType {
        case 13: return .green
        case 20: return .orange
        case 37: return .cyan
        case 57: return .purple
        case 82: return .orange
        default: return .cyan
        }
    }
}
