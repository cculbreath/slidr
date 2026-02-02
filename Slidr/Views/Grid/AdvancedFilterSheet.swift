import SwiftUI

struct AdvancedFilterSheet: View {
    @Bindable var viewModel: GridViewModel
    @Environment(PlaylistService.self) private var playlistService
    @Environment(\.dismiss) private var dismiss

    @State private var filter: AdvancedFilter
    @State private var showSavePlaylist = false
    @State private var playlistName = ""

    init(viewModel: GridViewModel) {
        self.viewModel = viewModel
        _filter = State(initialValue: viewModel.advancedFilter ?? AdvancedFilter())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(width: 560, height: 440)
        .sheet(isPresented: $showSavePlaylist) {
            savePlaylistSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Advanced Filter")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Search field
                HStack {
                    Text("Search:")
                        .frame(width: 60, alignment: .trailing)
                    TextField("Search text...", text: $filter.searchText)
                        .textFieldStyle(.roundedBorder)
                }

                // Combine mode
                HStack {
                    Text("Match")
                    Picker("", selection: $filter.combineMode) {
                        Text("All").tag(CombineMode.all)
                        Text("Any").tag(CombineMode.any)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Text("of the following rules:")
                }

                // Rules
                ForEach(Array(filter.rules.enumerated()), id: \.element.id) { index, rule in
                    filterRuleRow(index: index, rule: rule)
                }

                // Add rule button
                HStack {
                    Spacer()
                    Button {
                        filter.rules.append(FilterRule())
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle")
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Rule Row

    private func filterRuleRow(index: Int, rule: FilterRule) -> some View {
        HStack(spacing: 8) {
            // Field picker
            Picker("Field", selection: fieldBinding(at: index)) {
                ForEach(FilterField.allCases, id: \.self) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            // Condition picker (if applicable)
            let conditions = filter.rules[index].field.availableConditions
            if !conditions.isEmpty {
                Picker("Condition", selection: conditionBinding(at: index)) {
                    ForEach(conditions, id: \.self) { condition in
                        Text(condition.rawValue).tag(condition)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            // Value input
            valueInput(at: index)

            // Remove button
            Button {
                filter.rules.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Value Input

    @ViewBuilder
    private func valueInput(at index: Int) -> some View {
        let field = filter.rules[index].field
        switch field {
        case .tag:
            TextField("Tag", text: stringValueBinding(at: index))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 100)

        case .source:
            TextField("Source", text: stringValueBinding(at: index))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 100)

        case .mediaType:
            Picker("", selection: mediaTypeValueBinding(at: index)) {
                ForEach(MediaType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 100)

        case .productionType:
            Picker("", selection: productionTypeValueBinding(at: index)) {
                ForEach(ProductionType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 120)

        case .duration:
            HStack {
                TextField("Seconds", value: durationValueBinding(at: index), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("sec")
                    .foregroundStyle(.secondary)
            }

        case .rating:
            Picker("", selection: ratingValueBinding(at: index)) {
                ForEach(1...5, id: \.self) { stars in
                    Text(String(repeating: "\u{2605}", count: stars)).tag(stars)
                }
            }
            .labelsHidden()
            .frame(width: 100)

        case .hasTranscript, .hasCaption:
            Text("Yes")
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Save as Smart Playlist\u{2026}") {
                playlistName = "Filtered Playlist"
                showSavePlaylist = true
            }
            .disabled(filter.isEmpty)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply") {
                if filter.isEmpty {
                    viewModel.advancedFilter = nil
                } else {
                    viewModel.advancedFilter = filter
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Save Playlist Sheet

    private var savePlaylistSheet: some View {
        VStack(spacing: 16) {
            Text("Save as Smart Playlist")
                .font(.headline)

            TextField("Playlist name", text: $playlistName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    showSavePlaylist = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let playlist = playlistService.createPlaylist(name: playlistName, type: .smart)
                    filter.applyToPlaylist(playlist)
                    playlistService.updatePlaylist(playlist)
                    showSavePlaylist = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    // MARK: - Bindings

    private func fieldBinding(at index: Int) -> Binding<FilterField> {
        Binding(
            get: { filter.rules[index].field },
            set: { newField in
                let oldField = filter.rules[index].field
                filter.rules[index].field = newField
                if oldField != newField {
                    filter.rules[index].condition = newField.availableConditions.first ?? .contains
                    filter.rules[index].value = newField.defaultValue
                }
            }
        )
    }

    private func conditionBinding(at index: Int) -> Binding<FilterCondition> {
        Binding(
            get: { filter.rules[index].condition },
            set: { filter.rules[index].condition = $0 }
        )
    }

    private func stringValueBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                if case .string(let value) = filter.rules[index].value { return value }
                return ""
            },
            set: { filter.rules[index].value = .string($0) }
        )
    }

    private func mediaTypeValueBinding(at index: Int) -> Binding<MediaType> {
        Binding(
            get: {
                if case .mediaType(let type) = filter.rules[index].value { return type }
                return .video
            },
            set: { filter.rules[index].value = .mediaType($0) }
        )
    }

    private func productionTypeValueBinding(at index: Int) -> Binding<ProductionType> {
        Binding(
            get: {
                if case .productionType(let type) = filter.rules[index].value { return type }
                return .professional
            },
            set: { filter.rules[index].value = .productionType($0) }
        )
    }

    private func durationValueBinding(at index: Int) -> Binding<TimeInterval> {
        Binding(
            get: {
                if case .duration(let seconds) = filter.rules[index].value { return seconds }
                return 30
            },
            set: { filter.rules[index].value = .duration($0) }
        )
    }

    private func ratingValueBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: {
                if case .rating(let rating) = filter.rules[index].value { return rating }
                return 3
            },
            set: { filter.rules[index].value = .rating($0) }
        )
    }
}
