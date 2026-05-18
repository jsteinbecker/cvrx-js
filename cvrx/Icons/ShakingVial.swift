//
//  ShakingVial.swift
//  cvrx
//
//  Created by Josh Steinbecker on 5/27/26.
//

import SwiftUI

var vialShake: some View {
    Image(systemName: "cross.vial", variableValue: 1.00)
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.white, Color.accentColor, Color(red: 0.0, green: 0.0, blue: 0.0))
        .font(.system(size: 16, weight: .regular))
}
