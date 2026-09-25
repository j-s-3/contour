import Foundation

/// A Jira ticket referenced by the PR, used to ground the "Problem to be solved" ELI5
/// statement in the actual ticket description rather than an inference from the diff.
struct JiraTicketInfo: Codable, Hashable, Sendable {
    var key: String
    var summary: String
    var description: String
    var url: String
}
