# Metalang99 Research Experiment

## Purpose

This experiment evaluates whether the metalang99 family of libraries (metalang99, interface99, and datatype99) could beneficially replace or complement existing XUL/XPCOM interface patterns, particularly `NS_IMPL_ISUPPORTS`.

## Structure

```
experiments/metalang99-research/
├── README.md                      # This file
├── SUMMARY.md                     # Executive summary with recommendations
├── RESEARCH.md                    # Detailed analysis (300+ lines)
├── example_traditional.cpp        # Current NS_IMPL_ISUPPORTS pattern
├── example_interface99.cpp        # Hypothetical interface99 usage
└── example_datatype99.cpp         # Hypothetical datatype99 usage

third_party/
├── metalang99/                    # Preprocessor metaprogramming library
├── interface99/                   # Runtime polymorphism (traits/interfaces)
└── datatype99/                    # Algebraic data types with pattern matching
```

## Quick Summary

**Question:** Should we replace NS_IMPL_ISUPPORTS with interface99?

**Answer:** **NO** - Do not replace existing code. Limited experimental use MAY be considered for new internal utilities only.

### Why NOT?

1. **Incompatible with XPCOM** - Different vtable layout, no refcounting, no QueryInterface
2. **No JavaScript access** - Can't expose to browser scripts
3. **Missing critical features** - No cycle collection, no thread safety checks
4. **High migration risk** - Would break existing infrastructure
5. **Binary incompatibility** - Not COM-compatible

### Potential Limited Use Cases

- ✅ datatype99 for internal event types (better than manual tagged unions)
- ✅ datatype99 for result/error types (safer than some nsresult patterns)
- ✅ interface99 for internal test mocks and utilities
- ❌ NOT for public APIs, XPCOM interfaces, or JavaScript-accessible components

## Key Findings

### Complexity Comparison

| Metric | XPCOM/NS_IMPL_ISUPPORTS | interface99 | Winner |
|--------|------------------------|-------------|--------|
| Lines for interface | ~8 | ~5 | interface99 |
| Lines for implementation | ~40 | ~20 | interface99 |
| Boilerplate ratio | ~60% | ~10% | interface99 |
| Reference counting | ✓ Built-in | ✗ Manual | XPCOM |
| QueryInterface | ✓ Yes | ✗ No | XPCOM |
| Binary compatibility | ✓ Yes | ✗ No | XPCOM |
| JavaScript access | ✓ Yes | ✗ No | XPCOM |
| Cycle collection | ✓ Yes | ✗ No | XPCOM |

**Conclusion:** interface99 is cleaner but fundamentally incompatible with XPCOM requirements.

### Security Analysis

- ✅ No security vulnerabilities detected by CodeQL
- ✅ Libraries are MIT licensed (compatible with MPL 2.0)
- ✅ Type safety improvements with datatype99
- ⚠️ Heavy preprocessor use makes code harder to audit
- ⚠️ New pattern could lead to developer mistakes

## Recommendations

### For Production Code

**DO:**
- Keep using NS_IMPL_ISUPPORTS for all XPCOM interfaces
- Use existing patterns for public APIs
- Maintain compatibility with Firefox infrastructure

**DON'T:**
- Replace working NS_IMPL_ISUPPORTS implementations
- Use for JavaScript-accessible components
- Use where reference counting is needed
- Use for cross-component communication

### For Experimental Use (If Interested)

**Consider:**
1. Using datatype99 for new internal event types
2. Using datatype99 for result/error handling in isolated modules
3. Small pilot project in non-critical area
4. Thorough documentation and developer training

**Process:**
1. Start with isolated, non-critical subsystem
2. Measure compilation time impact
3. Gather developer feedback
4. Assess debugging experience
5. Make decision after 3-6 months

## Files

### Documentation

- **SUMMARY.md** - Executive summary for decision-makers
- **RESEARCH.md** - Comprehensive technical analysis
- **README.md** - This file

### Code Examples (For Reference Only)

These examples demonstrate concepts but are NOT meant to be compiled in the Firefox build:

- **example_traditional.cpp** - How NS_IMPL_ISUPPORTS works today
- **example_interface99.cpp** - How interface99 would look (hypothetical)
- **example_datatype99.cpp** - How datatype99 would look (hypothetical)

### Libraries (Reference)

Located in `third_party/`:

- **metalang99/** - Preprocessor metaprogramming
- **interface99/** - Runtime polymorphism
- **datatype99/** - Algebraic data types

## References

- [XPCOM Documentation](https://firefox-source-docs.mozilla.org/xpcom/)
- [metalang99 GitHub](https://github.com/hirrolot/metalang99)
- [interface99 GitHub](https://github.com/hirrolot/interface99)
- [datatype99 GitHub](https://github.com/hirrolot/datatype99)

## Conclusion

The metalang99 libraries offer interesting modern C99 patterns, but they are **not suitable for replacing NS_IMPL_ISUPPORTS** in the XUL/XPCOM codebase. 

XPCOM provides critical features (reference counting, QueryInterface, cycle collection, JavaScript access) that cannot be easily replicated. The libraries remain in `third_party/` for reference and potential limited experimental use in the future.

**Bottom line:** "If it ain't broke, don't fix it" - NS_IMPL_ISUPPORTS works well for its purpose.

---

**Research Date:** 2025-10-23  
**Researcher:** GitHub Copilot (with human oversight)  
**Status:** Complete  
**Recommendation:** Do not replace existing code; consider limited experimental use only
