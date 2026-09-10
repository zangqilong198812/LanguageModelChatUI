// The message model moved out to `ChatModel` so the Mac app can link it —
// those types are pure Foundation and always were, but they lived in this
// target, which is a UIKit view layer and therefore iOS-only.
//
// Re-exported so nothing that already says `import LanguageModelChatUI`
// has to change. The split is meant to be invisible from the iPhone side.
@_exported import ChatModel
