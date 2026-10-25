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

/// Compact top-of-editor notice. Detailed information lives in the
/// project-named dialog so the viewer, timeline, and thumbnails keep their
/// normal size.
struct ProjectIntegrityBanner: View {
    let project: StudioProject
    let report: ProjectIntegrityReport
    let busy: Bool
    let narrationActionEnabled: Bool
    let showInFinder: () -> Void
    let regenerateNarration: () -> Void
    let regenerateVideoArtifacts: () -> Void
    let deleteProject: () -> Void

    @State private var showingIssues = false

    private var tint: Color { report.isDamaged ? .red : .orange }
    private var iconName: String {
        report.isDamaged ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
    }
    private var issueCount: Int { report.problems.count }
    private var reviewTitle: String {
        issueCount == 1 ? "Review Issue…" : "Review \(issueCount) Issues…"
    }
    private var bannerTitle: String {
        report.isDamaged
            ? "“\(project.name)” needs attention"
            : "“\(project.name)” has missing files"
    }
    private var bannerMessage: String {
        if report.folderMissing {
            return "The project folder is missing. Restore it, or remove this project entry."
        }
        if report.manifestUnreadable {
            return "project.json is missing or damaged. Restore it from a backup, or delete the project."
        }
        if report.problems.contains(where: { $0.category == .source }) {
            return "The original video is missing. Playback, analysis, and video exports are unavailable."
        }
        if report.isDamaged {
            return "Most project files are missing. Review the remaining files or delete the project."
        }
        if report.problems.count == 1, let problem = report.problems.first {
            switch problem.category {
            case .narration:
                return "Narration audio is missing for \(problem.missingCount) AD segment\(problem.missingCount == 1 ? "" : "s"). It can be regenerated."
            case .thumbnails:
                return "Timeline pictures are missing. They can be regenerated from the original video."
            case .metadata:
                return "Video details are missing. They can be regenerated from the original video."
            case .exports:
                return "\(problem.missingCount) exported file\(problem.missingCount == 1 ? "" : "s") missing. Export again to recreate \(problem.missingCount == 1 ? "it" : "them")."
            case .manifest, .source, .significantLoss:
                break
            }
        }
        return "\(report.missingTrackedFiles) of \(report.totalTrackedFiles) tracked files are missing. Generated files can usually be regenerated."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(tint)
                .imageScale(.medium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(bannerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if report.canShowInFinder {
                    Button("Show in Finder", systemImage: "folder", action: showInFinder)
                        .labelStyle(.iconOnly)
                        .controlSize(.small)
                        .help("Show this project in Finder")
                }
                if report.isDamaged {
                    Button(report.folderMissing ? "Remove Project…" : "Delete Project…", systemImage: "trash", role: .destructive) {
                        deleteProject()
                    }
                    .controlSize(.small)
                    .disabled(busy)
                    .help(report.folderMissing
                        ? "Remove the missing project entry from VidiStudio"
                        : "Move the entire damaged project folder to the Bin")
                }
                Button(reviewTitle, systemImage: "list.bullet.rectangle") {
                    showingIssues = true
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tint.opacity(0.25)), alignment: .bottom)
        .sheet(isPresented: $showingIssues) {
            ProjectIntegrityDetailsSheet(
                report: report,
                busy: busy,
                narrationActionEnabled: narrationActionEnabled,
                showInFinder: showInFinder,
                regenerateNarration: regenerateNarration,
                regenerateVideoArtifacts: regenerateVideoArtifacts,
                deleteProject: deleteProject
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(report.accessibilityLabel)
    }
}

/// Small inspector icon shown when a project has more than one integrity
/// issue. It opens the same project-named issue dialog used by the banner.
struct ProjectIntegrityDialogButton: View {
    let report: ProjectIntegrityReport
    let busy: Bool
    let narrationActionEnabled: Bool
    var showInFinder: (() -> Void)? = nil
    var regenerateNarration: (() -> Void)? = nil
    var regenerateVideoArtifacts: (() -> Void)? = nil
    var deleteProject: (() -> Void)? = nil

    @State private var showingIssues = false

    private var tint: Color { report.isDamaged ? .red : .orange }
    private var iconName: String {
        report.isDamaged ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
    }
    private var issueCount: Int { report.problems.count }

    var body: some View {
        Button {
            showingIssues = true
        } label: {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel("Show all \(issueCount) project file issues")
        .help("Show all \(issueCount) project file issues")
        .sheet(isPresented: $showingIssues) {
            ProjectIntegrityDetailsSheet(
                report: report,
                busy: busy,
                narrationActionEnabled: narrationActionEnabled,
                showInFinder: showInFinder,
                regenerateNarration: regenerateNarration,
                regenerateVideoArtifacts: regenerateVideoArtifacts,
                deleteProject: deleteProject
            )
        }
    }
}

struct ProjectIntegrityDetailsSheet: View {
    let report: ProjectIntegrityReport
    let busy: Bool
    let narrationActionEnabled: Bool
    var showInFinder: (() -> Void)? = nil
    var regenerateNarration: (() -> Void)? = nil
    var regenerateVideoArtifacts: (() -> Void)? = nil
    var deleteProject: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var tint: Color { report.isDamaged ? .red : .orange }
    private var iconName: String {
        report.isDamaged ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
    }
    private var statusTitle: String { report.isDamaged ? "Damaged" : "Needs Attention" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(report.problems) { problem in
                        ProjectIntegrityProblemView(problem: problem, tint: tint)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 740, minHeight: 540, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project file issues for \(report.projectName). \(report.accessibilityLabel)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Project File Issues")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.13), in: Capsule())
                }
                Text(report.projectName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(report.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(report.problems.count) issue\(report.problems.count == 1 ? "" : "s") · \(report.missingTrackedFiles) of \(report.totalTrackedFiles) tracked files missing or unreadable")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if report.canShowInFinder, let showInFinder {
                Button("Show in Finder", systemImage: "folder") {
                    dismiss()
                    showInFinder()
                }
            }
            if report.canRegenerateNarration, let regenerateNarration {
                Button("Regenerate Missing Narration", systemImage: "waveform") {
                    dismiss()
                    regenerateNarration()
                }
                .disabled(busy || !narrationActionEnabled)
                .help(narrationActionEnabled
                    ? "Recreate narration audio for AD segments whose audio file was removed"
                    : "A valid Gemini API key is required to regenerate Gemini TTS narration")
            }
            if report.canRegenerateVideoArtifacts, let regenerateVideoArtifacts {
                Button("Regenerate Video Details & Pictures", systemImage: "photo.on.rectangle.angled") {
                    dismiss()
                    regenerateVideoArtifacts()
                }
                .disabled(busy)
            }

            Spacer()

            if report.isDamaged, let deleteProject {
                Button(report.folderMissing ? "Remove Project…" : "Delete Project…", systemImage: "trash", role: .destructive) {
                    dismiss()
                    deleteProject()
                }
                .disabled(busy)
                .help(report.folderMissing
                    ? "Remove the missing project entry from VidiStudio"
                    : "Move the entire damaged project folder to the Bin")
            }
        }
        .padding(16)
    }
}

struct ProjectIntegrityProblemView: View {
    let problem: ProjectFileProblem
    let tint: Color

    private var problemTint: Color { problem.isCritical ? .red : tint }
    private var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(problemTint.opacity(0.12))
                    Image(systemName: problem.category.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(problemTint)
                        .accessibilityHidden(true)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(problem.title)
                        .font(.headline)
                    Text(problem.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text(problem.impact)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let recovery = problem.recovery {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(problemTint)
                        .accessibilityHidden(true)
                    Text(recovery)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !problem.missingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Missing files")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(problem.missingFiles) { file in
                                Text(file.displayName)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: problem.missingFiles.count > 4 ? 132 : nil)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(problemTint.opacity(0.16), lineWidth: 1)
        )
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
