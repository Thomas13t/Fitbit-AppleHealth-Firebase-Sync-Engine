import SwiftUI

struct DebugLogView: View {
    @EnvironmentObject var syncManager: SyncManager
    
    var body: some View {
        List {
            if syncManager.syncLogs.isEmpty {
                Text("No logs available yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(syncManager.syncLogs, id: \.self) { log in
                    Text(log)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
        .navigationTitle("Sync Logs")
    }
}
