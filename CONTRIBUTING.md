# Contributing

In this repository the `main` branch contains the latest development version of the Ably SDK. All development (bug fixing, feature implementation, etc.) is done against the `main` branch, which you should branch from whenever you'd like to make modifications. Here's the steps to follow when contributing to this repository.

 - Fork it
 - Install Carthage: `brew install carthage`
 - Install gems: `bundle install`
 - Setup or update your machine by running `make update`
 - Create your feature branch from `main` (`git checkout main && git checkout -b my-new-feature-branch`)
 - Commit your changes (`git commit -am 'Add some feature'`)
 - Ensure you have added suitable tests and the test suite is passing
 - Push to the branch (`git push origin my-new-feature-branch`)
 - Create a new Pull Request

Releases of the Ably SDK built by the sources in this repository are tagged with their [semantic version](http://semver.org/) numbers.

## Development Flow

When you first clone the repository then you will need to run `make update` in order to
bring in Git submodules and Carthage dependencies.

Code can then be modified, built and tested by loading [Ably.xcworkspace](Ably.xcworkspace) in your Xcode IDE.

The Xcode project relies upon dependencies resolved by Carthage.
If you make changes to the [Cartfile](Cartfile) then you will need to run `make update_carthage_dependencies`
from the command line and then do a clean rebuild in Xcode.

Changes made to dependencies in the [Cartfile](Cartfile) need to be reflected in
[Ably.podspec](Ably.podspec) and vice-versa.

## Adding new Objective-C files to the SDK

The steps below are for the core SDK — the `Ably` target, whose sources live in `Source/`. The `AblyPubSubDevice` target (`PubSubDevice/`) is laid out differently: its public headers go in `PubSubDevice/include/AblyPubSubDevice/` and its implementations directly in `PubSubDevice/`, there is no umbrella header to add an `#import` to, and it is absent from `Ably.xcodeproj`. SwiftPM globs the directory and generates the module map, so a new file there needs no other change.

### Public header (`.h`) files

These are the header files that form the public interface of the SDK.

1. Put `.h` file in directory `Source/include/Ably`.
1. Add `#import` to one of the following umbrella header files:
   - `Source/include/Ably/AblyPublic.h` if the API contained in this header is intended for general use.
   - `Source/include/Ably/AblyInternal.h` if the API contained in this header is intended for use only by Ably-authored SDKs and should not be included in the Jazzy-generated documentation.
1. Add to the Xcode project `Ably.xcodeproj` — you need to add it as a Public header to all three SDK targets (Ably-iOS, Ably-macOS, Ably-tvOS).

### Private header (`.h`) files

These are the header files that form the internal interface of the SDK.

1. Put `.h` file in directory `Source/PrivateHeaders/Ably`.
1. Add `header` declaration to the `Private` module in module map files `Source/Ably.modulemap` and `Source/include/module.modulemap`.
1. Add to the Xcode project `Ably.xcodeproj` — you need to add it as a Private header to all three SDK targets (Ably-iOS, Ably-macOS, Ably-tvOS).

### Implementation (`.m`) files

1. Put `.m` file in directory `Source`.
1. Add to the Xcode project `Ably.xcodeproj` — you need to add it to all three SDK targets (Ably-iOS, Ably-macOS, Ably-tvOS).

## Running tests

To run tests, do any of the following:

- use the Xcode UI to run on any platform
- run `swift test` to run on your Mac
- run `make test_[iOS|tvOS|macOS]` to run on any platform

The `make test_*` commands are used by CI and expect you to have a simulator device of a specific model and OS version. See [`Fastfile`](./fastlane/Fastfile) for these values. If you don't have a matching simulator, you can create one using `simctl`. For example, `xcrun simctl create "iPhone 12 (14.4)" "iPhone 12" "com.apple.CoreSimulator.SimRuntime.iOS-14-4"`.

### Test targets

`swift test` builds and runs every test target in the package:

| Target | Path | Contents |
| --- | --- | --- |
| `AblyTests` | `Test/AblyTests` | Swift tests for the core SDK |
| `AblyTestsObjC` | `Test/AblyTestsObjC` | Objective-C tests for the core SDK |
| `UTS` | `Test/UTS` | Universal Test Suite, derived from the language-neutral specs in the [`specification`](https://github.com/ably/specification) repository — including the ported LiveObjects `objects` unit specs under `unit/objects/`. Its `objects` suites link `AblyLiveObjects`, which is why the Fastlane lanes raise their deployment target — see [Supported OS versions](#supported-os-versions) |
| `AblyLiveObjectsTests` | `LiveObjects/Tests/AblyLiveObjectsTests` | LiveObjects native unit and integration tests |

To run just one of them, filter by module name — for example `swift test --filter 'AblyLiveObjectsTests\.'`.

Every one of these targets selects its files by directory: SwiftPM globs the target's `path`, and the test plans name whole targets rather than individual tests. A new test file is therefore picked up automatically, with no change to `Package.swift`, to any test plan, or to any CI workflow. Note in particular that the ported LiveObjects `objects` UTS unit specs live inside the `UTS` target (under `Test/UTS/unit/objects/`), alongside the rest of the Universal Test Suite, so they run as part of that target rather than `AblyLiveObjectsTests`.

Both `AblyLiveObjectsTests` and the `objects` UTS suites also depend on a shared test-support target, `AblyLiveObjectsTesting` (`Test/AblyLiveObjectsTesting`), imported with `@testable` for internal-access test helpers and mocks. It is a regular (non-test) target, so it is compiled but never run on its own — which is why it is not listed above.

In CI:

- [`integration-test.yaml`](.github/workflows/integration-test.yaml) runs the Fastlane lanes with `suite:sdk`, which builds the `ably-cocoa` scheme against [`Test/Ably.xctestplan`](Test/Ably.xctestplan) and passes `-skip-testing:UTS`, so it covers `AblyTests` and `AblyTestsObjC` on all three platforms.
- [`uts.yaml`](.github/workflows/uts.yaml) runs the same lanes with `suite:uts` (`-only-testing:UTS`), covering the `UTS` target alone on all three platforms. It is the **only** place CI executes that target's tests, and therefore where the ported LiveObjects `objects` unit specs run.

  Each platform runs twice, once per entry point. The `core` leg uses the default `Ably` test plan, and builds clients with `ARTRealtime(options:)`. The `device` leg uses [`Test/UTSDevice.xctestplan`](Test/UTSDevice.xctestplan), whose configuration sets `UTS_SIDE=device`, and builds them with `PubSubDevice.createClient(options:)` instead. [`Test/UTS/README.md`](Test/UTS/README.md) documents the seam.

  Test plans are declared in `.swiftpm/xcode/xcshareddata/xcschemes/ably-cocoa.xcscheme`. A plan is also how an environment variable reaches the test process under `xcodebuild`, where neither a plain export nor a `TEST_RUNNER_`-prefixed build setting does. Under `swift test` no plan is needed, because the test binary inherits the environment.

  The two are separate workflows because the UTS is primarily a *unit* suite, so grouping it under "Integration Test" misnamed it; splitting them also means a UTS failure is distinguishable from an `AblyTests` one without opening a log, and either can be dispatched or re-run without the other's sandbox time. Between them they cover the test plan exactly once. A lane invoked without `suite:` still runs the whole plan, which is what a local `bundle exec fastlane test_macOS` does.
- [`liveobjects.yaml`](.github/workflows/liveobjects.yaml) runs `AblyLiveObjectsTests` three ways: `swift test --filter 'AblyLiveObjectsTests\.'`, the `AblyLiveObjects` scheme via `LiveObjects/BuildTool`, and the code-coverage job. These are not equivalent — `BuildTool test-library` uses the scheme's default `AllTests` plan, whereas the coverage job passes `-testPlan UnitTests`, which skips anything tagged `.integration`. It does **not** execute the `UTS` target's tests (that's `uts.yaml`'s job, above), though its SPM job still compiles the whole package — `UTS` included — under `-warnings-as-errors`.
- [`check-spm.yaml`](.github/workflows/check-spm.yaml) only builds; it runs no tests.

## Plugins

ably-cocoa allows users to pass in Ably-authored plugins via the `ARTClientOptions.plugins` property. These plugins extend the functionality of the SDK. For more information on the implementation of the plugins mechanism, see [`Docs/plugins.md`](Docs/plugins.md).

## LiveObjects

The LiveObjects plugin lives in [`LiveObjects/`](LiveObjects) and is vended as this package's `AblyLiveObjects` product. It has its own [`CONTRIBUTING.md`](LiveObjects/CONTRIBUTING.md) covering setup, tests, linting and coding guidelines; read that before working on plugin code.

Two things about the plugin affect the repository as a whole, and so are documented here rather than there.

### Supported OS versions

The package's declared platform floor in [`Package.swift`](Package.swift) is that of the core SDK: macOS 10.11, iOS 9, tvOS 10. LiveObjects requires **macOS 11, iOS 14, tvOS 14** — the versions mandated by [ADR-114](https://ably.atlassian.net/wiki/spaces/ENG/pages/3199500291/ADR-114+Increase+Cocoa+SDK+minimum+supported+version+to+iOS+14) and the [RFC](https://ably.atlassian.net/wiki/spaces/SDKs/pages/2986147844/RFC+Deprecate+iOS+13+support+for+ably-cocoa) behind it, which the core SDK has not yet adopted.

SwiftPM platform requirements are package-wide, so a single package hosts both floors by annotating every top-level declaration in `LiveObjects/Sources/AblyLiveObjects` with:

```swift
@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
```

Don't write these annotations by hand. After adding a declaration, run [`Scripts/annotate-liveobjects-availability.py`](Scripts/annotate-liveobjects-availability.py) from the repo root:

```sh
python3 Scripts/annotate-liveobjects-availability.py
```

It annotates every unannotated top-level declaration under `LiveObjects/Sources/AblyLiveObjects` (pass another directory as its sole argument to override that), and is idempotent — running it on an already-annotated tree changes nothing.

CI enforces this two ways: it runs the script and fails on a non-empty diff, which covers all top-level declarations; and it separately builds the target with `-require-explicit-availability=error`, which covers the public ones.

Test code cannot use the same mechanism, because swift-testing's `@Suite` macro rejects types marked `@available`. Instead, any test build that links `AblyLiveObjects` raises its own deployment target to the plugin's floor. Two places do this today, both by passing `IPHONEOS_DEPLOYMENT_TARGET=14.0` and `TVOS_DEPLOYMENT_TARGET=14.0` to `xcodebuild`:

- `LiveObjects/BuildTool` (`testDeploymentTargetOverrides`), for the invocations that build and run `AblyLiveObjectsTests`.
- [`fastlane/Fastfile`](fastlane/Fastfile), in the `xcargs` shared by the integration-test lanes, because the `UTS` target links `AblyLiveObjects` too. Without it the harness fails on the iOS and tvOS simulators with errors of the form `'…' is only available in iOS 14.0 or newer`.

Neither overrides macOS: xcodebuild raises the macOS test bundle's floor well above the package's of its own accord, and the test code relies on that. Both affect the test build only — the package's declared platform floor and the shipped artifacts are unchanged.

If you add another `xcodebuild`-based path that compiles a test target linking `AblyLiveObjects`, it will need the same override. Test code that needs a newer OS than the plugin's floor must still carry its own `@available` — for example `Subscriber.swift`, whose parameter packs require iOS/tvOS 17, along with every test that uses it.

### Distribution

`AblyPubSubDevice` and `AblyLiveObjects` are available **via Swift Package Manager only**. CocoaPods and Carthage consumers receive the core SDK alone, so a release tag does not deliver the same set of products to every channel:

| Channel | `AblyPubSubCore` | `AblyPubSubDevice` | `AblyLiveObjects` |
| --- | --- | --- | --- |
| Swift Package Manager | yes | yes | yes |
| CocoaPods | yes (as the `Ably` pod) | no | no |
| Carthage | yes | no | no |

> The `AblyPubSubCore` product's module is named `Ably` and its classes carry the `ART` prefix, so
> consumers reach the core as `import Ably` / `#import <Ably/…>` whichever channel they install it
> from — which is why the CocoaPods pod and the Carthage framework are both named `Ably`.

The two are SPM-only for different reasons. Nothing about `AblyPubSubDevice` resists the other channels: it is a plain Objective-C target over the core, with the same platform floor and no plugin machinery, so shipping it as a pod would mean adding a podspec and Carthage targets rather than removing an obstacle. `AblyLiveObjects` is the constrained one, and deliberately so rather than by omission — four separate things would each have to change to lift it:

- [`Ably.podspec`](Ably.podspec)'s `source_files` covers `Source/` only, so neither `LiveObjects/` nor `_AblyPluginSupportPrivate/` ships in the pod; and `Ably.xcodeproj`, which Carthage builds, contains no LiveObjects or plugin-support targets.
- `ABLY_SUPPORTS_PLUGINS` is defined only in `Package.swift`. Without it the plugin hook points — `ARTClientOptions.plugins` and the plumbing in `ARTRealtimeChannel.m`, `ARTRealtime.m` and `ARTJsonLikeEncoder.m` — are compiled out. It is a compile-time define on the core target, so enabling it would enable it for every CocoaPods and Carthage consumer, in a configuration that has never been built or tested.
- `_AblyPluginSupportPrivate` is a target but not a product, so SPM structurally prevents an external consumer from depending on it. Neither CocoaPods nor Carthage has an equivalent to that distinction: any module the plugin can import is a module the consumer can import. Private spec repositories don't help — they restrict who may fetch an artifact, not what is importable once fetched, and a public `Ably` pod cannot depend on a privately hosted one without breaking `pod install` for everyone.
- The podspec declares iOS/tvOS 10, macOS 10.12 and Swift 5.0, whereas LiveObjects needs the floors above and the Swift 6 language mode.

Note that OS version requirements are *not* among these reasons: per-declaration `@available` lets one package host components with different floors, which is why the plugin no longer needs a repository of its own (see [`Docs/plugins.md`](Docs/plugins.md) on how this supersedes ADR-128).

Revisit this if a customer on CocoaPods asks for LiveObjects. CocoaPods would be the only candidate — its file lists are globs, whereas `Ably.xcodeproj` enumerates every file individually and is maintained by hand, which would make Carthage support a permanent per-file cost.

## Coding standards

- In Objective-C code, use `art_dispatch_sync` and `art_dispatch_async` instead of `dispatch_sync` and `dispatch_async`, for more debuggable handling of the case in which we accidentally submit to a `nil` queue.

### Time-related operations

All time-dependent code in ably-cocoa goes through the injectable `ARTTimeProvider` abstraction (declared in `Source/PrivateHeaders/Ably/ARTTimeProvider.h`). This indirection allows the Universal Test Suite to install a single fake-time implementation that controls every clock-dependent code path across both ably-cocoa and any Ably-authored plugins.

New code MUST obtain time and scheduling primitives from an injected `id<ARTTimeProvider>` rather than calling system primitives directly. In particular:

- Don't call `[NSDate date]` (or `Date()` from Swift) directly. Use `[timeProvider wallClockNow]`.
- Don't call `clock_gettime_nsec_np`, `mach_continuous_time`, or similar continuous-clock primitives directly. Use `[timeProvider continuousClockNow]`, which returns an `id<ARTContinuousClockInstant>` that supports `isAfter:` and `addingDuration:`.
- Don't call `dispatch_after`, `NSTimer`, or `dispatch_source_set_timer` directly to run something after a delay. Use `[timeProvider scheduleAfter:queue:block:]`, which returns an `id<ARTSchedulerHandle>` that supports `cancel`.

Internal classes obtain their `ARTTimeProvider` by reading `options.testOptions.timeProvider` in their `-init` (the default value is an `ARTSystemTimeProvider`, backed by real system primitives) and stash it as an ivar, the same way the `logger` and the internal dispatch queue are passed in from the owning class. Downstream consumers (e.g. `ARTEventEmitter`) receive the provider as an init parameter from their owning class.

## Linting

Source files must comply with the rules defined in `.editorconfig` (enforced by CI).

Many text editors — including Xcode, if the "Prefer settings from .editorconfig files" setting is switched on — can automatically follow these rules.

To check compliance locally, install `editorconfig-checker` (`brew install editorconfig-checker`) and run:

```bash
make lint
```

## Release Process

### Versioning

The repository has a single version number, applied to everything it publishes. Since the LiveObjects plugin moved into this repository it no longer has a version of its own: the standalone [ably-liveobjects-swift-plugin](https://github.com/ably/ably-liveobjects-swift-plugin) package stopped at 0.4.1, and the first release of `AblyLiveObjects` from here carries this repository's next version number. There is no 0.x line to continue, and the plugin's [historical changelog](LiveObjects/CHANGELOG.md) is kept only for reference.

Because a shared version number implies more than it delivers, one thing is worth stating explicitly in release notes:

* **A tag does not mean the same thing on every channel.** CocoaPods and Carthage consumers receive only the core SDK (the `AblyPubSubCore` product, shipped as the `Ably` pod / `Ably.xcframework`); see [Distribution](#distribution). A release whose only change is to LiveObjects is a no-op for them, and the changelog entry should say so.

### Steps

For each release, the following needs to be done:

* Confirm that none of our `Package.swift` dependencies are specified using a fixed `.revision`. (The plugin-support library used to be the likeliest offender here; it is now the in-repo `_AblyPluginSupportPrivate` target rather than an external dependency, so it no longer needs its own release.)
* Create a new branch `release/x.x.x` (where `x.x.x` is the new version number) from the `main` branch
* Run `make bump_[major|minor|patch]` to bump the new version number. This will create a Git commit, push it to origin: `git push -u origin release/x.x.x`
* Go to [Github releases](https://github.com/ably/ably-cocoa/releases) and press the `Draft a new release` button. Choose your new branch as a target
* Press the `Choose a tag` dropdown and start typing a new tag, Github will suggest the `Create new tag x.x.x on publish` option. After you select it Github will unveil the `Generate release notes` button
* From the newly generated changes remove everything that doesn't make much sense to the library user
* Copy the final list of changes to the top of the `CHANGELOG.md` file. Modify as necessary to fit the existing format of this file
* Commit these changes and push to the origin `git add CHANGELOG.md && git commit -m "Update change log." && git push -u origin release/x.x.x`
* Make a pull request against `main` and await approval of reviewer(s)
* Once approved and/or any additional commits have been added, merge the PR (if you do this from Github's web interface then use the "Rebase and merge" option)
* After merging the PR, wait for all CI jobs for `main` to pass
* Publish your drafted release:
    * refer to previous releases for release notes format
    * attach to the release the prebuilt framework file (`Ably.framework.zip`) generated by Carthage – you can find this file in the `carthage-built-framework` artifact uploaded by the `check-pod` CI workflow
* Checkout `main` locally, pulling in changes using `git checkout main && git pull`. Make sure the new tag you need was created on publish
* Release an update for CocoaPods using `pod trunk push Ably.podspec --allow-warnings`. Details on this command, as well as instructions for adding other contributors as maintainers, are at [Getting setup with Trunk](https://guides.cocoapods.org/making/getting-setup-with-trunk.html) in the [CocoaPods Guides](https://guides.cocoapods.org/). This publishes the core SDK only — there is no LiveObjects pod
* Test the integration of the library in a Xcode project using Carthage and CocoaPods using the [installation guide](https://github.com/ably/ably-cocoa#installation-guide)
* Test that Swift Package Manager resolves the new tag, selecting the `AblyPubSubCore`, `AblyPubSubDevice` and `AblyLiveObjects` products
