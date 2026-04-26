import SwiftUI

struct WorkoutListView: View {
    @EnvironmentObject var authService: AuthService
    // We are cheating a bit here by holding a local state, 
    // ideally it would come from a view model, but keeping it simple as requested.
    @State private var recentWorkouts: [WorkoutData] = []
    @State private var isLoading = false
    
    // In a real app this would be injected
    private let firestoreService = FirestoreService()
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Fetching workouts...")
            } else if recentWorkouts.isEmpty {
                Text("No recent workouts found in Firebase.")
                    .foregroundColor(.secondary)
            } else {
                List(recentWorkouts) { workout in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.sourceName)
                            .font(.headline)
                        
                        Text("Duration: \(Int(workout.durationSeconds / 60)) min")
                            .font(.subheadline)
                        
                        if let cals = workout.totalEnergyBurnedKcal {
                            Text("Calories: \(Int(cals)) kcal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Date: \(workout.startDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Recent Workouts")
        .task {
            await fetchWorkouts()
        }
        .refreshable {
            await fetchWorkouts()
        }
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
