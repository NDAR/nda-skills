---
name: angular-coding-standards
description: Use when creating, changing, reviewing, or testing Angular components, templates, services, forms, routing, or Angular-specific TypeScript code.
---

# Angular Coding Standards

Use the target repository's established conventions. This skill supplies a shared baseline where those conventions are absent; it does not authorize framework migrations.

## Resolve Conventions

Inspect repository instructions, `package.json`, lockfiles, Angular/Nx project configuration, TypeScript and ESLint settings, and nearby production and test code. Resolve conflicts in this order:

```text
direct task requirements
> repository instructions and documented standards
> repository quality tooling and configuration
> adjacent production and test patterns
> shared Angular baseline
```

Record the installed Angular version, package manager, and test executor before selecting APIs or commands. Use version-matched documentation. Existing NgModules, RxJS state, or Jasmine/Karma tests are not permission to migrate to standalone components, signals, or another runner.

## Shared Baseline

| Area | Baseline when repository guidance is absent |
| --- | --- |
| Structure | Group by feature; keep components focused on presentation and interaction, and reusable data access in injectable services. Respect Nx library boundaries and public entry points. |
| TypeScript | Preserve strict compiler/template checks; model nullable and asynchronous values explicitly. Narrow `unknown` at boundaries rather than introducing unchecked `any` or non-null assertions. |
| Components | For new code, prefer standalone components where supported and compatible with the app. Preserve public input/output contracts and the existing change-detection strategy. |
| State | Use the repository's signals/store/RxJS patterns. Derive values rather than duplicating state; keep side effects out of computed state and template expressions. |
| Async work | Prefer template-managed subscriptions; otherwise use version-supported lifecycle cleanup. Choose RxJS flattening operators according to cancellation/ordering requirements. Handle loading, empty, and failure states. |
| Templates | Keep expressions simple, track repeated items by stable identity, and use semantic HTML with labels, keyboard interaction, and visible focus. Follow the installed version's template syntax. |
| Forms | Preserve the established forms approach; prefer typed reactive forms for new complex forms where supported. Surface validation errors accessibly. |
| Security | Keep secrets out of browser bundles and logs. Preserve Angular sanitization; do not bypass trust checks for untrusted HTML/URLs. Client-side guards do not enforce server authorization. |
| Tests | Use existing TestBed, HTTP/router testing utilities, and runner conventions. Assert rendered behavior, inputs/outputs, and failure paths rather than private implementation details. |

For example, a search change in an NgModule/RxJS feature should preserve that structure, cancel obsolete requests when appropriate, and test the rendered results and error state using the existing runner. It does not require a signals migration.

## Verify and Report

Use `angular-verification` for completion checks. Explain any repository override, the commands actually run, and unavailable checks. A passing unit test does not establish accessibility or browser interaction correctness; inspect changed UI in the supported browser workflow when relevant.

Consult the [Angular style guide](https://angular.dev/style-guide) and [testing documentation](https://angular.dev/guide/testing), selecting documentation compatible with the installed version. Common mistakes are copying current APIs into older apps, weakening strictness to make a build pass, and replacing established state/test tooling during an unrelated change.
