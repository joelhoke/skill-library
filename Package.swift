// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SkillLibrary", platforms: [.macOS(.v14)], products: [
    .executable(name: "SkillLibrary", targets: ["SkillLibrary"]),
    .executable(name: "skilltool", targets: ["SkillTool"])
], targets: [
    .target(name: "SkillCore"),
    .executableTarget(name: "SkillLibrary", dependencies: ["SkillCore"]),
    .executableTarget(name: "SkillTool", dependencies: ["SkillCore"]),
    .testTarget(name: "SkillCoreTests", dependencies: ["SkillCore"])
], swiftLanguageModes: [.v5])
