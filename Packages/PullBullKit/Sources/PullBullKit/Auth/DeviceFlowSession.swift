import Foundation

public enum DeviceFlowEvent: Sendable, Equatable {
    case code(userCode: String, verificationURL: URL, expiresAt: Date)
    /// Polling works again after `.unreachable`.
    case waiting
    case unreachable
    case granted(TokenGrant)
    case expired, denied, tooManyCodes, misconfigured
}

/// Drives one device-flow sign-in: requests a code, then polls at GitHub's pace until the user
/// answers, the code expires or the consumer stops listening.
public struct DeviceFlowSession: Sendable {
    private static let slowDownStep = 5
    private static let pollBackoffCap = 60
    private static let codeRetryWaits = [5, 10, 20, 30]

    private let client: DeviceFlowClient
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date

    public init(
        client: DeviceFlowClient, clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.clock = clock
        self.now = now
    }

    /// One task per stream; ending the stream or cancelling its consumer stops all requests.
    public func run() -> AsyncStream<DeviceFlowEvent> {
        AsyncStream { continuation in
            let task = Task {
                await drive(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func drive(_ out: AsyncStream<DeviceFlowEvent>.Continuation) async {
        guard let code = await requestCode(out) else { return }
        out.yield(
            .code(
                userCode: code.userCode, verificationURL: code.verificationURL,
                expiresAt: now().addingTimeInterval(TimeInterval(code.expiresIn.components.seconds))))

        var interval = code.interval
        var wait = interval
        var unreachable = false
        // Counted from the sleeps themselves so expiry works with any clock.
        var elapsed = Duration.zero
        while true {
            do { try await clock.sleep(for: .seconds(wait)) } catch { return }
            elapsed += .seconds(wait)
            if elapsed >= code.expiresIn {
                out.yield(.expired)
                return
            }
            do {
                let result = try await client.poll(code)
                if unreachable {
                    unreachable = false
                    out.yield(.waiting)
                }
                switch result {
                case .pending: break
                case .slowDown(let returned): interval = max(interval + Self.slowDownStep, returned)
                case .granted(let grant):
                    out.yield(.granted(grant))
                    return
                }
                wait = interval
            } catch DeviceFlowError.expired {
                out.yield(.expired)
                return
            } catch DeviceFlowError.denied {
                out.yield(.denied)
                return
            } catch DeviceFlowError.tooManyCodes {
                out.yield(.tooManyCodes)
                return
            } catch DeviceFlowError.misconfigured, DeviceFlowError.badRefreshToken {
                out.yield(.misconfigured)
                return
            } catch DeviceFlowError.network, DeviceFlowError.unexpected {
                if unreachable {
                    wait = min(wait * 2, Self.pollBackoffCap)
                } else {
                    unreachable = true
                    out.yield(.unreachable)
                    wait = min(interval * 2, Self.pollBackoffCap)
                }
            } catch {
                // Anything else is a bug, not a network blip: end with a final event, not silence.
                if !Task.isCancelled { out.yield(.misconfigured) }
                return
            }
        }
    }

    /// Retries transient failures (network, 5xx); a permanent one ends with `.misconfigured`.
    /// Returns nil once the stream has ended or been cancelled.
    private func requestCode(_ out: AsyncStream<DeviceFlowEvent>.Continuation) async -> DeviceCode? {
        var attempt = 0
        while true {
            do {
                return try await client.requestCode()
            } catch DeviceFlowError.tooManyCodes {
                out.yield(.tooManyCodes)
                return nil
            } catch DeviceFlowError.network, DeviceFlowError.unexpected {
                if attempt == 0 { out.yield(.unreachable) }
                let wait = Self.codeRetryWaits[min(attempt, Self.codeRetryWaits.count - 1)]
                attempt += 1
                do { try await clock.sleep(for: .seconds(wait)) } catch { return nil }
            } catch is CancellationError {
                return nil
            } catch {
                out.yield(.misconfigured)
                return nil
            }
        }
    }
}
