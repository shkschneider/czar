# GitHub Copilot Instructions

A concise guide for Copilot: what to install, how to build, run and test the project.

## Prerequisites

- LuaJIT (preferred runtime)
- C toolchain: gcc/clang, make (for any native C/extension pieces)
- Library: glibc (possibly musl)

Example installs
- Debian/Ubuntu:
  - sudo apt install -y build-essential luajit luajit-5.1-dev gcc
- macOS (Homebrew):
  - brew install luajit gcc
- Windows:
  - _unsupported/untested for now_

## Setup

1. Install `luajit`, `luajit-dev` ; test with `luajit -v`

2. Clone the repo https://github.com/shkschneider/czar.git

## Build

```
./build.sh
# generates ./dist/cz
```

## Run

```
./dist/cz run ...
```

## Test

```
# test all
./check.sh
# test some
./check.sh ...
```

## Format

> work-in-progress
```
./dist/cz format ...
```

## Automation

- `.github/workflows/build.yml`
- `.github/workflows/test.yml`
