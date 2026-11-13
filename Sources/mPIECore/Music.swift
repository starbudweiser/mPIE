import Foundation

public struct NowPlaying: Equatable, Sendable {
    public var player: MusicPlayer
    public var playing: Bool
    public var title: String
    public var artist: String
    public var shuffle: Bool
    public var repeating: Bool
    public var artworkURL: String?

    public init(player: MusicPlayer, playing: Bool, title: String, artist: String, shuffle: Bool, repeating: Bool, artworkURL: String? = nil) {
        self.player = player; self.playing = playing; self.title = title; self.artist = artist
        self.shuffle = shuffle; self.repeating = repeating; self.artworkURL = artworkURL
    }
}

public enum MusicCommand: String, Sendable {
    case playPause, next, previous, shuffle, repeatToggle
}

/// Scripts AppleScript de la télécommande (Musique et Spotify). Aucun n'est lancé si l'appli ne tourne pas.
public enum MusicScripts {
    public static func appName(_ player: MusicPlayer) -> String { player == .spotify ? "Spotify" : "Music" }

    public static func command(_ command: MusicCommand, player: MusicPlayer) -> String {
        let app = appName(player)
        switch (command, player == .spotify) {
        case (.playPause, _): return "tell application \"\(app)\" to playpause"
        case (.next, _): return "tell application \"\(app)\" to next track"
        case (.previous, _): return "tell application \"\(app)\" to previous track"
        case (.shuffle, false): return "tell application \"Music\" to set shuffle enabled to not shuffle enabled"
        case (.shuffle, true): return "tell application \"Spotify\" to set shuffling to not shuffling"
        case (.repeatToggle, false):
            return """
            tell application "Music"
              if song repeat is off then
                set song repeat to all
              else if song repeat is all then
                set song repeat to one
              else
                set song repeat to off
              end if
            end tell
            """
        case (.repeatToggle, true): return "tell application \"Spotify\" to set repeating to not repeating"
        }
    }

    /// Renvoie « état|||titre|||artiste|||aléatoire|||répétition[|||pochette] ».
    public static func info(player: MusicPlayer) -> String {
        if player == .spotify {
            return """
            tell application "Spotify"
              if player state is stopped then return "stopped||||||||||false|||false|||"
              return (player state as string) & "|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (shuffling as string) & "|||" & (repeating as string) & "|||" & (artwork url of current track)
            end tell
            """
        }
        return """
        tell application "Music"
          if player state is stopped then return "stopped||||||||||false|||off|||"
          return (player state as string) & "|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (shuffle enabled as string) & "|||" & (song repeat as string) & "|||"
        end tell
        """
    }

    public static func parse(_ output: String, player: MusicPlayer) -> NowPlaying? {
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 5 else { return nil }
        let repeating = player == .spotify ? parts[4] == "true" : parts[4] != "off" && !parts[4].isEmpty
        let artwork = parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil
        return NowPlaying(player: player, playing: parts[0] == "playing", title: parts[1], artist: parts[2],
                          shuffle: parts[3] == "true", repeating: repeating, artworkURL: artwork)
    }

    /// Enregistre la pochette de la piste courante d'Apple Musique dans `path` (Spotify donne une adresse web).
    public static func artwork(toFile path: String) -> String {
        """
        tell application "Music"
          try
            set d to raw data of artwork 1 of current track
            set f to open for access POSIX file "\(path)" with write permission
            set eof of f to 0
            write d to f
            close access f
            return "ok"
          on error
            try
              close access POSIX file "\(path)"
            end try
            return "none"
          end try
        end tell
        """
    }
}
