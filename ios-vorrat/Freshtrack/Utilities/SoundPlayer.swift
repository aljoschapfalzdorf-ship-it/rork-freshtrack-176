import AVFoundation

/// Spielt den professionellen UI-Klick ("ui_click_tick") — ausschließlich
/// beim Öffnen des Pro-Paywalls und beim Tap auf den KI-Koch-Tab.
enum SoundPlayer {
    private static var player: AVAudioPlayer?

    static func playChime() {
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [])
            guard let url = Bundle.main.url(forResource: "ui_click_tick", withExtension: "mp3"),
                  let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
            loaded.volume = 1.0
            player = loaded
        }
        player?.currentTime = 0
        player?.play()
    }
}
