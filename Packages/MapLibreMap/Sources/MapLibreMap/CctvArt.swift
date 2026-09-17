import UIKit

/// Split red / blue disc. The CCTV mark on the packed desk.
enum CctvArt {
    static func dot() -> UIImage {
        let size: CGFloat = 44
        let well: CGFloat = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let disc = CGRect(
                x: (size - well) / 2,
                y: (size - well) / 2,
                width: well,
                height: well
            )
            cg.saveGState()
            cg.addEllipse(in: disc)
            cg.clip()
            cg.setFillColor(
                UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1).cgColor
            )
            cg.fill(CGRect(x: disc.minX, y: disc.minY, width: well / 2, height: well))
            cg.setFillColor(
                UIColor(red: 61.0 / 255.0, green: 158.0 / 255.0, blue: 1, alpha: 1).cgColor
            )
            cg.fill(CGRect(x: disc.midX, y: disc.minY, width: well / 2, height: well))
            cg.restoreGState()
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(1.5)
            cg.strokeEllipse(in: disc)
        }
    }
}
