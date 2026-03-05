import Foundation

enum ProxySettings {
    /// Returns a URLSessionConfiguration with proxy settings applied (if enabled).
    static func configuredSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        let defaults = UserDefaults.standard

        guard defaults.bool(forKey: Constants.Keys.proxyEnabled),
              let host = defaults.string(forKey: Constants.Keys.proxyHost), !host.isEmpty,
              let portString = defaults.string(forKey: Constants.Keys.proxyPort),
              let port = Int(portString), port > 0 else {
            return config
        }

        let proxyType = defaults.string(forKey: Constants.Keys.proxyType) ?? "http"
        let username = defaults.string(forKey: Constants.Keys.proxyUsername) ?? ""
        let password = defaults.string(forKey: Constants.Keys.proxyPassword) ?? ""

        var proxyDict: [String: Any] = [:]

        if proxyType == "socks5" {
            proxyDict[kCFStreamPropertySOCKSProxyHost as String] = host
            proxyDict[kCFStreamPropertySOCKSProxyPort as String] = port
            if !username.isEmpty {
                proxyDict[kCFStreamPropertySOCKSUser as String] = username
                proxyDict[kCFStreamPropertySOCKSPassword as String] = password
            }
        } else {
            // HTTP proxy
            proxyDict[kCFNetworkProxiesHTTPEnable as String] = true
            proxyDict[kCFNetworkProxiesHTTPProxy as String] = host
            proxyDict[kCFNetworkProxiesHTTPPort as String] = port
            // HTTPS through HTTP proxy
            proxyDict["HTTPSEnable"] = true
            proxyDict["HTTPSProxy"] = host
            proxyDict["HTTPSPort"] = port
            if !username.isEmpty {
                proxyDict[kCFProxyUsernameKey as String] = username
                proxyDict[kCFProxyPasswordKey as String] = password
            }
        }

        config.connectionProxyDictionary = proxyDict
        return config
    }
}
