# Research: Applying qlibs/reflect for XUL Interface Code Modernization

## Executive Summary

This document presents research on applying the [qlibs/reflect](https://github.com/qlibs/reflect/) library to modernize and improve the readability of XUL/XPCOM interface code in the Noraneko Runtime (Firefox-based) codebase.

## Background

### Current XPCOM Interface Pattern

The current XPCOM (Cross Platform Component Object Model) system uses macro-based interface implementations:

1. **NS_DECL_ISUPPORTS** - Declares reference counting methods
2. **NS_IMPL_ISUPPORTS** - Implements QueryInterface, AddRef, and Release
3. **NS_IMETHODIMP** - Implements interface methods

Example from `caps/DomainPolicy.cpp`:
```cpp
// Header
class DomainPolicy final : public nsIDomainPolicy {
 public:
  NS_DECL_ISUPPORTS
  NS_DECL_NSIDOMAINPOLICY
  DomainPolicy();
  // ...
};

// Implementation
NS_IMPL_ISUPPORTS(DomainPolicy, nsIDomainPolicy)

NS_IMETHODIMP
DomainPolicy::GetBlocklist(nsIDomainSet** aSet) {
  nsCOMPtr<nsIDomainSet> set = mBlocklist.get();
  set.forget(aSet);
  return NS_OK;
}
```

### What is qlibs/reflect?

The reflect library is a C++20 static reflection library that provides:
- Type introspection (type names, member names)
- Compile-time member access by name or index
- Enum to string conversion
- Zero-cost abstraction with optimal binary size
- Single header implementation
- No external dependencies

## Analysis

### Key Features of reflect Library

1. **Type and Member Names**
   ```cpp
   struct Foo { int a; int b; };
   static_assert("Foo" == reflect::type_name<Foo>());
   static_assert("a" == reflect::member_name<0, Foo>());
   ```

2. **Member Access**
   ```cpp
   Foo f{42, 100};
   static_assert(42 == reflect::get<0>(f));
   static_assert(42 == reflect::get<"a">(f));
   ```

3. **Iteration Over Members**
   ```cpp
   reflect::for_each([](auto I) {
     // Access each member by index I
   }, f);
   ```

### Compatibility Assessment

#### Requirements
- **C++20**: Requires gcc-12+, clang-15+, msvc-19.36+
- **No RTTI Required**: Works with `-fno-rtti`
- **No Exceptions Required**: Works with `-fno-exceptions`

#### Firefox/Gecko Build System Compatibility
✅ **Compatible**: Firefox currently uses C++20 features
✅ **Build System**: Uses Clang/GCC with modern versions
⚠️ **Concern**: Firefox compilation times are already long; reflect adds ~0.2s per include

### Potential Applications in XUL/XPCOM

#### 1. Interface Method Registration (Low Impact)

**Current Pattern:**
```cpp
NS_IMPL_ISUPPORTS(DomainPolicy, nsIDomainPolicy)
```

**With Reflect (Concept):**
The reflect library doesn't directly replace XPCOM's vtable/QueryInterface mechanism, as XPCOM requires specific ABI compatibility and runtime interface discovery that reflect cannot provide. The macro-based system is deeply integrated with the XPCOM binary interface.

**Verdict**: ❌ **Not Suitable** - XPCOM's NS_IMPL_ISUPPORTS is too tightly coupled to the component object model and binary interface.

#### 2. Debug/Logging Improvements (Medium Impact)

**Current Pattern:**
```cpp
// Manual logging
printf("Setting property in %s\n", "DomainPolicy");
```

**With Reflect:**
```cpp
template<typename T>
void LogClassOperation(const T& obj, const char* operation) {
  printf("%s on class %s\n", operation, 
         reflect::type_name(obj).data());
}
```

**Verdict**: ✅ **Potentially Useful** - Can improve debugging and introspection

#### 3. Property/Configuration Systems (High Impact)

**Use Case**: Settings, preferences, or configuration structures

**Current Pattern:**
```cpp
struct Settings {
  int timeout;
  bool enabled;
  const char* name;
};

// Manual serialization
void SaveSettings(const Settings& s) {
  WriteInt("timeout", s.timeout);
  WriteBool("enabled", s.enabled);
  WriteString("name", s.name);
}
```

**With Reflect:**
```cpp
void SaveSettings(const Settings& s) {
  reflect::for_each([&s](auto I) {
    auto name = reflect::member_name<I>(s);
    auto value = reflect::get<I>(s);
    WriteValue(name, value);
  }, s);
}
```

**Verdict**: ✅ **Good Fit** - Reduces boilerplate for generic operations

#### 4. Testing/Mocking Infrastructure (Medium Impact)

**Use Case**: Automatic test fixture generation

**With Reflect:**
```cpp
template<typename T>
void CompareStructs(const T& a, const T& b) {
  reflect::for_each([&](auto I) {
    if (reflect::get<I>(a) != reflect::get<I>(b)) {
      printf("Mismatch in field %s\n", 
             reflect::member_name<I>(a).data());
    }
  }, a);
}
```

**Verdict**: ✅ **Useful** - Can improve test utilities

## Concerns and Limitations

### 1. Binary Interface Stability
- **Issue**: XPCOM requires stable binary interfaces across versions
- **Impact**: Reflect doesn't help with this; macro system is designed for ABI stability
- **Risk**: High if used for core interface implementation

### 2. Compilation Time
- **Issue**: Reflect adds ~0.2s per include (with tests), ~0.1s without tests
- **Impact**: Firefox already has long build times
- **Mitigation**: Use `-DNTEST` in production builds; limit usage to non-critical paths

### 3. Limited to Aggregate Types
- **Issue**: Reflect works best with simple structs/classes without complex inheritance
- **Impact**: Many XPCOM classes use multiple inheritance and virtual methods
- **Limitation**: Cannot replace virtual method dispatch

### 4. XPCOM-Specific Requirements
- **QueryInterface**: Requires specific vtable layout
- **Reference Counting**: Needs atomic operations and specific lifecycle
- **Interface Discovery**: Runtime type checking that reflect cannot provide

## Recommendations

### ✅ **Recommended Use Cases**

1. **Configuration/Settings Structures**
   - Generic serialization/deserialization
   - Preference management
   - Command-line argument parsing

2. **Debug and Development Tools**
   - Enhanced logging with automatic type names
   - Developer console introspection
   - Crash reporting with field-level detail

3. **Testing Infrastructure**
   - Automatic comparison functions
   - Mock object validation
   - Test fixture generation

4. **Non-Critical Utilities**
   - JSON/XML serialization helpers
   - IPC message builders
   - Statistics collection

### ❌ **Not Recommended**

1. **Core XPCOM Interface Implementation**
   - NS_IMPL_ISUPPORTS replacement
   - Virtual method dispatch
   - QueryInterface mechanism

2. **Hot Performance Paths**
   - Core rendering code
   - Event dispatch
   - Memory allocation

3. **Platform-Specific Code**
   - Binary interface layers
   - Plugin interfaces
   - External component interfaces

## Experimental Implementation

### Example: Enhanced Settings System

See `example_settings.cpp` for a proof-of-concept showing how reflect can improve a settings management system with automatic serialization.

### Example: Debug Logging Utility

See `example_logging.cpp` for enhanced logging that automatically includes type and member names.

## Conclusion

The qlibs/reflect library is **not suitable for replacing core XPCOM interface patterns** like `NS_IMPL_ISUPPORTS` due to:
- XPCOM's specific ABI requirements
- Need for stable binary interfaces
- Runtime type discovery requirements
- Complex inheritance patterns

However, reflect **can be valuable for**:
- Configuration and settings management
- Development and debugging tools
- Testing infrastructure
- Generic serialization tasks

### Recommendation: **Partial Adoption for Utilities**

Consider adopting reflect for:
1. New configuration/settings systems in the `.github/` or `noraneko/` specific code
2. Development tools and debugging utilities
3. Test infrastructure improvements

**Do not** replace existing XPCOM interface code with reflect-based implementations.

## Next Steps

If proceeding with limited adoption:

1. ✅ Add reflect header to `third_party/` or `.github/research/`
2. ✅ Create example implementations for configuration management
3. ✅ Add compilation tests to CI
4. ✅ Document usage guidelines
5. ⚠️ Monitor compilation time impact
6. ⚠️ Start with non-critical utilities only

## References

- [qlibs/reflect GitHub](https://github.com/qlibs/reflect/)
- [C++20 Reflection Proposal P2996](https://wg21.link/P2996)
- [Mozilla XPCOM Documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/XPCOM)
- [nsISupportsImpl.h Implementation](../../xpcom/base/nsISupportsImpl.h)
