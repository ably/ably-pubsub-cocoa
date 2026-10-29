import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

struct TaskBoardView: View {
    @ObservedObject var viewModel: TaskBoardViewModel
    let clientTitle: String

    @State private var taskInput = ""

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Client identifier
                        Text(clientTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)

                        // Card container
                        VStack(spacing: 2) {
                            // Header
                            Text("Realtime Task Board")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 8)

                            // Input section
                            HStack(spacing: 12) {
                                TextField("Enter task", text: $taskInput)
                                #if !os(tvOS)
                                    .textFieldStyle(.roundedBorder)
                                #endif
                                    .onSubmit {
                                        addTask()
                                    }

                                Button("Add") {
                                    addTask()
                                }
                                .buttonStyle(.borderedProminent)
                                #if !os(tvOS)
                                    .controlSize(.small)
                                #endif
                                    .disabled(taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Remove all") {
                                    viewModel.removeAllTasks()
                                }
                                .buttonStyle(.bordered)
                                #if !os(tvOS)
                                    .controlSize(.small)
                                #endif
                            }
                            .padding(.bottom, 12)

                            // Tasks list
                            VStack(spacing: 0) {
                                if viewModel.tasks.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "checklist")
                                            .font(.system(size: 32))
                                            .foregroundColor(.secondary)
                                        Text("No tasks yet")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                        Text("Add your first task above")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 20)
                                } else {
                                    ForEach(Array(viewModel.tasks.keys.enumerated()), id: \.offset) { index, taskId in
                                        TaskRow(
                                            id: taskId,
                                            title: viewModel.tasks[taskId] ?? "",
                                            onEdit: { newTitle in
                                                viewModel.editTask(id: taskId, newTitle: newTitle)
                                            },
                                            onRemove: {
                                                viewModel.removeTask(id: taskId)
                                            },
                                        )
                                        if index < viewModel.tasks.keys.count - 1 {
                                            Divider()
                                                .background(SwiftUI.Color.gray.opacity(0.3))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                        .frame(maxWidth: 320)

                        // Error message
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding()
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thickMaterial)
            }
        }
    }

    private func addTask() {
        let title = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        viewModel.addTask(title)
        taskInput = ""
    }
}

struct TaskRow: View {
    let id: String
    let title: String
    let onEdit: (String) -> Void
    let onRemove: () -> Void

    @State private var showingEditAlert = false
    @State private var editingTitle = ""

    var body: some View {
        HStack(spacing: 16) {
            // Task title
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Edit button
            Button("Edit") {
                editingTitle = title
                showingEditAlert = true
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.blue)

            // Remove button
            Button("Remove") {
                onRemove()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .alert("Edit Task", isPresented: $showingEditAlert) {
            TextField("Task title", text: $editingTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmedTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTitle.isEmpty {
                    onEdit(trimmedTitle)
                }
            }
            .disabled(editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new title for this task")
        }
    }
}
