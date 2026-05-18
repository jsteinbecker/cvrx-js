//
//  VialViewfinder.swift
//  cvrx
//
//  Created by Josh Steinbecker on 5/28/26.
//

import SwiftUI

var vialViewfinderIcon: some View {
    Image(systemName: "vial.viewfinder", variableValue: 1.00)
    .symbolRenderingMode(.palette)
    .foregroundStyle(Color.white, Color.accentColor, Color.accentColor)
    .font(.system(size: 16, weight: .regular))
}
