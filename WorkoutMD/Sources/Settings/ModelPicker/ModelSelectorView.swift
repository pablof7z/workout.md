import SwiftUI

/// Ported from RockingLife's `OpenRouterModelSelectorView.swift` (win-the-day-app) — a real, fetched,
/// searchable model navigator, replacing `ModelTierSettingsView`'s old hardcoded suggestion lists for
/// BOTH providers (`source` picks which catalog gets fetched — see `ModelCatalogSource`). This is a
/// `List`, not its own `NavigationStack` — the caller (`ModelTierSettingsView`) presents it inside
/// `.sheet { NavigationStack { ModelSelectorView(...) } }`.
///
/// Deliberately capability/date-free: no badges, no capability filter, no "newest" sort, no dates in
/// the detail sheet — rows are logo + name + id + pricing + context, detail adds maker + pricing +
/// limits + description. Nothing else.
struct ModelSelectorView: View {
    var source: ModelCatalogSource
    @Binding var selectedModelID: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = ModelSelectorViewModel()
    @State private var searchText = ""
    @State private var sort: ModelSort = .recommended
    @State private var providerFilter: String?
    @State private var manualModelID = ""

    var body: some View {
        List {
            currentSection
            controlsSection
            loadingSection
            modelsSection
            customSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search models, providers, ids")
        .refreshable { await viewModel.reload(source: source) }
        .task(id: source) {
            if manualModelID.isEmpty { manualModelID = selectedModelID }
            await viewModel.loadIfNeeded(source: source)
        }
        .navigationDestination(for: ModelCatalogOption.self) { model in
            ModelSelectorDetailView(
                model: model,
                selectedModelID: selectedModelID
            ) {
                selectedModelID = model.id
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                providerMenu
                Button {
                    Task { await viewModel.reload(source: source) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh models")
            }
        }
    }

    private var currentSection: some View {
        Section("Current") {
            if let current = viewModel.models.first(where: { $0.id == selectedModelID }) {
                NavigationLink(value: current) {
                    ModelSelectorRow(model: current, isSelected: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedModelID)
                        .font(.subheadline.monospaced())
                    Text("Custom model ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var controlsSection: some View {
        Section {
            Picker("Sort", selection: $sort) {
                ForEach(ModelSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }

            if let providerFilter,
               let providerName = providerName(for: providerFilter) {
                Button {
                    self.providerFilter = nil
                } label: {
                    Label("Provider: \(providerName)", systemImage: "xmark.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if viewModel.isLoading && viewModel.models.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading models")
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let error = viewModel.errorMessage {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    Button {
                        Task { await viewModel.reload(source: source) }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var modelsSection: some View {
        Section("\(visibleModels.count) Models") {
            if visibleModels.isEmpty && !viewModel.isLoading {
                Text("No models match this search")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleModels) { model in
                    NavigationLink(value: model) {
                        ModelSelectorRow(model: model, isSelected: model.id == selectedModelID)
                    }
                }
            }
        }
    }

    private var customSection: some View {
        Section("Custom model ID") {
            TextField("provider/model", text: $manualModelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

            Button {
                let trimmed = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                selectedModelID = trimmed
                dismiss()
            } label: {
                Label("Use custom ID", systemImage: "checkmark.circle")
            }
            .disabled(manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var providerMenu: some View {
        Menu {
            Button {
                providerFilter = nil
            } label: {
                Label("All providers", systemImage: providerFilter == nil ? "checkmark" : "building.2")
            }

            ForEach(providerSummaries) { provider in
                Button {
                    providerFilter = provider.id
                } label: {
                    if providerFilter == provider.id {
                        Label("\(provider.name) (\(provider.count))", systemImage: "checkmark")
                    } else {
                        Text("\(provider.name) (\(provider.count))")
                    }
                }
            }
        } label: {
            Image(systemName: "building.2")
        }
        .accessibilityLabel("Filter by provider")
    }

    private var visibleModels: [ModelCatalogOption] {
        var models = viewModel.models

        if let providerFilter {
            models = models.filter { $0.providerID == providerFilter }
        }

        let terms = searchText
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !terms.isEmpty {
            models = models.filter { model in
                terms.allSatisfy { model.searchText.contains($0) }
            }
        }

        switch sort {
        case .recommended:
            return models
        case .price:
            return models.sorted { lhs, rhs in
                lhs.priceSortValue < rhs.priceSortValue
            }
        case .context:
            return models.sorted { ($0.contextLength ?? 0) > ($1.contextLength ?? 0) }
        case .name:
            return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var providerSummaries: [ModelSelectorProviderSummary] {
        let grouped = Dictionary(grouping: viewModel.models, by: \.providerID)
        return grouped.map { id, models in
            ModelSelectorProviderSummary(
                id: id,
                name: models.first?.providerName ?? id,
                count: models.count
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        .prefix(24)
        .map { $0 }
    }

    private func providerName(for id: String) -> String? {
        viewModel.models.first { $0.providerID == id }?.providerName
    }
}

@MainActor
private final class ModelSelectorViewModel: ObservableObject {
    @Published private(set) var models: [ModelCatalogOption] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = ModelCatalogService()

    func loadIfNeeded(source: ModelCatalogSource) async {
        guard models.isEmpty else { return }
        await reload(source: source)
    }

    func reload(source: ModelCatalogSource) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            models = try await service.fetchModels(source: source)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ModelSelectorRow: View {
    var model: ModelCatalogOption
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderLogoView(providerID: model.providerID, providerName: model.providerName)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .imageScale(.small)
                    }
                }

                Text(model.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(model.compactPricing)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                Text("per 1M")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(modelSelectorTokenLimit(model.contextLength))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct ModelSelectorDetailView: View {
    var model: ModelCatalogOption
    var selectedModelID: String
    var onSelect: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ProviderLogoView(
                        providerID: model.providerID,
                        providerName: model.providerName,
                        size: 52
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.name)
                            .font(.title3.weight(.semibold))
                        Text(model.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(model.providerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: onSelect) {
                    Label(selectedModelID == model.id ? "Selected" : "Use Model", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(selectedModelID == model.id)

                detailGroup("Pricing") {
                    ModelSelectorDetailLine("Prompt", pricingDetail(model.promptCostPerMillion))
                    ModelSelectorDetailLine("Completion", pricingDetail(model.completionCostPerMillion))
                    if model.cacheReadCostPerMillion != nil {
                        ModelSelectorDetailLine("Cache read", pricingDetail(model.cacheReadCostPerMillion))
                    }
                    if model.cacheWriteCostPerMillion != nil {
                        ModelSelectorDetailLine("Cache write", pricingDetail(model.cacheWriteCostPerMillion))
                    }
                }

                detailGroup("Limits") {
                    ModelSelectorDetailLine("Context", modelSelectorTokenLimit(model.contextLength))
                    ModelSelectorDetailLine("Output", modelSelectorTokenLimit(model.outputLimit))
                }

                if let description = model.modelDescription, !description.isEmpty {
                    detailGroup("Description") {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pricingDetail(_ value: Double?) -> String {
        guard let value else { return "Variable" }
        return "\(ModelCatalogOption.perToken(value)) / \(ModelCatalogOption.money(value)) per 1M"
    }
}

private struct ModelSelectorDetailLine: View {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private enum ModelSort: String, CaseIterable, Identifiable {
    case recommended
    case price
    case context
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Recommended"
        case .price: return "Lowest price"
        case .context: return "Largest context"
        case .name: return "Name"
        }
    }
}

private struct ModelSelectorProviderSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var count: Int
}

private extension ModelCatalogOption {
    var priceSortValue: Double {
        guard let promptCostPerMillion, let completionCostPerMillion else {
            return .greatestFiniteMagnitude
        }
        return promptCostPerMillion + completionCostPerMillion
    }
}

private func modelSelectorTokenLimit(_ value: Int?) -> String {
    guard let value else { return "Unknown" }
    if value >= 1_000_000 {
        let millions = Double(value) / 1_000_000
        return String(format: "%.1fM tokens", millions)
    }
    if value >= 1_000 {
        return "\(value / 1_000)K tokens"
    }
    return "\(value) tokens"
}
