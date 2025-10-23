// Example: Configuration Management with qlibs/reflect
// This demonstrates how reflect can improve settings/configuration code
// compared to traditional manual approaches in XUL/XPCOM code.

#include <cstdio>
#include <string_view>
#include <cstring>

// Note: In actual usage, would be: #include "reflect"
// For this example, we'll show the concept without full implementation

// ============================================================================
// TRADITIONAL APPROACH (Current XUL/XPCOM Pattern)
// ============================================================================

namespace traditional {

struct BrowserSettings {
  int timeout_ms;
  bool enable_tracking_protection;
  int max_connections;
  const char* homepage_url;
};

// Manual serialization - must update when adding fields
void SaveSettings(const BrowserSettings& settings) {
  printf("Traditional Approach:\n");
  printf("  timeout_ms=%d\n", settings.timeout_ms);
  printf("  enable_tracking_protection=%d\n", settings.enable_tracking_protection);
  printf("  max_connections=%d\n", settings.max_connections);
  printf("  homepage_url=%s\n", settings.homepage_url);
}

// Manual comparison - must update when adding fields
bool CompareSettings(const BrowserSettings& a, const BrowserSettings& b) {
  if (a.timeout_ms != b.timeout_ms) {
    printf("  Mismatch: timeout_ms (%d vs %d)\n", a.timeout_ms, b.timeout_ms);
    return false;
  }
  if (a.enable_tracking_protection != b.enable_tracking_protection) {
    printf("  Mismatch: enable_tracking_protection\n");
    return false;
  }
  if (a.max_connections != b.max_connections) {
    printf("  Mismatch: max_connections (%d vs %d)\n", 
           a.max_connections, b.max_connections);
    return false;
  }
  if (strcmp(a.homepage_url, b.homepage_url) != 0) {
    printf("  Mismatch: homepage_url\n");
    return false;
  }
  return true;
}

// Manual field counting
constexpr size_t GetFieldCount() {
  return 4; // Must manually update
}

} // namespace traditional

// ============================================================================
// REFLECT-BASED APPROACH (Modern C++20 with reflect)
// ============================================================================

namespace modern {

// Same structure definition
struct BrowserSettings {
  int timeout_ms;
  bool enable_tracking_protection;
  int max_connections;
  const char* homepage_url;
};

#ifdef USE_REFLECT_LIBRARY
// This would be the actual implementation with reflect library

#include "reflect"

// Automatic serialization - adapts when fields are added/removed
void SaveSettings(const BrowserSettings& settings) {
  printf("Reflect-based Approach:\n");
  reflect::for_each([&settings](auto I) {
    printf("  %s=", reflect::member_name<I>(settings).data());
    
    // Type-safe printing (simplified for example)
    auto& value = reflect::get<I>(settings);
    using T = std::remove_cvref_t<decltype(value)>;
    
    if constexpr (std::is_same_v<T, int>) {
      printf("%d", value);
    } else if constexpr (std::is_same_v<T, bool>) {
      printf("%s", value ? "true" : "false");
    } else if constexpr (std::is_same_v<T, const char*>) {
      printf("%s", value);
    }
    printf("\n");
  }, settings);
}

// Automatic comparison
bool CompareSettings(const BrowserSettings& a, const BrowserSettings& b) {
  bool all_match = true;
  reflect::for_each([&](auto I) {
    if (reflect::get<I>(a) != reflect::get<I>(b)) {
      printf("  Mismatch: %s\n", reflect::member_name<I>(a).data());
      all_match = false;
    }
  }, a);
  return all_match;
}

// Automatic field counting
constexpr size_t GetFieldCount() {
  BrowserSettings s{};
  return reflect::size(s);
}

#endif // USE_REFLECT_LIBRARY

// Simulated reflect-based approach for demonstration
// (shows the concept without full reflect library integration)
void SaveSettingsSimulated(const BrowserSettings& settings) {
  printf("Reflect-based Approach (simulated):\n");
  printf("  timeout_ms=%d\n", settings.timeout_ms);
  printf("  enable_tracking_protection=%s\n", 
         settings.enable_tracking_protection ? "true" : "false");
  printf("  max_connections=%d\n", settings.max_connections);
  printf("  homepage_url=%s\n", settings.homepage_url);
  printf("  [All fields accessed via reflection API]\n");
}

} // namespace modern

// ============================================================================
// COMPARISON AND BENEFITS
// ============================================================================

void DemonstrateComparison() {
  printf("=== Comparison: Traditional vs Reflect-based Settings ===\n\n");
  
  // Create test settings
  traditional::BrowserSettings settings1{
    .timeout_ms = 5000,
    .enable_tracking_protection = true,
    .max_connections = 10,
    .homepage_url = "https://mozilla.org"
  };
  
  traditional::BrowserSettings settings2{
    .timeout_ms = 3000,
    .enable_tracking_protection = true,
    .max_connections = 10,
    .homepage_url = "https://mozilla.org"
  };
  
  // Traditional approach
  printf("\n1. TRADITIONAL MANUAL SERIALIZATION:\n");
  traditional::SaveSettings(settings1);
  printf("\n  Lines of code: ~8\n");
  printf("  Maintenance: Must update for each new field\n");
  printf("  Error-prone: Easy to forget fields\n");
  
  // Modern approach
  printf("\n2. REFLECT-BASED AUTO SERIALIZATION:\n");
  modern::SaveSettingsSimulated(settings1);
  printf("\n  Lines of code: ~3 (generic implementation)\n");
  printf("  Maintenance: Automatic adaptation to new fields\n");
  printf("  Error-prone: Impossible to forget fields\n");
  
  // Comparison
  printf("\n3. TRADITIONAL COMPARISON:\n");
  bool match1 = traditional::CompareSettings(settings1, settings2);
  printf("  Result: %s\n", match1 ? "Match" : "No match");
  
  printf("\n4. Benefits of Reflect Approach:\n");
  printf("  ✓ Reduced boilerplate code\n");
  printf("  ✓ Automatic adaptation to structure changes\n");
  printf("  ✓ Compile-time safety\n");
  printf("  ✓ Better maintainability\n");
  printf("  ✓ Zero runtime overhead\n");
  
  printf("\n5. When NOT to use Reflect:\n");
  printf("  ✗ XPCOM interface implementations (NS_IMPL_ISUPPORTS)\n");
  printf("  ✗ Virtual method dispatch\n");
  printf("  ✗ Binary interface compatibility layers\n");
  printf("  ✗ QueryInterface mechanism\n");
}

// ============================================================================
// XPCOM INTERFACE PATTERN (Why reflect is NOT suitable)
// ============================================================================

namespace xpcom_example {

// Simplified XPCOM-style interface
class nsIDomainPolicy {
public:
  virtual ~nsIDomainPolicy() = default;
  virtual int QueryInterface(const char* iid, void** result) = 0;
  virtual unsigned int AddRef() = 0;
  virtual unsigned int Release() = 0;
  virtual int GetBlocklist(void** aSet) = 0;
};

// Traditional implementation with macros
class DomainPolicy : public nsIDomainPolicy {
private:
  unsigned int mRefCnt;
  
public:
  DomainPolicy() : mRefCnt(0) {}
  
  // These MUST be manually implemented for XPCOM
  // NS_IMPL_ISUPPORTS expands to something like:
  
  unsigned int AddRef() override {
    return ++mRefCnt;
  }
  
  unsigned int Release() override {
    unsigned int count = --mRefCnt;
    if (count == 0) {
      delete this;
    }
    return count;
  }
  
  int QueryInterface(const char* iid, void** result) override {
    // Complex vtable lookup logic
    // Cannot be replaced by reflection
    return -1;
  }
  
  int GetBlocklist(void** aSet) override {
    // Implementation
    return 0;
  }
};

void ExplainWhyNotSuitable() {
  printf("\n=== Why Reflect Cannot Replace XPCOM Patterns ===\n\n");
  
  printf("XPCOM NS_IMPL_ISUPPORTS requires:\n");
  printf("  1. Specific vtable layout for binary compatibility\n");
  printf("  2. Runtime interface discovery (QueryInterface)\n");
  printf("  3. Atomic reference counting with specific semantics\n");
  printf("  4. Cross-language compatibility (JavaScript, etc.)\n");
  printf("  5. Stable ABI across compiler versions\n");
  
  printf("\nReflect library provides:\n");
  printf("  1. Compile-time member introspection\n");
  printf("  2. Static type information\n");
  printf("  3. Zero-cost abstractions\n");
  printf("  ✗ NO runtime type discovery\n");
  printf("  ✗ NO vtable manipulation\n");
  printf("  ✗ NO ABI guarantees\n");
  
  printf("\nConclusion:\n");
  printf("  Reflect is a COMPLEMENTARY tool, not a replacement\n");
  printf("  for XPCOM infrastructure.\n");
}

} // namespace xpcom_example

// ============================================================================
// MAIN DEMONSTRATION
// ============================================================================

int main() {
  printf("╔════════════════════════════════════════════════════════════╗\n");
  printf("║  qlibs/reflect Research: Settings Management Example      ║\n");
  printf("╚════════════════════════════════════════════════════════════╝\n");
  
  DemonstrateComparison();
  xpcom_example::ExplainWhyNotSuitable();
  
  printf("\n=== Summary ===\n");
  printf("Reflect is EXCELLENT for:\n");
  printf("  • Configuration structures\n");
  printf("  • Settings management\n");
  printf("  • Debug/logging utilities\n");
  printf("  • Test infrastructure\n");
  printf("  • Serialization helpers\n");
  
  printf("\nReflect is NOT suitable for:\n");
  printf("  • XPCOM interface implementation\n");
  printf("  • NS_IMPL_ISUPPORTS replacement\n");
  printf("  • Virtual method generation\n");
  printf("  • Binary interface layers\n");
  
  return 0;
}
