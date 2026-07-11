import SwiftUI

/// The visual of a single diary page — warm paper, a dated header, and the
/// narrative set in handwriting. Used both standalone (DiaryPageView) and as a
/// page inside the flip-through reader (JournalReaderView).
struct DiaryPageContent: View {
    @Bindable var experience: Experience

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let ink   = Color(red: 0.20, green: 0.16, blue: 0.12)

    /// The narrative to read — the original note if we have it, else the summary.
    private var body_text: String {
        let raw = experience.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? experience.summary : raw
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(experience.timelineDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.custom("Caveat-Bold", size: 26))
                    .foregroundStyle(ink.opacity(0.65))

                if experience.hasLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(experience.location)
                    }
                    .font(.custom("Caveat-Regular", size: 20))
                    .foregroundStyle(ink.opacity(0.55))
                }

                Rectangle()
                    .fill(ink.opacity(0.15))
                    .frame(height: 1)

                Text(body_text)
                    .font(.custom("Caveat-Regular", size: 30))
                    .lineSpacing(6)
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if !experience.learning.isEmpty {
                    Text("— \(experience.learning)")
                        .font(.custom("Caveat-Bold", size: 26))
                        .foregroundStyle(ink.opacity(0.8))
                        .padding(.top, 4)
                }

                HStack(spacing: 6) {
                    Image(systemName: experience.tone.symbol)
                    Text(experience.tone.label)
                }
                .font(.custom("Caveat-Regular", size: 22))
                .foregroundStyle(experience.tone.tint)
                .padding(.top, 6)

                if experience.hasHealthContext {
                    HStack(spacing: 16) {
                        if let hours = experience.sleepHours {
                            healthChip("bed.double.fill", String(format: "%.1f h", hours))
                        }
                        if let steps = experience.steps {
                            healthChip("figure.walk", steps.formatted())
                        }
                        if let count = experience.workoutCount, count > 0 {
                            healthChip("figure.run", count == 1 ? "1 workout" : "\(count) workouts")
                        }
                    }
                    .font(.custom("Caveat-Regular", size: 18))
                    .foregroundStyle(ink.opacity(0.5))
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 480, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paper)
    }

    private func healthChip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
    }
}

/// Reads a single journal entry as a diary page. Edit opens the structured editor.
struct DiaryPageView: View {
    @Bindable var experience: Experience

    var body: some View {
        DiaryPageContent(experience: experience)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(experience.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExperienceDetailView(experience: experience)
                    } label: {
                        Text("Edit")
                    }
                }
            }
    }
}
