//
//  ReadBetterWidgetsBundle.swift
//  ReadBetterWidgets
//
//  Created by Ermin on 4/3/2026.
//

import WidgetKit
import SwiftUI

@main
struct ReadBetterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadBetterWidgets()
        ReadBetterWidgetsControl()
        ReadBetterWidgetsLiveActivity()
        ReadingLiveActivity()
    }
}
