import CueCore
import Foundation

/// Dictionary loading and conversion begin only when a conversion is requested.
/// The launcher never waits for this actor while typing or presenting results.
actor ChineseConversionEngine {
    static let shared = ChineseConversionEngine()
    private var converter: ChineseConverter?

    enum Failure: Error { case unavailable }

    func convert(_ text: String, to target: ChineseConversionTarget) throws -> String {
        try Task.checkCancellation()
        guard text.utf8.count <= ChineseConverter.maximumInputBytes else { throw SelectedTextError.textTooLarge }
        if converter == nil {
            #if SWIFT_PACKAGE && !CUE_APP_BUNDLE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            guard let url = bundle.url(forResource: "ChineseConversion", withExtension: "cuecc") else {
                throw Failure.unavailable
            }
            converter = try ChineseConverter(resourceURL: url)
        }
        try Task.checkCancellation()
        return try converter!.convert(text, to: target)
    }
}
