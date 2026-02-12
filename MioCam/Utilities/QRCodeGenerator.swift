//
//  QRCodeGenerator.swift
//  MioCam
//
//  QRコード生成の共通ユーティリティ
//

import UIKit
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    /// cameraId + pairingCode を JSON 形式にして QR コード画像に変換
    static func generateQRCode(cameraId: String, pairingCode: String) -> UIImage? {
        let payload: [String: String] = [
            "cameraId": cameraId,
            "pairingCode": pairingCode
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// ペアリングコードをフォーマット（現状はそのまま返す）
    static func formatPairingCode(_ code: String) -> String {
        return code
    }
}
