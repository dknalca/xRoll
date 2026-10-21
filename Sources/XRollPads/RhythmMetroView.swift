import SwiftUI
import XRollCore

struct MetroChapter: Identifiable {
    let id: String
    let exercises: [Exercise]
    var title: String { CourseWorld.title(for: id) }
}

struct RhythmMetroView: View {
    @ObservedObject var model: Model

    var body: some View {
        ScrollView {
            CourseRailwayMap(stations: model.campaignWorlds, evidence: model.courseEvidence,
                selectExercise: model.openCampaignLevel)
                .padding(24).frame(maxWidth: 920, alignment: .leading)
        }
        .background(StudioDesign.canvas)
    }
}
