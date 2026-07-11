import SwiftUI

/// Reads a journal entry as a diary page — warm paper, handwriting, a dated
/// header — like turning a page in a notebook. Edit opens the structured editor.
struct DiaryPageView: View {
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
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 480, alignment: .topLeading)
        }
        .background(paper.ignoresSafeArea())
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
