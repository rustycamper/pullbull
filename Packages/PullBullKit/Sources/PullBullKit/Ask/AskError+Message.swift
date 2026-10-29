extension AskError {
    /// The one line shown in place of an answer.
    public var message: String {
        switch self {
        case .offline: "No network."
        case .unauthorized: "Anthropic rejected the key. Check it in Settings → Ask AI."
        case .rateLimited: "Rate limited by Anthropic. Try again shortly."
        case .timeout: "No answer in 20 s."
        case .refusal: "The model declined to answer."
        case .truncated: "Ask AI failed (answer cut off)."
        case .noAnswer: "Ask AI failed (no answer)."
        case .server(let status): status > 0 ? "Ask AI failed (HTTP \(status))." : "Ask AI failed (unexpected error)."
        }
    }
}
