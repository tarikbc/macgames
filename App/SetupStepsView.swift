import MacGamesCore
import SwiftUI

/// The setup stages as a checklist that fills in while setup runs.
struct SetupStepsView: View {
    let game: GameModel
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Setup").font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(Array(SetupStep.allCases.enumerated()), id: \.element) { index, step in
                    StepRow(step: step, status: status(of: step), accent: game.profile.accent)
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared || reduceMotion ? 0 : -12)
                        .animation(.spring(duration: 0.5, bounce: 0.2).delay(Double(index) * 0.05), value: appeared)
                }
            }
        }
        .onAppear { appeared = true }
    }

    func status(of step: SetupStep) -> StepRow.Status {
        if game.finishedSteps.contains(step) { return .done }
        if game.step == step { return .active }
        if game.state == .needsSteam && step < .steam { return .done }
        return .pending
    }
}

struct StepRow: View {
    enum Status { case pending, active, done }
    let step: SetupStep
    let status: Status
    let accent: Color

    var body: some View {
        HStack(spacing: Space.m) {
            ZStack {
                switch status {
                case .pending:
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                case .active:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(accent)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: 18, height: 18)
            Text(step.title)
                .font(.system(size: 13, weight: status == .active ? .semibold : .regular))
                .foregroundStyle(status == .pending ? .secondary : .primary)
        }
        .animation(.spring(duration: 0.45, bounce: 0.45), value: status)
    }
}
