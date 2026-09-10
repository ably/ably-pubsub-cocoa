import ArgumentParser
import AsyncAlgorithms
import Foundation
import Table

@main
@available(macOS 14, *)
struct BuildTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [
            BuildLibrary.self,
            BuildLibraryForTesting.self,
            TestLibrary.self,
            BuildExampleApp.self,
            GenerateMatrices.self,
            Lint.self,
            SpecCoverage.self,
            BuildDocumentation.self,
            GenerateCodeCoverage.self,
        ],
    )
}

@available(macOS 14, *)
struct BuildLibrary: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the AblyLiveObjects library",
    )

    @Option var configuration: Configuration?
    @Option var platform: Platform

    mutating func run() async throws {
        let destinationSpecifier = try await platform.resolve()
        let scheme = "AblyLiveObjects"

        try await XcodeRunner.runXcodebuild(action: "build", configuration: configuration, scheme: scheme, destination: destinationSpecifier)
    }
}

@available(macOS 14, *)
struct BuildLibraryForTesting: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build the AblyLiveObjects library for testing",
        discussion: "This is for use with test-library --without-building.",
    )

    @Option var platform: Platform

    mutating func run() async throws {
        let destinationSpecifier = try await platform.resolve()
        let scheme = "AblyLiveObjects"

        try await XcodeRunner.runXcodebuild(action: "build-for-testing", scheme: scheme, destination: destinationSpecifier)
    }
}

@available(macOS 14, *)
struct TestLibrary: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Test the AblyLiveObjects library",
        discussion: "By default, this builds and tests in a single step. Pass --without-building to skip the build (requires a prior build-library-for-testing step).",
    )

    @Option var platform: Platform
    @Flag(help: "Only run unit tests (excludes integration tests).")
    var onlyUnitTests = false
    @Flag(help: "Skip building; requires a prior build-library-for-testing step.")
    var withoutBuilding = false

    mutating func run() async throws {
        let destinationSpecifier = try await platform.resolve()
        let scheme = "AblyLiveObjects"

        let action = withoutBuilding ? "test-without-building" : "test"
        try await XcodeRunner.runXcodebuild(action: action, scheme: scheme, destination: destinationSpecifier, testPlan: onlyUnitTests ? "UnitTests" : nil)
    }
}

@available(macOS 14, *)
struct GenerateCodeCoverage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate code coverage for the AblyLiveObjects library",
        discussion: "Runs the unit tests and outputs a .xcresult bundle containing code coverage information",
    )

    @Option(help: "Pathname of where to output the .xcresult bundle.")
    var resultBundlePath: String

    mutating func run() async throws {
        let platform = Platform.macOS
        let destinationSpecifier = try await platform.resolve()
        let scheme = "AblyLiveObjects"

        try await XcodeRunner.runXcodebuild(
            action: "test",
            scheme: scheme,
            destination: destinationSpecifier,
            testPlan: "UnitTests",
            resultBundlePath: resultBundlePath,
        )
    }
}

@available(macOS 14, *)
struct BuildExampleApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build the AblyLiveObjectsExample example app")

    @Option var platform: Platform

    mutating func run() async throws {
        let destinationSpecifier = try await platform.resolve()

        let secretsFilePath = "Example/AblyLiveObjectsExample/Secrets.swift"
        if !FileManager.default.fileExists(atPath: secretsFilePath) {
            // If it doesn't already exist (e.g. if running in CI), create the Secrets.swift file needed to build the example app
            let secretsFileContents = """
            enum Secrets {
                // Insert your Ably API key inside the double quotes below.
                static let ablyAPIKey = ""
            }

            """

            let data = secretsFileContents.data(using: .utf8)!
            try data.write(to: .init(filePath: secretsFilePath))
        }

        try await XcodeRunner.runXcodebuild(action: nil, scheme: "AblyLiveObjectsExample", destination: destinationSpecifier)
    }
}

struct GenerateMatrices: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a build matrix that can be used for specifying which GitHub jobs to run",
        discussion: """
        Outputs a key=value string which, when appended to $GITHUB_OUTPUT, sets the job's `matrix` output to a JSON object which can be used for generating builds. This allows us to make sure that our various matrix jobs use consistent parameters.

        This object has the following structure:

        {
            withoutPlatform: { tooling: Tooling }[]
            withPlatform: { tooling: Tooling, platform: PlatformArgument }[]
        }

        where Tooling is

        {
            xcodeVersion: string
        }

        and PlatformArgument is a value that can be passed as the --platform argument of the build-and-test-library or build-example-app commands.
        """,
    )

    mutating func run() throws {
        let tooling = ["16.4"].map { xcodeVersion in
            [
                "xcodeVersion": xcodeVersion,
            ]
        }

        let matrix: [String: Any] = [
            "withoutPlatform": [
                "tooling": tooling,
            ],
            "withPlatform": [
                "tooling": tooling,
                "platform": Platform.allCases.map(\.rawValue),
            ],
        ]

        // I'm assuming the JSONSerialization output has no newlines
        let keyValue = try "matrix=\(String(data: JSONSerialization.data(withJSONObject: matrix), encoding: .utf8))"
        fputs("\(keyValue)\n", stderr)
        print(keyValue)
    }
}

@available(macOS 14, *)
struct Lint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Checks code formatting and quality.")

    enum Error: Swift.Error {
        case malformedSwiftVersionFile
        case malformedPackageManifestFile
        case malformedPackageLockfile
        case mismatchedVersions(swiftVersionFileVersion: String, packageManifestFileVersion: String)
        case packageLockfilesHaveDifferentContents(paths: [String])
    }

    @Flag(name: .customLong("fix"), help: .init("Fixes linting errors where possible before linting"))
    var shouldFix = false

    mutating func run() async throws {
        if shouldFix {
            try await fix()
            try await lint()
        } else {
            try await lint()
        }
    }

    func lint() async throws {
        try await ProcessRunner.run(executableName: "mint", arguments: ["run", "swiftformat", "--lint", "."])
        try await ProcessRunner.run(executableName: "mint", arguments: ["run", "swiftlint"])
        try await ProcessRunner.run(executableName: "npm", arguments: ["run", "prettier:check"])
        try await checkSwiftVersionFile()
        try await comparePackageLockfiles()
    }

    func fix() async throws {
        try await ProcessRunner.run(executableName: "mint", arguments: ["run", "swiftformat", "."])
        try await ProcessRunner.run(executableName: "mint", arguments: ["run", "swiftlint", "--fix"])
        try await ProcessRunner.run(executableName: "npm", arguments: ["run", "prettier:fix"])
    }

    /// Checks that the Swift version specified by the `Package.swift`'s `"swift-tools-version"` matches that in the `.swift-version` file (which is used to tell SwiftFormat the minimum version of Swift supported by our code). Per [SwiftFormat#1496](https://github.com/nicklockwood/SwiftFormat/issues/1496) it's currently our responsibility to make sure they're kept in sync.///
    func checkSwiftVersionFile() async throws {
        // The manifest that governs the compilation of the LiveObjects sources
        // is the root ably-cocoa one (BuildTool is run with the LiveObjects
        // directory as the working directory).
        async let swiftVersionFileContents = loadUTF8StringFromFile(at: ".swift-version")
        async let packageManifestFileContents = loadUTF8StringFromFile(at: "../Package.swift")

        guard let swiftVersionFileMatch = try await /^(\d+\.\d+)\n$/.firstMatch(in: swiftVersionFileContents) else {
            throw Error.malformedSwiftVersionFile
        }

        let swiftVersionFileVersion = String(swiftVersionFileMatch.1)

        guard let packageManifestFileMatch = try await /^\/\/ swift-tools-version: (\d+\.\d+)\n/.firstMatch(in: packageManifestFileContents) else {
            throw Error.malformedPackageManifestFile
        }

        let packageManifestFileVersion = String(packageManifestFileMatch.1)

        if swiftVersionFileVersion != packageManifestFileVersion {
            throw Error.mismatchedVersions(
                swiftVersionFileVersion: swiftVersionFileVersion,
                packageManifestFileVersion: packageManifestFileVersion,
            )
        }
    }

    /// Checks that the SPM-managed Package.resolved matches the Xcode-managed one. (I still don't fully understand _why_ there are two files).
    ///
    /// Ignores the `originHash` property of the Package.resolved file, because this property seems to frequently be different between the SPM version and the Xcode version, and I don't know enough about SPM to know what this property means or whether there's a reproducible way to get them to match.
    func comparePackageLockfiles() async throws {
        // The SPM-managed lockfile is the root ably-cocoa one (BuildTool is run
        // with the LiveObjects directory as the working directory).
        let lockfilePaths = ["../Package.resolved", "AblyLiveObjects.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
        let lockfileContents = try await withThrowingTaskGroup(of: Data.self) { group in
            for lockfilePath in lockfilePaths {
                group.addTask {
                    try await loadDataFromFile(at: lockfilePath)
                }
            }

            return try await group.reduce(into: []) { accum, fileContents in
                accum.append(fileContents)
            }
        }

        // Remove the `originHash` property from the Package.resolved contents before comparing (for reasons described above).
        let lockfileContentsWeCareAbout = try lockfileContents.map { data in
            guard var dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Error.malformedPackageLockfile
            }

            dictionary.removeValue(forKey: "originHash")

            // We use .sortedKeys to get a canonical JSON encoding for comparison.
            return try JSONSerialization.data(withJSONObject: dictionary, options: .sortedKeys)
        }

        if Set(lockfileContentsWeCareAbout).count > 1 {
            throw Error.packageLockfilesHaveDifferentContents(paths: lockfilePaths)
        }
    }

    private func loadDataFromFile(at path: String) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: .init(filePath: path))
        return data
    }

    private func loadUTF8StringFromFile(at path: String) async throws -> String {
        let data = try await loadDataFromFile(at: path)
        return try String(data: data, encoding: .utf8)
    }
}

@available(macOS 14, *)
struct SpecCoverage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print information about which spec points are implemented",
        discussion: "You can set the GITHUB_TOKEN environment variable to provide a GitHub authentication token to use when fetching the latest commit.",
    )

    @Option(help: "The SHA of the spec commit to use")
    var specCommitSHA: String?

    enum Error: Swift.Error {
        case unexpectedStatusCodeLoadingCommit(Int)
        case unexpectedStatusCodeLoadingSpec(Int)
        case conformanceToNonexistentSpecPoints(specPointIDs: [String])
        case couldNotFindTestTarget
        case malformedSpecOneOfTag
        case specUntestedTagMissingComment
        case specNotApplicableTagMissingComment
        case specOneOfIncorrectTotals(specPointID: String, coverageTagTotals: [Int], actualTotal: Int)
        case specOneOfIncorrectIndices(specPointID: String, coverageTagIndices: [Int], expectedIndices: [Int])
        case multipleConformanceTagTypes(specPointID: String, types: [String])
    }

    /**
     * A representation of the chat features spec Textile file.
     */
    private struct SpecFile {
        struct SpecPoint: Identifiable {
            var id: String
            var isTestable: Bool

            init?(specLine: String) {
                // example line that corresponds to a testable spec point:
                // ** @(CHA-RS4b)@ @[Testable]@ Room status update events must contain the previous room status.
                // (This `Testable` is a convention that's being used only in the Chat spec)

                let specPointLineRegex = /^\*+ @\((.*?)\)@( @\[Testable\]@ )?/

                // swiftlint:disable:next force_try
                guard let match = try! specPointLineRegex.firstMatch(in: specLine) else {
                    return nil
                }

                id = String(match.output.1)
                isTestable = match.output.2 != nil
            }
        }

        var specPoints: [SpecPoint]

        init(fileContents: String) {
            specPoints = fileContents.split(whereSeparator: \.isNewline).compactMap { line in
                SpecPoint(specLine: String(line))
            }
        }
    }

    /**
     * A tag, extracted from a comment in the SDK's test code, which indicates conformance to a spec point, as described in the "Attributing tests to a spec point" section of `CONTRIBUTING.md`.
     */
    private struct ConformanceTag {
        enum `Type` {
            case spec(comment: String?)
            case specOneOf(index: Int, total: Int, comment: String?)
            case specPartial(comment: String?)
            case specUntested(comment: String)
            case specNotApplicable(comment: String)

            enum Case {
                case spec
                case specOneOf
                case specPartial
                case specUntested
                case specNotApplicable
            }

            var `case`: Case {
                switch self {
                case .spec:
                    .spec
                case .specOneOf:
                    .specOneOf
                case .specPartial:
                    .specPartial
                case .specUntested:
                    .specUntested
                case .specNotApplicable:
                    .specNotApplicable
                }
            }
        }

        var type: `Type`
        var specPointID: String

        init?(sourceLine: String) throws {
            let conformanceTagSourceLineRegex = /^\s+\/\/ @spec(OneOf|Partial|Untested|NotApplicable)?(?:\((\d)?\/(\d)?\))? (.*?)(?: - (.*))?$/

            guard let match = try conformanceTagSourceLineRegex.firstMatch(in: sourceLine) else {
                return nil
            }

            specPointID = String(match.output.4)

            let comment: String? = if let capture = match.output.5 {
                String(capture)
            } else {
                nil
            }

            switch match.output.1 {
            case nil:
                type = .spec(comment: comment)
            case "OneOf":
                guard let indexString = match.output.2, let index = Int(indexString), let totalString = match.output.3, let total = Int(totalString) else {
                    throw Error.malformedSpecOneOfTag
                }
                type = .specOneOf(index: index, total: total, comment: comment)
            case "Partial":
                type = .specPartial(comment: comment)
            case "Untested":
                guard let comment else {
                    throw Error.specUntestedTagMissingComment
                }
                type = .specUntested(comment: comment)
            case "NotApplicable":
                guard let comment else {
                    throw Error.specNotApplicableTagMissingComment
                }
                type = .specNotApplicable(comment: comment)
            default:
                preconditionFailure("Incorrect assumption when reading regex captures")
            }
        }
    }

    private struct CoverageReport {
        struct Summary {
            var specPointCount: Int
            var testableSpecPointCount: Int
            private var specPointCountsByCoverageLevel: [CoverageLevel: Int]

            init(specPointCount: Int, testableSpecPointCount: Int, specPointCoverages: [SpecPointCoverage]) {
                self.specPointCount = specPointCount
                self.testableSpecPointCount = testableSpecPointCount

                specPointCountsByCoverageLevel = Dictionary(grouping: specPointCoverages, by: \.coverageLevel)
                    .mapValues(\.count)
                for coverageLevel in CoverageLevel.allCases where specPointCountsByCoverageLevel[coverageLevel] == nil {
                    specPointCountsByCoverageLevel[coverageLevel] = 0
                }
            }

            func specPointCountForCoverageLevel(_ coverageLevel: CoverageLevel) -> Int {
                guard let count = specPointCountsByCoverageLevel[coverageLevel] else {
                    preconditionFailure("Missing key \(coverageLevel)")
                }
                return count
            }
        }

        var summary: Summary

        /**
         * One per testable spec point.
         */
        var testableSpecPointCoverages: [SpecPointCoverage]

        /**
         * The IDs of spec points that are not marked as Testable but which have a conformance tag. We'll emit a warning for these, because it might mean that the spec point they refer to has been replaced or deleted; might need to re-think this approach if it turns out there are other good reasons for testing non-testable points).
         */
        var nonTestableSpecPointIDsWithConformanceTags: Set<String>

        enum CoverageLevel: CaseIterable {
            case tested
            case partiallyTested
            case implementedButDeliberatelyNotTested
            case notTested
            case notApplicable
        }

        struct SpecPointCoverage {
            var specPointID: String
            var coverageLevel: CoverageLevel
            var comments: [String]
        }

        static func generate(specFile: SpecFile, conformanceTags: [ConformanceTag]) throws -> CoverageReport {
            let conformanceTagsBySpecPointID = Dictionary(grouping: conformanceTags, by: \.specPointID)

            // 1. Check that all of the conformance tags correspond to actual spec points.
            let invalidSpecPointIDs = Set(conformanceTagsBySpecPointID.keys).subtracting(specFile.specPoints.map(\.id))
            if !invalidSpecPointIDs.isEmpty {
                throw Error.conformanceToNonexistentSpecPoints(specPointIDs: invalidSpecPointIDs.sorted())
            }

            // 2. Find any conformance tags for non-testable spec points (see documentation of the `nonTestableSpecPointIDsWithConformanceTags` property for motivation).
            let specPointsByID = Dictionary(grouping: specFile.specPoints, by: \.id)

            var nonTestableSpecPointIDsWithConformanceTags: Set<String> = []
            for conformanceTag in conformanceTags {
                let specPointID = conformanceTag.specPointID
                let specPoint = specPointsByID[specPointID]!.first!
                if !specPoint.isTestable {
                    nonTestableSpecPointIDsWithConformanceTags.insert(specPointID)
                }
            }

            // 3. Validate the spec coverage tags, and determine the coverage of each testable spec point.
            let testableSpecPoints = specFile.specPoints.filter(\.isTestable)
            let specPointCoverages = try testableSpecPoints.map { specPoint in
                let conformanceTagsForSpecPoint = conformanceTagsBySpecPointID[specPoint.id, default: []]
                return try generateCoverage(for: specPoint, conformanceTagsForSpecPoint: conformanceTagsForSpecPoint)
            }

            return .init(
                summary: .init(
                    specPointCount: specFile.specPoints.count,
                    testableSpecPointCount: testableSpecPoints.count,
                    specPointCoverages: specPointCoverages,
                ),
                testableSpecPointCoverages: specPointCoverages,
                nonTestableSpecPointIDsWithConformanceTags: nonTestableSpecPointIDsWithConformanceTags,
            )
        }

        /// Validates the spec coverage tags for this spec point, and determines its coverage.
        private static func generateCoverage(for specPoint: SpecFile.SpecPoint, conformanceTagsForSpecPoint: [ConformanceTag]) throws -> SpecPointCoverage {
            // Calculated data to be used in output
            var coverageLevel: CoverageLevel?
            var comments: [String] = []

            // Bookkeeping data for validation of conformance tags
            var specOneOfDatas: [(index: Int, total: Int)] = []
            var conformanceTagTypeCases: Set<ConformanceTag.`Type`.Case> = []

            for conformanceTag in conformanceTagsForSpecPoint {
                // We only make use of the comments that explain why something is untested or partially tested.
                switch conformanceTag.type {
                case .spec:
                    coverageLevel = .tested
                case let .specOneOf(index: index, total: total, _):
                    coverageLevel = .tested
                    specOneOfDatas.append((index: index, total: total))
                case let .specPartial(comment: comment):
                    coverageLevel = .partiallyTested
                    if let comment {
                        comments.append(comment)
                    }
                case let .specUntested(comment: comment):
                    coverageLevel = .implementedButDeliberatelyNotTested
                    comments.append(comment)
                case let .specNotApplicable(comment: comment):
                    coverageLevel = .notApplicable
                    comments.append(comment)
                }

                conformanceTagTypeCases.insert(conformanceTag.type.case)
            }

            // Before returning, we validate the conformance tags for this spec point:

            // 1. Check we don't have more than one type of conformance tag for this spec point.
            if conformanceTagTypeCases.count > 1 {
                throw Error.multipleConformanceTagTypes(
                    specPointID: specPoint.id,
                    types: conformanceTagTypeCases.map { "\($0)" },
                )
            }

            // 2. Validate the data attached to the @specOneOf(m/n) conformance tags.
            if !specOneOfDatas.isEmpty {
                // Do the totals stated in the tags match the number of tags?
                let coverageTagTotals = specOneOfDatas.map(\.total)
                if !(coverageTagTotals.allSatisfy { $0 == specOneOfDatas.count }) {
                    throw Error.specOneOfIncorrectTotals(
                        specPointID: specPoint.id,
                        coverageTagTotals: specOneOfDatas.map(\.total),
                        actualTotal: specOneOfDatas.count,
                    )
                }

                // Are the indices as expected?
                let coverageTagIndices = specOneOfDatas.map(\.index).sorted()
                let expectedIndices = Array(1 ... specOneOfDatas.count)
                if coverageTagIndices != expectedIndices {
                    throw Error.specOneOfIncorrectIndices(
                        specPointID: specPoint.id,
                        coverageTagIndices: coverageTagIndices,
                        expectedIndices: expectedIndices,
                    )
                }
            }

            return SpecPointCoverage(
                specPointID: specPoint.id,
                coverageLevel: coverageLevel ?? .notTested,
                comments: comments,
            )
        }
    }

    private struct CoverageReportViewModel {
        struct SummaryViewModel {
            var specContentsMessage: String
            var table: String

            init(summary: CoverageReport.Summary) {
                specContentsMessage = "There are \(summary.specPointCount) spec points, \(summary.testableSpecPointCount) of which are marked as testable."

                let headers = ["Coverage level", "Number of spec points", "Percentage of testable spec points"]

                let percentageFormatter = NumberFormatter()
                percentageFormatter.numberStyle = .percent
                percentageFormatter.minimumFractionDigits = 1
                percentageFormatter.maximumFractionDigits = 1

                let rows = CoverageReport.CoverageLevel.allCases.map { coverageLevel in
                    let specPointCount = summary.specPointCountForCoverageLevel(coverageLevel)

                    return [
                        CoverageReportViewModel.descriptionForCoverageLevel(coverageLevel),
                        String(specPointCount),
                        percentageFormatter.string(from: NSNumber(value: Double(specPointCount) / Double(summary.testableSpecPointCount)))!,
                    ]
                }

                // swiftlint:disable:next force_try
                table = try! Table(data: [headers] + rows).table()
            }
        }

        var summary: SummaryViewModel
        var warningMessages: [String]
        var specPointsTable: String

        init(report: CoverageReport) {
            warningMessages = []
            if !report.nonTestableSpecPointIDsWithConformanceTags.isEmpty {
                warningMessages.append("Warning: The tests have conformance tags for the following non-Testable spec points: \(Array(report.nonTestableSpecPointIDsWithConformanceTags).sorted().joined(separator: ", ")). Have these spec points been deleted or replaced?")
            }

            let headers = ["Spec point ID", "Coverage level", "Comments"]

            let rows = report.testableSpecPointCoverages.map { coverage in
                // TODO: https://github.com/ably-labs/ably-chat-swift/issues/94 - Improve the output of comments. The Table library doesn't:
                //
                // 1. offer the ability to wrap long lines
                // 2. handle multi-line strings
                //
                // so I'm currently just combining all the comments into a single line and then truncating this line.
                let comments = coverage.comments.joined(separator: ",")

                let truncateCommentsToLength = 80
                let truncatedComments = comments.count > truncateCommentsToLength ? comments.prefix(truncateCommentsToLength - 1) + "…" : comments

                return [
                    coverage.specPointID,
                    Self.descriptionForCoverageLevel(coverage.coverageLevel),
                    truncatedComments,
                ]
            }

            // swiftlint:disable:next force_try
            specPointsTable = try! Table(data: [headers] + rows).table()

            summary = .init(summary: report.summary)
        }

        static func descriptionForCoverageLevel(_ coverageLevel: CoverageReport.CoverageLevel) -> String {
            switch coverageLevel {
            case .tested:
                "Tested"
            case .partiallyTested:
                "Partially tested"
            case .implementedButDeliberatelyNotTested:
                "Implemented, not tested"
            case .notTested:
                "Not tested"
            case .notApplicable:
                "Not applicable"
            }
        }
    }

    mutating func run() async throws {
        let branchName = "main"

        let specCommitSHA: String
        if let specCommitSHAOption = self.specCommitSHA {
            print("Using forced spec commit (\(specCommitSHAOption.prefix(7))).\n")
            specCommitSHA = specCommitSHAOption
        } else {
            specCommitSHA = try await fetchLatestSpecCommitSHAForBranchName(branchName)
            print("Using latest spec commit (\(specCommitSHA.prefix(7))) from branch \(branchName).\n")
        }

        let specFile = try await loadSpecFile(forCommitSHA: specCommitSHA)
        let conformanceTags = try await fetchConformanceTags()

        let report = try CoverageReport.generate(specFile: specFile, conformanceTags: conformanceTags)

        let reportViewModel = CoverageReportViewModel(report: report)
        print(reportViewModel.summary.specContentsMessage + "\n")
        print((reportViewModel.warningMessages + [""]).joined(separator: "\n"))
        print(reportViewModel.summary.table)
        print(reportViewModel.specPointsTable)
    }

    /**
     * The response from GitHub's ["get a commit" endpoint](https://docs.github.com/en/rest/commits/commits?apiVersion=2022-11-28#get-a-commit).
     */
    private struct GitHubCommitResponseDTO: Codable {
        var sha: String
    }

    private func fetchLatestSpecCommitSHAForBranchName(_ branchName: String) async throws -> String {
        // https://docs.github.com/en/rest/commits/commits?apiVersion=2022-11-28#get-a-commit
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/ably/specification/commits/\(branchName)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let gitHubToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            print("Using GitHub token from GITHUB_TOKEN environment variable.")
            request.setValue("Bearer \(gitHubToken)", forHTTPHeaderField: "Authorization")
        }

        let (commitData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            preconditionFailure("Expected an HTTPURLResponse")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw Error.unexpectedStatusCodeLoadingCommit(httpResponse.statusCode)
        }

        let responseDTO = try JSONDecoder().decode(GitHubCommitResponseDTO.self, from: commitData)
        return responseDTO.sha
    }

    private func loadSpecFile(forCommitSHA commitSHA: String) async throws -> SpecFile {
        let specFileURL = URL(string: "https://raw.githubusercontent.com/ably/specification/\(commitSHA)/textile/chat-features.textile")!
        let (specData, response) = try await URLSession.shared.data(from: specFileURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            preconditionFailure("Expected an HTTPURLResponse")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw Error.unexpectedStatusCodeLoadingSpec(httpResponse.statusCode)
        }

        let specContents: String = try String(data: specData, encoding: .utf8)

        return SpecFile(fileContents: specContents)
    }

    private func fetchConformanceTags() async throws -> [ConformanceTag] {
        let testSourceFilePaths = try await fetchTestSourceFilePaths()
        let testSources = try await withThrowingTaskGroup(of: String.self) { group in
            for testSourceFilePath in testSourceFilePaths {
                group.addTask {
                    let (data, _) = try await URLSession.shared.data(from: testSourceFilePath)
                    return try String(data: data, encoding: .utf8)
                }
            }

            return try await Array(group)
        }

        return try testSources.flatMap { testSource in
            try testSource.split(whereSeparator: \.isNewline).compactMap { sourceLine in
                try ConformanceTag(sourceLine: String(sourceLine))
            }
        }
    }

    /**
     * The result of invoking `swift package describe`.
     */
    private struct PackageDescribeOutput: Codable {
        /**
         * The absolute path of the directory containing the `Package.swift` file.
         */
        var path: String

        struct Target: Codable {
            var name: String

            /**
             * The path of this target's sources, relative to ``PackageDescribeOutput/path``.
             */
            var path: String

            /**
             * The paths of each of this target's sources, relative to ``path``.
             */
            var sources: [String]
        }

        var targets: [Target]
    }

    /**
     * Fetches the absolute file URLs of all of the source files for the SDK's tests.
     */
    private func fetchTestSourceFilePaths() async throws -> [URL] {
        let packageDescribeOutputData = try await ProcessRunner.runAndReturnStdout(
            executableName: "swift",
            arguments: ["package", "describe", "--type", "json"],
        )

        let packageDescribeOutput = try JSONDecoder().decode(PackageDescribeOutput.self, from: packageDescribeOutputData)

        guard let testTarget = (packageDescribeOutput.targets.first { $0.name == "AblyLiveObjectsTests" }) else {
            throw Error.couldNotFindTestTarget
        }

        let targetSourcesAbsoluteURL = URL(filePath: packageDescribeOutput.path).appending(path: testTarget.path)
        return testTarget.sources.map { sourceRelativePath in
            targetSourcesAbsoluteURL.appending(component: sourceRelativePath)
        }
    }
}

@available(macOS 14, *)
struct BuildDocumentation: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build documentation for the library",
    )

    mutating func run() async throws {
        // For now, this is intended to just perform some validation of the documentation comments. We'll generate HTML output in https://github.com/ably/ably-chat-swift/issues/2.

        try await ProcessRunner.run(
            executableName: "swift",
            arguments: [
                "package",
                "generate-documentation",

                "--product", "AblyLiveObjects",

                // Useful because it alerts us about links to nonexistent symbols.
                "--warnings-as-errors",

                // Outputs the following information about which symbols have been documented and to what level of detail:
                //
                // - a table at the end of the CLI output
                // - as a JSON file in ./.build/plugins/Swift-DocC/outputs/AblyLiveObjects.doccarchive/documentation-coverage.json
                //
                // I do not yet know how to make use of these (there's all sorts of unexpected symbols that we didn't directly declare there, e.g. `compactMap(_:)`), but maybe it'll be a bit helpful still.
                "--experimental-documentation-coverage",

                // Increases the detail level of the aforementioned coverage table in CLI output.
                "--coverage-summary-level", "detailed",
            ],
        )
    }
}
