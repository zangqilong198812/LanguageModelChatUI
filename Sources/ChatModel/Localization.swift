import Foundation

/// The handful of words the model types say out loud.
///
/// `ProgressStep.label` returns display text, which is a little unusual for a
/// model type — but it shipped that way and both apps read it, so the split
/// keeps it rather than changing behaviour on the way past.
///
/// This target carries its own four-key catalog instead of reaching into
/// `LanguageModelChatUI`'s: that one is the iOS view layer's, and depending on
/// it backwards would put UIKit back in ChatModel's path — which is the whole
/// thing this split exists to avoid.
enum ChatModelStrings {
    static func localized(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .module)
    }
}
