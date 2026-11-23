import SwiftUI

struct ProjectOverview: View {
    @Environment(\.usageFeatures) private var features
    let estimate: Estimate
    let showEstimate: () -> Void
    let showControlling: () -> Void
    let showDocuments: () -> Void
    let showBilling: () -> Void
    var assignProjectNumber: (() -> Void)?

    var body: some View {
        let costs = estimate.costs(for: nil)
        let balance = estimate.invoiceOutstandingGross
        VStack(alignment: .leading, spacing: 22) {
            if let number = estimate.projectNumber {
                LabeledContent("Project number", value: number).font(.headline)
            } else if let assignProjectNumber {
                Button("Assign project number", systemImage: "number", action: assignProjectNumber)
                    .buttonStyle(.bordered)
                    .help("Assign a permanent number using the current client.")
            }
            HStack(alignment: .top, spacing: 12) {
                stat(estimate.approvedNet == nil ? "Estimated fee" : "Agreed fee", estimate.currentBillableNet,
                     icon: "doc.text", action: showEstimate)
                if features.costControlling {
                    stat("Forecast DB2", costs.forecast.db2, icon: "chart.bar.xaxis", action: showControlling)
                }
                stat(balance < 0 ? "Client credit" : "Outstanding invoices", abs(balance),
                     icon: "eurosign.circle", action: showBilling)
            }
            if !features.costControlling {
                HStack(alignment: .top, spacing: 12) {
                    stat("Income", estimate.invoiceNetTotal, icon: "arrow.down.circle", action: showBilling)
                    stat("Expenses", costs.actual.external + costs.actual.internalCost,
                         icon: "arrow.up.circle", action: showDocuments)
                    stat("Profit", estimate.invoiceNetTotal - costs.actual.external - costs.actual.internalCost,
                         icon: "chart.bar", action: showBilling)
                }
                Text("Net invoiced income less recorded external and internal costs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { nextAction; Spacer(minLength: 20); nextButton }
                VStack(alignment: .leading, spacing: 12) { nextAction; nextButton }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: Decimal, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(label, systemImage: icon)
                        .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                }
                Text(euros(value))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(value < 0 ? Color.red : Color.primary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.16)) }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var nextAction: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next action").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(next.0).font(.headline)
        }
    }

    private var nextButton: some View {
        Button(action: next.2) {
            Label(next.1, systemImage: "arrow.right")
        }.buttonStyle(.borderedProminent)
    }

    private var next: (LocalizedStringKey, LocalizedStringKey, () -> Void) {
        switch estimate.currentStatus {
        case .inquiry: ("Build the estimate", "Open estimate", showEstimate)
        case .offered: ("Check the proposal and record acceptance", "Open documents", showDocuments)
        case .accepted, .active:
            features.costControlling
                ? ("Review actual costs and the forecast", "Open controlling", showControlling)
                : ("Review invoices and payments", "Open billing", showBilling)
        case .invoiced: ("Review invoices and payments", "Open billing", showBilling)
        case .closed: ("Review the project archive", "Open documents", showDocuments)
        }
    }
}
