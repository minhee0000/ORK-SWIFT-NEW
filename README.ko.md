# ORK-SWIFT-NEW

[English](README.md) | [한국어](README.ko.md)

Xcode 빌드 파이프라인에서 사용할 수 있는 Swift 소스 난독화 CLI입니다.

이 도구는 원본 프로젝트를 직접 바꾸지 않고, 복사된 소스 트리에서
`xcodebuild` 또는 `swift build` 전에 난독화를 수행하도록 설계했습니다.
프로젝트마다 제외할 폴더와 파일을 지정할 수 있고, seed 기반으로
결정적인 이름을 생성합니다. `--output`을 사용할 때는 `.build`, `.git`,
`build`, `DerivedData`, `tmp` 같은 빌드/캐시 디렉터리를 복사본에서
제외합니다.

구성 요소와 안전 모델은 [Docs/Architecture.md](Docs/Architecture.md)를
참고하세요.

## 기능

- seed 기반의 결정적 난독화 결과.
- 폴더, 경로, glob 스타일 generated 파일 제외 규칙.
- Swift symlink target 보존.
- Swift access-controlled import를 사용하는 디렉터리의 파일명 보존.
- 파일명, 타입명, 함수명 rename 전체를 JSON manifest로 기록.
- 커스텀 빌드 시스템에서 사용할 수 있는 library API.
- shell script와 CI release pipeline에서 사용할 수 있는 CLI.
- 임시 프로젝트 복사본에서 동작하는 Xcode build wrapper 예제.

## 난독화 범위

- `.swift` 파일 basename.
- 보수적으로 안전하다고 판단한 internal/private `struct`, `class`, `enum`,
  `actor` 이름.
- 보수적으로 안전하다고 판단한 `private`, `fileprivate func` 선언.
- 안전하게 rewrite 가능한 local call site.

타입/함수 rename pass는 런타임 민감성이나 모호성이 있는 Swift 코드를
의도적으로 스킵합니다.

- `@objc`, `@IBAction`, `@NSManaged`, `_cdecl`, `_silgen_name`,
  `_dynamicReplacement`, `@objcMembers`, `@main`.
- `public`, `open`, `dynamic`, `override`, exported type 선언.
- backticked name, nested type, 특수 entry point, unsafe overload,
  `CodingKeys`.
- `Combine.Subscription` 같은 qualified external type reference.
- 일반 direct call이 아닌 function reference.
- 문자열 literal 또는 interpolation 안에 등장하는 타입명/함수명.
- private overload signature와 argument label이 맞지 않는 call.
- 함수 body 내부의 same-name call처럼 type checking 후 다른 overload로
  해석될 수 있는 경우.

## 요구사항

- macOS 13 이상.
- Xcode command line tools.
- Swift 5.9 이상.

## 빌드와 테스트

```bash
swift build -c release
swift test
```

## CLI 사용법

도움말 출력:

```bash
swift run -c release ork-swift-new -- --help
```

소스 디렉터리에 실행:

```bash
swift run -c release ork-swift-new -- \
  --input /path/to/AppSources \
  --output /tmp/AppSources.obfuscated \
  --rename-files \
  --rename-types \
  --rename-private-functions \
  --exclude Security \
  --exclude "*.generated.swift" \
  --manifest /tmp/obfuscation-manifest.json \
  --seed "my-app-release"
```

임시 복사본에 직접 rewrite:

```bash
swift run -c release ork-swift-new -- \
  --input /tmp/MyAppCopy/MyApp \
  --in-place \
  --rename-files \
  --rename-types \
  --rename-private-functions \
  --manifest /tmp/ork-swift-new-manifest.json
```

## 실제 Before / After

아래 예시는 실제 SwiftPM fixture에 release binary를 실행한 뒤, 난독화된
output에서 `swift test`까지 통과한 결과입니다.

```bash
.build/release/ork-swift-new \
  --input /tmp/ork-type-rename-build \
  --output /tmp/ork-type-rename-obfuscated \
  --rename-files \
  --rename-types \
  --rename-private-functions \
  --manifest /tmp/ork-type-rename-manifest.json \
  --seed readme-before-after-example

swift test --package-path /tmp/ork-type-rename-obfuscated
```

실제 실행 요약:

| 항목 | 값 |
| --- | ---: |
| 분석한 Swift 파일 | 2 |
| 파일명 rename | 2 |
| 타입명 rename | 2 |
| 함수명 rename | 2 |
| 스킵된 타입 | 0 |
| 스킵된 함수 | 0 |
| 난독화 후 package test | Passed |

실제 manifest mapping:

| 종류 | Before | After |
| --- | --- | --- |
| File | `Sources/TypeRenameFixture/ProfileCoordinator.swift` | `Sources/TypeRenameFixture/S_4cf42fc62b35.swift` |
| File | `Tests/TypeRenameFixtureTests/TypeRenameFixtureTests.swift` | `Tests/TypeRenameFixtureTests/S_67d425ab347d.swift` |
| Type name | `ProfileCoordinator` | `T_f04922bb1f20` |
| Type name | `ProfileFactory` | `T_77f18701a822` |
| Function | `formatTitle` | `f_e9a307e3809f` |
| Function | `sanitize` | `f_fbb68bb3f18e` |

<table>
<tr>
<th>Before: <code>Sources/TypeRenameFixture/ProfileCoordinator.swift</code></th>
<th>After: <code>Sources/TypeRenameFixture/S_4cf42fc62b35.swift</code></th>
</tr>
<tr>
<td>
<pre><code class="language-swift">import Foundation

struct ProfileCoordinator {
    func buildTitle(for name: String) -> String {
        let sanitized = sanitize(name)
        return formatTitle(sanitized)
    }

    private func sanitize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTitle(_ value: String) -> String {
        "Profile: \(value)"
    }
}

struct ProfileFactory {
    static func makeTitle() -> String {
        let coordinator = ProfileCoordinator()
        return coordinator.buildTitle(for: " Example ")
    }
}</code></pre>
</td>
<td>
<pre><code class="language-swift">import Foundation

struct T_f04922bb1f20 {
    func buildTitle(for name: String) -> String {
        let sanitized = f_fbb68bb3f18e(name)
        return f_e9a307e3809f(sanitized)
    }

    private func f_fbb68bb3f18e(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func f_e9a307e3809f(_ value: String) -> String {
        "Profile: \(value)"
    }
}

struct T_77f18701a822 {
    static func makeTitle() -> String {
        let coordinator = T_f04922bb1f20()
        return coordinator.buildTitle(for: " Example ")
    }
}</code></pre>
</td>
</tr>
</table>

## Xcode Build Wrapper

`Examples/build-obfuscated-xcode.sh`는 Xcode 프로젝트를 임시 작업
디렉터리로 복사하고, 그 복사본 안에서 지정된 소스 폴더를 난독화한 뒤
`xcodebuild`를 실행합니다.

예시:

```bash
SCHEME_NAME=MyApp \
SOURCE_DIR=MyApp \
OBFUSCATION_EXCLUDES=$'Generated\nSecurity' \
./Examples/build-obfuscated-xcode.sh
```

주요 환경 변수:

- `SCHEME_NAME`: 필수 Xcode scheme.
- `SOURCE_DIR`: 복사된 프로젝트 안의 소스 폴더. 기본값은 `SCHEME_NAME`.
- `WORKSPACE_PATH`: 프로젝트 복사본 안의 workspace path. 기본값은
  `${SCHEME_NAME}.xcworkspace`.
- `PROJECT_PATH`: workspace를 쓰지 않을 때의 fallback project path.
- `OBFUSCATION_EXCLUDES`: newline으로 구분된 exclude pattern.
- `KEEP_OBFUSCATION_WORKDIR=1`: 빌드 후 임시 복사본을 삭제하지 않음.

## Exclude Pattern

exclude 규칙은 프로젝트에 종속되지 않도록 범용적으로 동작합니다.

- `Security`: 어느 위치든 path component가 `Security`인 항목을 스킵.
- `Features/Generated`: 해당 directory prefix를 스킵.
- `*.generated.swift`: basename 또는 relative path가 매칭되는 generated
  Swift 파일을 스킵.

기본 exclude:

```text
.build, .git, build, DerivedData, Pods, Package.swift, Package@swift-*.swift, main.swift, LinuxMain.swift, tmp, *.generated.swift
```

완전히 직접 제어하려면 `--no-default-excludes`를 사용하세요.

## 검증

아래 수치는 추정값이 아니라 release binary를 실제로 로컬에서 실행한
결과입니다.

`--rename-files`, `--rename-types`, `--rename-private-functions`를 켠 대형
공개 Swift codebase dry-run 결과:

| Repository | Swift 파일 | 파일 rename | 타입 rename | 함수 rename | 스킵된 타입 | 스킵된 함수 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DuckDuckGo-iOS | 1,197 | 697 | 1,114 | 1,107 | 1,041 | 344 |
| Nextcloud-iOS | 382 | 382 | 257 | 201 | 212 | 51 |
| Signal-iOS | 2,554 | 626 | 1,398 | 3,377 | 6,198 | 3,018 |
| WordPress-iOS | 3,384 | 3,176 | 2,547 | 2,967 | 3,780 | 1,208 |
| firefox-ios | 2,917 | 2,917 | 2,434 | 3,604 | 3,040 | 889 |
| mastodon-ios | 839 | 837 | 445 | 380 | 1,339 | 198 |
| sourcekit-lsp | 418 | 105 | 359 | 259 | 329 | 159 |
| swift-docc | 895 | 348 | 456 | 282 | 925 | 151 |
| swift-format | 250 | 205 | 157 | 166 | 141 | 83 |
| swift-package-manager | 1,197 | 998 | 537 | 519 | 2,136 | 323 |
| swift-protobuf | 474 | 466 | 122 | 188 | 7,594 | 46 |
| swift-syntax | 744 | 446 | 423 | 788 | 1,439 | 388 |
| **Total** | **15,251** | **11,203** | **10,249** | **13,838** | **28,174** | **6,858** |

대형 프로젝트 12개의 manifest는 모두 유효한 JSON으로 파싱되었습니다.

난독화된 SwiftPM output build는 swift-protobuf, swift-format, swift-syntax,
swift-docc, sourcekit-lsp, swift-package-manager에서 검증했습니다.

타입 rename은 난독화된 SwiftPM fixture에서도 검증했으며, rename된 source와
rename된 test target 모두 `swift test`를 통과했습니다.

`--rename-types`를 켠 추가 검증:

| 세트 | 프로젝트 | Swift 파일 | 파일 rename | 타입 rename | 함수 rename | 스킵된 타입 | 스킵된 함수 | 유효 manifest | 난독화 build 통과 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 공개 Swift library/app | 20 | 7,800 | 6,601 | 4,287 | 1,828 | 11,112 | 1,182 | 20 | swift-log, swift-metrics, SnapKit, swift-algorithms, fluent, swift-dependencies, Moya, Nimble |

## Manifest

manifest는 release build의 비공개 audit trail입니다.

```json
{
  "fileRenames": [
    {
      "from": "Feature/ProfileView.swift",
      "to": "Feature/S_123456789abc.swift"
    }
  ],
  "functionRenames": [
    {
      "file": "Feature/ProfileView.swift",
      "from": "renderAvatar",
      "to": "f_123456789abc"
    }
  ],
  "typeRenames": [
    {
      "file": "Feature/ProfileView.swift",
      "kind": "struct",
      "from": "ProfileView",
      "to": "T_123456789abc"
    }
  ],
  "skippedTypes": [],
  "skippedFunctions": []
}
```

manifest는 release-only 문제를 디버깅할 때 유용하지만, 난독화 mapping의
일부를 되돌릴 수 있으므로 비공개 build artifact로 보관해야 합니다.

## Library API

```swift
import ORKSwiftNewCore

let result = try ORKSwiftNew().run(.init(
    inputPath: "/tmp/MyAppCopy/MyApp",
    outputPath: "/tmp/MyAppObfuscated",
    manifestPath: "/tmp/ork-swift-new-manifest.json",
    seed: "my-app-release",
    renameFiles: true,
    renameTypes: true,
    renamePrivateFunctions: true,
    excludePatterns: ["Generated", "Security"]
))

print(result.summary)
```

## 현재 한계

ORK-SWIFT-NEW은 의도적으로 source-conservative하게 동작합니다. 완전한
Swift semantic refactoring을 시도하지 않으며 public API, protocol,
property, asset, Objective-C selector, storyboard reference, reflection/runtime
hook을 통해 노출되는 symbol은 rename하지 않습니다. production pipeline은
난독화 후 `xcodebuild` 성공을 최종 검증 gate로 취급해야 합니다.
