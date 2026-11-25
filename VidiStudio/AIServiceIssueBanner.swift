import SwiftUI

/// Persistent application-wide warning shown after Gemini quota, billing, or
/// service failures. AI actions stay disabled until Retry AI succeeds.
struct AIServiceIssueBanner: View {
    @Bindable var studio: StudioModel
    var showsProjectStatus = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if showsProjectStatus && studio.selected?.requiresLocalYouTubePlayback == true {
            Label(YouTubeVideo.privateAnalysisMessage, systemImage: "info.circle")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.secondary.opacity(0.1))
        } else if let issue = studio.aiServiceIssue {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: issue.kind == .quota ? "creditcard.trianglebadge.exclamationmark" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.title)
                        .font(.subheadline.bold())
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("AI reprocessing is disabled until this is resolved. Existing transcripts, descriptions, narration, and exports are unchanged.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button("Retry AI", systemImage: "arrow.clockwise") {
                        studio.retryAIConnection()
                    }
                    .controlSize(.small)
                    .disabled(studio.busy)
                    .help("Check the active AI connection again.")
                    .requiresInternet(.gemini)
                    Button("AI Settings…", systemImage: "gearshape") {
                        studio.settingsSection = "Gemini"
                        SettingsSectionRequest.request("Gemini")
                        openSettings()
                    }
                    .controlSize(.small)
                    .help("Open AI settings to review the active connection.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.orange.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.orange.opacity(0.3)), alignment: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(issue.title). \(issue.message). AI reprocessing is disabled.")
        }
    }
}
