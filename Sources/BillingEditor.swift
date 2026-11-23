import SwiftUI

struct BillingEditor: View {
    @Environment(\.usageFeatures) private var features
    @State var schedule: BillingSchedule
    let net: Decimal
    let locked: Bool
    let defaultDays: Int
    let save: (BillingSchedule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project payment terms").font(.title2.bold())
            Toggle("Set a project payment deadline (Zahlungsziel)", isOn: Binding(get: { schedule.days != nil }, set: { schedule.days = $0 ? defaultDays : nil })).disabled(locked)
                .help("Override the client’s default payment deadline for this project.")
            if schedule.days != nil {
                TextField("Days after invoice date", value: Binding(get: { schedule.days ?? defaultDays }, set: { schedule.days = $0 }), format: .number).disabled(locked)
            } else { Text("Uses the client’s payment terms.").foregroundStyle(.secondary) }
            if features.advancedBilling || !schedule.stages.isEmpty {
                Divider()
                Text("Billing milestones").font(.headline)
                if locked { Text("The first instalment export saved the schedule and fee basis for this billing series.").font(.callout) }
                HStack {
                    Button("Single invoice") { schedule.stages = [] }
                    Button("50 / 50") { setPreset([50,50]) }
                    Button("25 / 25 / 50") { setPreset([25,25,50]) }
                }.disabled(locked)
                ScrollView {
                    VStack {
                        ForEach($schedule.stages) { $stage in
                            HStack {
                                TextField("Milestone", text: $stage.name)
                                Picker("Calculation", selection: Binding(get: { stage.fixedAmount != nil }, set: { fixed in
                                    stage.fixedAmount = fixed ? cents(net * stage.percent / 100) : nil
                                    if !fixed && stage.percent == 0 { stage.percent = 1 }
                                })) {
                                    Text("%").tag(false)
                                    Text("EUR").tag(true)
                                }.labelsHidden().frame(width: 66)
                                if stage.fixedAmount != nil {
                                    TextField("Fixed net amount", value: Binding(get: { stage.fixedAmount ?? 0 }, set: { stage.fixedAmount = $0 }), format: .number)
                                        .frame(width: 82)
                                } else {
                                    TextField("Percentage", value: $stage.percent, format: .number).frame(width: 82)
                                }
                                Text((schedule.amounts(net: net)[stage.id] ?? 0).formatted(.currency(code: "EUR"))).frame(width: 100, alignment: .trailing)
                                Button("Remove", systemImage: "minus.circle") { schedule.stages.removeAll { $0.id == stage.id } }.labelStyle(.iconOnly)
                            }
                        }
                    }
                }.frame(maxHeight: 180).disabled(locked)
                Button("Add milestone", systemImage: "plus") { schedule.stages.append(BillingMilestone(percent: 0, name: "")) }.disabled(locked)
                if schedule.stages.contains(where: { $0.fixedAmount != nil }) {
                    Text("Fixed amounts are net. With a mixed schedule, percentages apply to the balance after the fixed amounts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !schedule.valid(net: net) {
                    Text("Use positive named instalments that add up to the project fee. If using percentages, enter shares that total 100%.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save(schedule); dismiss() }.keyboardShortcut(.defaultAction).disabled(!schedule.valid(net: net))
            }
        }.padding(22).frame(width: 520)
    }
    private func setPreset(_ shares: [Decimal]) {
        let names = shares.count == 2 ? ["Project start","Delivery"] : ["Project start","Mid-project","Delivery"]
        schedule.stages = zip(shares,names).map { BillingMilestone(percent: $0, name: $1) }
    }
}
