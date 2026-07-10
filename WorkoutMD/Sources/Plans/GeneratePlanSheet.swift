import SwiftUI
import SwiftData

/// "Coach-generated from a goal" plan creation: the user states a goal in plain language, the coach
/// (via `CoachController.generatePlan`) proposes a structured plan, which is inserted (not yet
/// active — same as any other newly created plan) on success.
struct GeneratePlanSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachController.self) private var coachController
    @Environment(AppSettings.self) private var appSettings

    @State private var goalText: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("e.g. Upper body, 45 min, hypertrophy", text: $goalText, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            HStack {
                                ProgressView()
                                Text("Asking the coach…")
                            }
                        } else {
                            Text("Generate Plan")
                        }
                    }
                    .disabled(goalText.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                } footer: {
                    Text("Target session length comes from Settings (currently \(appSettings.sessionLengthMinutes) min).")
                }
            }
            .navigationTitle("Generate from Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        coachController.generatePlan(goalPrompt: goalText, sessionLengthMinutes: appSettings.sessionLengthMinutes) { result in
            isGenerating = false
            switch result {
            case .success(let plan):
                modelContext.insert(plan)
                try? modelContext.save()
                dismiss()
            case .failure(let error):
                errorMessage = error.userMessage
            }
        }
    }
}
