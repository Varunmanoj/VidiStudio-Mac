import Foundation

@main
struct ShareLinkHarness {
    static func main() {
        let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30")!
        let video = URL(fileURLWithPath: "/tmp/A shared movie #1.mov")

        precondition(VidiStudioShareLink.youtubeVideoID(from: watch.absoluteString) == "dQw4w9WgXcQ")
        precondition(VidiStudioShareLink.youtubeVideoID(from: "https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        precondition(VidiStudioShareLink.youtubeVideoID(from: "https://example.com/watch?v=dQw4w9WgXcQ") == nil)

        let youtubeLink = VidiStudioShareLink.makeURL(for: .youtube(watch))!
        precondition(VidiStudioShareLink.parse(youtubeLink) == .youtube(watch))

        let videoLink = VidiStudioShareLink.makeURL(for: .videoFile(video))!
        precondition(VidiStudioShareLink.parse(videoLink) == .videoFile(video))

        precondition(VidiStudioShareLink.parse(URL(string: "vidistudio://share?kind=youtube&source=https://example.com")!) == nil)
        precondition(VidiStudioShareLink.parse(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!) == nil)
        print("VidiStudio share-link checks passed")
    }
}
