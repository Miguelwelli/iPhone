import Foundation

/// Coarse phase mirror of `TransferJob.State`, used by the UI to render the right progress
/// description ("Baixando" vs "Transferindo") without inspecting the job's raw state everywhere.
public enum TransferPhase: String, Sendable {
    case idle
    case preparing
    case downloading
    case connecting
    case transferring
    case paused
    case completed
    case failed
    case cancelled

    public init(state: TransferJob.State) {
        switch state {
        case .queued: self = .idle
        case .preparing: self = .preparing
        case .downloading: self = .downloading
        case .connecting: self = .connecting
        case .transferring: self = .transferring
        case .paused: self = .paused
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }

    public var title: String {
        switch self {
        case .idle: return "AGUARDANDO"
        case .preparing: return "PREPARANDO"
        case .downloading: return "BAIXANDO"
        case .connecting: return "CONECTANDO"
        case .transferring: return "TRANSFERINDO"
        case .paused: return "PAUSADA"
        case .completed: return "CONCLUÍDO"
        case .failed: return "ERRO"
        case .cancelled: return "CANCELADA"
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .downloading, .connecting, .transferring: return true
        default: return false
        }
    }
}

/// Small Math helpers kept out of the views to stay testable.
public enum ProgressMath {
    /// Fraction of the overall job expressed as 0...1 for a job that downloads then uploads.
    /// Download and upload each contribute half, which keeps the big ring meaningful in both phases.
    public static func overall(downloaded: Int64, uploaded: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        let downloadPortion = min(Double(downloaded) / Double(total), 1) * 0.5
        let uploadPortion = min(Double(uploaded) / Double(total), 1) * 0.5
        return min(downloadPortion + uploadPortion, 1)
    }

    /// Exponential moving average, used to smooth the speed meter.
    public static func smoothed(previous: Double, sample: Double, factor: Double = 0.3) -> Double {
        guard previous > 0 else { return sample }
        return previous * (1 - factor) + sample * factor
    }
}
