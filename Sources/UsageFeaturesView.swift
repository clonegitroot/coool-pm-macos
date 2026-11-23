import SwiftUI

private struct UsageFeaturesKey: EnvironmentKey {
    static let defaultValue = UsageFeatures.full
}

extension EnvironmentValues {
    var usageFeatures: UsageFeatures {
        get { self[UsageFeaturesKey.self] }
        set { self[UsageFeaturesKey.self] = newValue }
    }
}

struct UsageProfilePicker: View {
    @Binding var features: UsageFeatures
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(UsageProfile.allCases, id: \.self) { profile in
                Button {
                    features = profile.features
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: features == profile.features ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(profile.title)).font(.headline)
                            Text(LocalizedStringKey(profile.detail)).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(features == profile.features ? 0.10 : 0.025),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(features == profile.features ? .isSelected : [])
            }
        }
    }
}

struct UsageFeaturesSettings: View {
    @Binding var features: UsageFeatures
    @State private var choosingProfile = false
    @State private var preview: UsageFeatures?
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            LabeledContent("Usage profile") { Text(LocalizedStringKey(features.profileTitle)) }
            Button("Choose a starting profile…") { choosingProfile = true }
            Text("Adjust the interface to your work. Hidden features retain their saved records and still contribute to totals.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Available features") {
            ForEach(UsageFeature.allCases, id: \.self) { feature in
                Toggle(isOn: Binding(get: { features.enabled(feature) }, set: { features.set(feature, enabled: $0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(feature.title))
                        Text(LocalizedStringKey(feature.detail)).font(.caption).foregroundStyle(.secondary)
                    }
                }.help(LocalizedStringKey(feature.detail))
            }
        }
        .sheet(isPresented: $choosingProfile) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a starting profile").font(.title2.bold())
                UsageProfilePicker(features: Binding(get: { preview ?? features }, set: { preview = $0 }))
                Text("Applying a profile replaces the feature switches below. You can adjust them again at any time.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { choosingProfile = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply profile") { if let preview { features = preview }; choosingProfile = false }
                        .buttonStyle(.borderedProminent).disabled(preview == nil)
                }
            }.padding(24).frame(width: 560).environment(\.locale, locale)
                .onAppear { preview = nil }
        }
    }
}

struct ProjectFeaturesView: View {
    @Binding var overrides: UsageFeatureOverrides?
    let defaults: UsageFeatures
    @State private var showingFeatures = false

    var body: some View {
        HStack {
            Button {
                showingFeatures.toggle()
            } label: {
                Label("Features for this project", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingFeatures, arrowEdge: .bottom) {
                featureControls
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var featureControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features for this project").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Text("Use extra tools on this project or simplify its interface. Global preferences apply wherever you select Default.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach([UsageFeature.teamPlanning, .costControlling, .advancedBilling], id: \.self) { feature in
                    Picker(selection: Binding(get: { overrides?.value(feature) }, set: { value in
                        var updated = overrides ?? UsageFeatureOverrides()
                        updated.set(feature, enabled: value)
                        overrides = updated.isEmpty ? nil : updated
                    })) {
                        Text(defaults.enabled(feature) ? "Default · On" : "Default · Off").tag(Bool?.none)
                        Text("On").tag(Optional(true))
                        Text("Off").tag(Optional(false))
                    } label: { Text(LocalizedStringKey(feature.title)) }
                    .pickerStyle(.menu)
                    .help(LocalizedStringKey(feature.detail))
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
