//
//  PreTripTasksView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/26/26.
//

import SwiftUI
import SwiftData

struct PreTripTasksView: View {
    let trip: Trip
    let vm: TripsViewModel

    @Environment(\.modelContext) private var context
    @State private var newTaskTitle: String = ""

    private var tasks: [PreTripTask] {
        (trip.preTripTasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            ForEach(tasks) { task in
                HStack(spacing: 12) {
                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isComplete ? ThemeTokens.successGreen : ThemeTokens.textMuted)
                        .font(.system(size: 20))
                        .onTapGesture { vm.toggleTask(task, context: context) }

                    Text(task.title)
                        .strikethrough(task.isComplete, color: ThemeTokens.textMuted)
                        .foregroundStyle(task.isComplete ? ThemeTokens.textMuted : ThemeTokens.textPrimary)
                        .animation(.spring(response: 0.25), value: task.isComplete)
                }
            }
            .onDelete { indexSet in
                indexSet.map { tasks[$0] }.forEach { vm.deleteTask($0, context: context) }
            }

            // Inline add row
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(ThemeTokens.accent)
                    .font(.system(size: 20))
                TextField("Add task...", text: $newTaskTitle)
                    .submitLabel(.done)
                    .onSubmit {
                        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        vm.addTask(to: trip, title: newTaskTitle, context: context)
                        newTaskTitle = ""
                    }
            }
        }
        .navigationTitle("Pre-Trip Checklist")
        .navigationBarTitleDisplayMode(.inline)
    }
}
