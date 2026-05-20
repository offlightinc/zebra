import Foundation

enum EmailThreadGmailURL {
    static func build(accountEmail: String?, providerThreadId: String?) -> URL? {
        guard let email = accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty,
              let tid = providerThreadId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tid.isEmpty else {
            return nil
        }
        var queryAllowed = CharacterSet.urlQueryAllowed
        queryAllowed.remove(charactersIn: "+&=?#")
        guard let emailEnc = email.addingPercentEncoding(withAllowedCharacters: queryAllowed),
              let tidEnc = tid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://mail.google.com/mail/?authuser=\(emailEnc)#all/\(tidEnc)")
    }
}
