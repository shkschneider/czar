# GitHub Copilot Instructions

A concise guide for Copilot: what to install, how to build, run and test the project.

## Prerequisites

- LuaJIT (preferred runtime)
- C toolchain: gcc/clang, make (for any native C/extension pieces)
- Optional (for testing / linting): luarocks, busted, luacheck

Example installs
- Debian/Ubuntu:
  - sudo apt install -y luajit-dev build-essential make luarocks
- macOS (Homebrew):
  - brew install luajit gcc make luarocks
- Windows:
  - Use WSL or install LuaJIT & a C toolchain; or use Chocolatey for packages.

## Setup

1. Install `luajit` ; test with `luajit -v`

2. Clone the repo https://github.com/shkschneider/czar.git

## Build

```
./build.sh
# generates ./dist/cz
```

## Run

```
./dist/cz <run> ...
```

## Test

```
# test all
./check.sh
# test some
./dist/cz <test> ...
```

## Format

```
# work-in-progress
./dist/cz format ...
# do not use for now
```

## Automation

```
.github/workflows/build.yml
.github/workflows/test.yml
```
