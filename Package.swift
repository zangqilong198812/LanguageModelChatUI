// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LanguageModelChatUI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        // ChatModel 要给 Mac 用。SwiftPM 的 platforms 是包级的,没法只给一个
        // target 声明,所以这里放开之后,UIKit 的那几个 target 在 macOS 上是编
        // 不过的 —— 它们也不该被编:Mac 只链 ChatModel 这一个产物,SwiftPM 就
        // 只构建它和它的依赖(它没有依赖)。
        //
        // 这条约束本身就是守卫:ChatModel 里一旦混进 import UIKit,macOS 构建
        // 立刻断,不需要额外的检查脚本。
        .macOS(.v14),
    ],
    products: [
        // 纯模型,零 UIKit,两端共用:iPhone 的渲染器和 Mac 的 SwiftUI 视图
        // 描述的是同一场对话,模型分家就意味着两块屏各说各话。
        .library(
            name: "ChatModel",
            targets: ["ChatModel"]
        ),
        .library(
            name: "ChatClientKit",
            targets: ["ChatClientKit"]
        ),
        .library(
            name: "LanguageModelChatUI",
            targets: ["LanguageModelChatUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/ListViewKit", from: "1.1.8"),
        .package(url: "https://github.com/Lakr233/MarkdownView", from: "3.7.0"),
        .package(url: "https://github.com/Lakr233/Litext", from: "1.2.1"),
        .package(url: "https://github.com/SnapKit/SnapKit.git", from: "5.7.1"),
        .package(url: "https://github.com/mischa-hildebrand/AlignedCollectionViewFlowLayout", from: "1.1.3"),
        .package(url: "https://github.com/ktiays/GlyphixTextFx/", from: "2.3.6"),
        .package(url: "https://github.com/alfianlosari/GPTEncoder.git", from: "1.0.4"),
    ],
    targets: [
        .target(
            name: "ChatModel",
            path: "Sources/ChatModel",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ServerEvent",
            path: "Sources/ServerEvent"
        ),
        .target(
            name: "ChatClientKit",
            dependencies: ["ServerEvent"],
            path: "Sources/ChatClientKit"
        ),
        .target(
            name: "LanguageModelChatUI",
            dependencies: [
                "ChatModel",
                "ChatClientKit",
                "ListViewKit",
                "MarkdownView",
                .product(name: "MarkdownParser", package: "MarkdownView"),
                "Litext",
                "SnapKit",
                "AlignedCollectionViewFlowLayout",
                "GlyphixTextFx",
                "GPTEncoder",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LanguageModelChatUITests",
            dependencies: ["LanguageModelChatUI"]
        ),
        .testTarget(
            name: "ChatClientKitTests",
            dependencies: ["ChatClientKit"]
        ),
    ]
)
