import Foundation

public enum HanlinYouTubeDocument {
    /// The app identity is supplied by the installed bundle, never the model payload.
    public static func origin(bundleID: String?) -> URL? {
        guard let bundleID, !bundleID.isEmpty, bundleID.utf8.count <= 255,
              bundleID.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte)
                      || (48...57).contains(byte) || byte == 45 || byte == 46
              }) else { return nil }
        let labels = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63
            && !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else { return nil }
        return URL(string: "https://\(bundleID.lowercased())")
    }

    public static func html(video: HanlinYouTubeVideo, origin: URL) -> String {
        // Only validated ID and app identity enter JSON; no model title/HTML/JavaScript enters.
        let settings: [String: Any] = [
            "videoId": video.id,
            "playerVars": ["autoplay": 0, "controls": 1, "playsinline": 1,
                           "origin": origin.absoluteString] as [String: Any]
        ]
        let encoded = String(decoding: try! JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]), as: UTF8.self)
        let nonce = UUID().uuidString
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)' https://www.youtube.com https://s.ytimg.com; style-src 'nonce-\(nonce)'; frame-src https://www.youtube.com https://www.youtube-nocookie.com; connect-src https://www.youtube.com; img-src https://i.ytimg.com">
        <style nonce="\(nonce)">html,body,#player{margin:0;width:100%;height:100%;background:black}iframe{border:0}</style>
        </head><body><div id="player"></div><script nonce="\(nonce)">
        let player;
        const report = value => window.webkit.messageHandlers.hanlinYouTube.postMessage(value);
        function onYouTubeIframeAPIReady() {
          const options = \(encoded);
          options.width = '100%'; options.height = '100%';
          options.events = {
            onReady: () => report({kind:'ready'}),
            onError: event => report({kind:'error',code:event.data})
          };
          player = new YT.Player('player', options);
        }
        window.hanlinStopYouTube = () => { if (player) { player.destroy(); player = null; } };
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
    }
}
