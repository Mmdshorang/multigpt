# Contributing to MultiCodex

Thanks for your interest in contributing.

## Prerequisites

- macOS 13+
- Xcode 15+
- Swift toolchain compatible with this repository
- `just` command runner

## Development Setup

```bash
git clone https://github.com/momoazn/multicodex.git
cd multicodex
just doctor
just run
```

## Before Opening a Pull Request

```bash
just check
```

This runs project checks (doctor, build, tests). Please include tests for behavior changes when possible.

## Scope Guidelines

- Keep changes focused and atomic.
- Prefer small pull requests with clear intent.
- Update documentation when behavior or developer workflows change.

## Code Style

- Follow the existing Swift style in this repository.
- Run format/lint tools when applicable:
  - `swiftformat .`
  - `swiftlint`

## Reporting Issues

Use GitHub Issues for bug reports and feature requests. Include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- macOS version
- MultiCodex version

For security issues, please open an issue with minimal reproduction details and avoid posting sensitive data.
