import WidgetKit
import SwiftUI

private val sharedDefaults = UserDefaults(suiteName: "group.com.cardcompass.cardcompass")

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), cardName: "Loading...", reasoning: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), cardName: "HDFC Diners Black", reasoning: "Best for Dining")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let cardName = sharedDefaults?.string(forKey: "widget_card_name") ?? "No cards available"
        let reasoning = sharedDefaults?.string(forKey: "widget_reasoning") ?? "Open app to configure"

        let entry = SimpleEntry(date: Date(), cardName: cardName, reasoning: reasoning)

        // Update widget every 30 mins
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let cardName: String
    let reasoning: String
}

struct CardCompassWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best Card Right Now")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "6C63FF"))

            Text(entry.cardName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Text(entry.reasoning)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .background(Color(hex: "050B18"))
    }
}

@main
struct CardCompassWidget: Widget {
    let kind: String = "CardCompassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CardCompassWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("CardCompass Recommender")
        .description("Shows the best credit card to use right now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Helper to use Hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
