import SwiftUI

enum WorkoutSortType: String, CaseIterable {
    case date = "Date"
    case type = "Type"
}

struct WorkoutListView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var syncManager: SyncManager
    
    @State private var recentWorkouts: [WorkoutData] = []
    @State private var isLoading = false
    @State private var sortType: WorkoutSortType = .date
    
    private let firestoreService = FirestoreService()
    
    var sortedWorkouts: [WorkoutData] {
        switch sortType {
        case .date:
            return recentWorkouts.sorted { $0.startDate > $1.startDate }
        case .type:
            return recentWorkouts.sorted { $0.workoutActivityType < $1.workoutActivityType }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
                
                VStack {
                    // Segmented Control
                    Picker("Sort by", selection: $sortType) {
                        ForEach(WorkoutSortType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
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
                                ForEach(sortedWorkouts) { workout in
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
