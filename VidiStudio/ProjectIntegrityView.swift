import SwiftUI
import AppKit

struct ProjectIntegrityBadge: View {
    let report: ProjectIntegrityReport

    private var color: Color { report.isDamaged ? .red : .orange }
    private var iconName: String {
        report.isDamaged ? "exclamationmark.triangle.fill" : "externaldrive.badge.exclamationmark"
    }
    private var title: String { report.isDamaged ? "Damaged" : "Files Missing" }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(report.badgeAccessibilityLabel)
        .help(report.shortDescription)
    }
}

/// Top-of-editor banner that mirrors the Gemini API key warning. Recoverable
/// deletions are warnings; missing project.json or the source video marks the
/// project as damaged and offers to delete the whole project.
struct ProjectIntegrityBanner: View {
    let project: StudioProject
    let report: ProjectIntegrityReport
    let busy: Bool
    let narrationActionEnabled: Bool
    let showInFinder: () -> Void
    let regenerateNarration: () -> Void
    let regenerateVideoArtifacts: () -> Void
    let deleteProject: () -> Void

    @State private var showsDetails = false

    private var tint: Color { report.isDamaged ? .red : .orange }
    private var iconName: String {
        report.isDamaged ? "exclamationmark.triangle.fill" : "externaldrive.badge.exclamationmark"
    }
    private var actionTint: Color { report.isDamaged ? .red : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .imageScale(.medium)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(report.headline)
                        .font(.subheadline.bold())
                    Text(report.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if report.totalTrackedFiles > 0 {
                        Text("\(report.missingTrackedFiles) of \(report.totalTrackedFiles) tracked files are missing or unreadable.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    if report.isDamaged {
                        Button(report.folderMissing ? "Remove Project…" : "Delete Project…", systemImage: "trash", role: .destructive) { deleteProject() }
                            .buttonStyle(.borderedProminent)
                            .tint(actionTint)
                            .controlSize(.small)
                            .disabled(busy)
                            .help(report.folderMissing
                                ? "Remove the missing project entry from VidiStudio"
                                : "Move the entire damaged project folder to the Bin")
                    }
                    if report.canRegenerateNarration {
                        Button("Regenerate Missing Narration", systemImage: "waveform", action: regenerateNarration)
                            .controlSize(.small)
                            .disabled(busy || !narrationActionEnabled)
                            .help(narrationActionEnabled
                                ? "Recreate narration audio for AD segments whose audio file was removed"
                                : "A valid Gemini API key is required to regenerate Gemini TTS narration")
                    }
                    if report.canRegenerateVideoArtifacts {
                        Button("Regenerate Video Details & Pictures", systemImage: "photo.on.rectangle.angled", action: regenerateVideoArtifacts)
                            .controlSize(.small)
                            .disabled(busy)
                            .help("Recreate metadata/probe.json and timeline pictures from the original video")
                    }
                    HStack(spacing: 6) {
                        if report.canShowInFinder {
                            Button("Show in Finder", systemImage: "folder", action: showInFinder)
                                .controlSize(.small)
                        }
                        if !report.problems.isEmpty {
                            Button(showsDetails ? "Hide Details" : "Show Details", systemImage: showsDetails ? "chevron.up" : "chevron.down") {
                                showsDetails.toggle()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            if showsDetails {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.problems) { problem in
                        ProjectIntegrityProblemView(problem: problem, tint: tint)
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tint.opacity(0.3)), alignment: .bottom)
        .onAppear {
            if report.isDamaged || report.missingTrackedFiles <= 3 { showsDetails = true }
        }
        .onChange(of: report.missingTrackedFiles) { _, missing in
            if report.isDamaged || missing <= 3 { showsDetails = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(report.accessibilityLabel)
    }
}

private struct ProjectIntegrityProblemView: View {
    let problem: ProjectFileProblem
    let tint: Color

    private var problemTint: Color { problem.isCritical ? .red : tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: problem.category.iconName)
                    .foregroundStyle(problemTint)
                    .accessibilityHidden(true)
                Text(problem.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(problemTint)
                Spacer()
            }
            Text(problem.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(problem.impact)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let recovery = problem.recovery {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            if !problem.missingFiles.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(problem.missingFiles) { file in
                            Text(file.displayName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: problem.missingFiles.count > 3 ? 92 : .infinity)
                .padding(.top, 2)
            }
        }
    }
}

struct DamagedProjectPlaceholderView: View {
    let project: StudioProject
    let report: ProjectIntegrityReport
    let busy: Bool
    let showInFinder: () -> Void
    let deleteProject: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Project Damaged", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(report.message)
        } actions: {
            Button(report.folderMissing ? "Remove Project…" : "Delete Project…", systemImage: "trash", role: .destructive) { deleteProject() }
                .disabled(busy)
                .help(report.folderMissing
                    ? "Remove the missing project entry from VidiStudio"
                    : "Move the entire damaged project folder to the Bin")
            if report.canShowInFinder {
                Button("Show in Finder", systemImage: "folder", action: showInFinder)
            }
        }
    }
}
