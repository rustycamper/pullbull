import Foundation

/// A transport failure of a comment post that `AuthorizedSend` would fold into `APIError`. A timeout or a
/// dropped connection can't tell "never sent" from "may have landed", so the code is kept for `classify`.
public struct CommentTransportError: Error, Equatable, Sendable {
    public let code: URLError.Code

    public init(code: URLError.Code) { self.code = code }
}

/// How a failed comment post is shown: `refused` when the comment certainly wasn't posted (the reason
/// is the message), `unknown` when it may have been.
public enum CommentFailure: Equatable, Sendable {
    case refused(String)
    case unknown

    /// The codes that mean the request never left: no connectivity, no route, no DNS, no connection.
    private static let neverSent: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
    ]

    public static func classify(_ error: any Error) -> CommentFailure {
        switch error {
        case let error as CommentTransportError:
            return neverSent.contains(error.code)
                ? .refused(RefreshError(APIError.network("")).message) : .unknown
        case APIError.writeRefused(let message):
            return .refused(message)
        case APIError.unauthorized, APIError.ssoRequired, APIError.rateLimited, APIError.forbidden,
             APIError.insufficientScopes:
            return .refused(RefreshError(error).message)
        default:
            return .unknown
        }
    }
}
