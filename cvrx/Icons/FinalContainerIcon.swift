//
//  FinalContainerIcon.swift
//  cvrx
//
//  Created by Josh Steinbecker on 5/28/26.
//
import SwiftUI


func finalContainerIcon(kind: String) -> some View {
    if (kind == ContainerKind.IVPB.rawValue) {
        return Image(systemName: "ivfluid.bag", variableValue: 1.00)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.accentColor, Color.accentColor)
            .font(.system(size: 16, weight: .regular))
    }
    else if (kind == ContainerKind.Syringe.rawValue) {
        return Image(systemName: "syringe", variableValue: 1.00)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.accentColor, Color.accentColor)
            .font(.system(size: 16, weight: .regular))
    }
    else if (kind == ContainerKind.CADD.rawValue) {
        return Image(systemName: "button.horizontal.top.fill", variableValue: 1.00)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.accentColor, Color.accentColor)
            .font(.system(size: 16, weight: .regular))
    }
    else {
        return Image(systemName: "cross.circle", variableValue: 1.00)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.accentColor, Color.accentColor)
            .font(.system(size: 16, weight: .regular))
    }
}

func finalCntrIconName(kind: String) -> String {
    if (kind == ContainerKind.IVPB.rawValue) {
        return "ivfluid.bag"
    }
    else if (kind == ContainerKind.Syringe.rawValue) {
        return "syringe"
    }
    else if (kind == ContainerKind.CADD.rawValue) {
        return "button.horizontal.top.fill"
    }
    else {
        return "cross.circle"
    }
}
