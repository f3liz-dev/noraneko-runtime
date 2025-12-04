# Noraneko Runtime Dagger CI

Dagger-based CI/CD module for building noraneko-runtime.

## Usage

```bash
cd .github/ci
go run . build [options]
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `-platform` | linux | Target: linux, windows |
| `-arch` | x86_64 | Architecture: x86_64, aarch64 |
| `-debug` | true | Enable debug build |
| `-pgo` | false | Enable PGO |
| `-pgo-mode` | - | generate or use |
| `-omnijar-compress` | deflate | deflate, zstd, lz4, none |
| `-output` | ./output | Output directory |

## Examples

```bash
# Linux x86_64 debug build
go run . build -platform=linux -arch=x86_64 -debug

# Linux aarch64 release build
go run . build -platform=linux -arch=aarch64 -debug=false

# PGO profile generation
go run . build -platform=linux -pgo -pgo-mode=generate
```
