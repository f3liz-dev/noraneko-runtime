# Reflect Library Research Experiment

## Overview

This directory contains research and experimental code evaluating the [qlibs/reflect](https://github.com/qlibs/reflect/) library for potential use in Noraneko Runtime to improve code readability and maintainability.

## Files

- **RESEARCH_FINDINGS.md** - Comprehensive analysis and recommendations
- **reflect** - The qlibs/reflect C++20 header library (MIT licensed)
- **simple_demo.cpp** - Simple demonstration (C++11, no dependencies)
- **practical_example.cpp** - Real usage with reflect library (C++20)
- **example_settings.cpp** - Detailed comparison of approaches
- **Makefile** - Build system for examples

## Quick Start

```bash
# Build and run simple demo
make simple_demo
./simple_demo

# Build and run practical example with reflect
make practical_example
./practical_example

# Run all examples
make run

# Test compilation time
make test
```

## Key Findings

### ✅ **Recommended Use Cases**

The reflect library is **excellent** for:

1. **Configuration Management**
   - Automatic serialization/deserialization
   - Generic settings handling
   - Preference management

2. **Debug and Development Tools**
   - Automatic type name extraction
   - Enhanced logging with member introspection
   - Developer console features

3. **Testing Infrastructure**
   - Automatic comparison functions
   - Test fixture generation
   - Mock validation

4. **Utilities**
   - JSON/XML serialization helpers
   - Statistics collection
   - Generic data processing

### ❌ **NOT Recommended**

The reflect library **should NOT be used** for:

1. **XPCOM Interface Implementation**
   - Cannot replace `NS_IMPL_ISUPPORTS`
   - Cannot provide QueryInterface functionality
   - Cannot maintain binary interface compatibility
   - Cannot implement virtual method dispatch

2. **Core Framework Code**
   - Reference counting mechanisms
   - Virtual inheritance patterns
   - Cross-language interfaces (JS/C++)
   - ABI-stable interfaces

## Why Reflect Cannot Replace NS_IMPL_ISUPPORTS

XPCOM's `NS_IMPL_ISUPPORTS` macro provides:
- **Runtime interface discovery** (QueryInterface)
- **Specific vtable layout** for binary compatibility
- **Atomic reference counting** with cycle collection
- **Cross-language support** (JavaScript, Python, etc.)
- **Stable ABI** across compiler versions

Reflect library provides:
- **Compile-time introspection** only
- **Static type information**
- **Zero-cost abstractions**
- ❌ NO runtime type discovery
- ❌ NO vtable manipulation
- ❌ NO ABI guarantees

## Performance Characteristics

### Compilation Time
- Reflect header: ~0.1s (with `-DNTEST`)
- With tests: ~0.2s
- Per usage: Minimal overhead

### Runtime Performance
- **Zero overhead**: All reflection is compile-time
- **Optimal binary size**: Strings stored in `.rodata`
- **No allocations**: Stack-only operations
- **Inlined code**: Aggressive compiler optimization

### Binary Size
Example: `type_name()` function generates only:
```asm
lea rdx, [rip + type_name<foo>]
mov eax, 3
ret
```

## Examples Demonstrated

### 1. Configuration Management (practical_example.cpp)

Shows automatic:
- Type introspection
- Member name extraction
- Configuration comparison
- Serialization

Results from running `./practical_example`:
```
Configuration for BrowserConfig:
  Number of fields: 4
  Fields:
    startup_timeout_ms = 5000 (type: int, size: 4, offset: 0)
    enable_e10s = true (type: bool, size: 1, offset: 4)
    max_content_processes = 8 (type: int, size: 4, offset: 8)
    hardware_acceleration = true (type: bool, size: 1, offset: 12)
```

### 2. Benefits Over Manual Code

**Traditional Approach:**
```cpp
void print_settings(const Settings& s) {
  printf("timeout: %d\n", s.timeout);
  printf("enabled: %d\n", s.enabled);
  printf("max_conn: %d\n", s.max_conn);
  // Must update when adding fields!
}
```

**With Reflect:**
```cpp
void print_settings(const Settings& s) {
  reflect::for_each([&s](auto I) {
    printf("%s: ", reflect::member_name<I>(s).data());
    // Print value
  }, s);
  // Automatically adapts to new fields!
}
```

## Integration Recommendation

### For Noraneko-Specific Code

Consider using reflect in:
- `.github/` directory utilities
- `noraneko/` specific features
- Development and build tools
- Testing infrastructure

### Do NOT Use In

- Existing Firefox/Gecko core code
- XPCOM implementations
- Performance-critical paths
- Binary interface layers

## Compilation Requirements

- **C++ Standard**: C++20 or later
- **Compilers**: 
  - GCC 12+
  - Clang 15+
  - MSVC 19.36+
- **Flags**: Works with `-fno-rtti -fno-exceptions`

## License

- **reflect library**: MIT License (included)
- **Example code**: MPL 2.0 (Noraneko project)

## Conclusion

The reflect library is a **complementary tool**, not a replacement for XPCOM infrastructure. It offers significant benefits for configuration management, debugging, and testing, but cannot and should not replace core XPCOM patterns like `NS_IMPL_ISUPPORTS`.

**Recommendation**: Adopt for utilities and Noraneko-specific code, avoid for core framework.

## Further Reading

- [Full Research Document](RESEARCH_FINDINGS.md)
- [qlibs/reflect GitHub](https://github.com/qlibs/reflect/)
- [C++20 Reflection Proposal](https://wg21.link/P2996)
- [Mozilla XPCOM Docs](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/XPCOM)
