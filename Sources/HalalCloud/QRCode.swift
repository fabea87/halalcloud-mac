//
//  QRCode.swift
//  HalalCloud
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCode {
    static func image(for text: String) -> NSImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let image = QRCode.image(for: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(ProgressView())
            }
        }
    }
}
