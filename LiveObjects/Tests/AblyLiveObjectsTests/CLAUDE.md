# Testing guidelines

- Use the Swift Testing framework (`import Testing`), not XCTest.
- Do not use `fatalError` in response to a test expectation failure; use Swift Testing's `#require` macro instead.
- Only add labels to test cases or suites when the label differs from the name of the suite `struct` or test method.
- Follow the guidelines under "Attributing tests to a spec point" in `CONTRIBUTING.md` to tag unit tests with the relevant specification points. Follow the exact comment format described there. Pay particular attention to the difference between `@spec` and `@specPartial`, and do not write `@spec` multiple times for the same specification point.
- Add comments explaining when some piece of test data is not important for the scenario being tested.
- Run the tests to check they pass.
- When importing these modules in test code:
  - Ably: `import AblyPubSubDevice`
  - AblyLiveObjects: `@testable import AblyLiveObjects`
  - `_AblyPluginSupportPrivate`: `import _AblyPluginSupportPrivate` (not `internal import`)
- When you need to pass a logger to internal components in tests, pass `TestLogger()`.
- When you need to unwrap an optional value in tests, use `#require` instead of `guard let`.
- When creating `testsOnly_` property declarations, do not write generic comments describing them; their meaning is already well understood.
- Place unit test suites in `Unit/`; place integration suites in `Integration/` and give them `.tags(.integration)` (the tag, via the UnitTests test plan's `skippedTags`, is what excludes them from the fast unit loop — the directory is the human-readable signal).
