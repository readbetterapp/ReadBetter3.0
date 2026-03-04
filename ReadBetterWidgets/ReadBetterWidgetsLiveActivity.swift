//
//  ReadBetterWidgetsLiveActivity.swift
//  ReadBetterWidgets
//
//  Created by Ermin on 4/3/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ReadBetterWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ReadBetterWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadBetterWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ReadBetterWidgetsAttributes {
    fileprivate static var preview: ReadBetterWidgetsAttributes {
        ReadBetterWidgetsAttributes(name: "World")
    }
}

extension ReadBetterWidgetsAttributes.ContentState {
    fileprivate static var smiley: ReadBetterWidgetsAttributes.ContentState {
        ReadBetterWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ReadBetterWidgetsAttributes.ContentState {
         ReadBetterWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ReadBetterWidgetsAttributes.preview) {
   ReadBetterWidgetsLiveActivity()
} contentStates: {
    ReadBetterWidgetsAttributes.ContentState.smiley
    ReadBetterWidgetsAttributes.ContentState.starEyes
}
