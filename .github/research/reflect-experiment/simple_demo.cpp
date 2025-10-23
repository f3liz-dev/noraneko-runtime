// Simplified example showing reflect concepts
// This file demonstrates the benefits without requiring full C++20 compile

#include <cstdio>
#include <cstring>

// ============================================================================
// Example 1: Manual approach (current pattern)
// ============================================================================

namespace manual {

struct Settings {
  int timeout;
  bool enabled;
  int max_conn;
};

void print_settings(const Settings& s) {
  printf("Manual approach - must list each field:\n");
  printf("  timeout: %d\n", s.timeout);
  printf("  enabled: %d\n", s.enabled);
  printf("  max_conn: %d\n", s.max_conn);
  printf("  Problem: Adding a field requires updating this function\n");
}

}

// ============================================================================
// Example 2: With reflect library (conceptual)
// ============================================================================

namespace with_reflect {

struct Settings {
  int timeout;
  bool enabled;
  int max_conn;
};

// This is what the code WOULD look like with reflect:
/*
void print_settings(const Settings& s) {
  printf("Reflect approach - automatic:\n");
  reflect::for_each([&s](auto I) {
    printf("  %s: ", reflect::member_name<I>(s).data());
    // print value based on type
    printf("\n");
  }, s);
  printf("  Benefit: Adding fields is automatic!\n");
}
*/

void print_settings_simulated(const Settings& s) {
  printf("Reflect approach (simulated):\n");
  printf("  timeout: %d  [via reflect::get<0>]\n", s.timeout);
  printf("  enabled: %d  [via reflect::get<1>]\n", s.enabled);
  printf("  max_conn: %d  [via reflect::get<2>]\n", s.max_conn);
  printf("  Benefit: Generic code adapts to structure changes\n");
}

}

// ============================================================================
// Example 3: XPCOM pattern (why reflect doesn't fit)
// ============================================================================

namespace xpcom {

// Simplified XPCOM interface
struct ISupports {
  virtual unsigned int AddRef() = 0;
  virtual unsigned int Release() = 0;
  virtual ~ISupports() = default;
};

// Traditional approach with macro
class Component : public ISupports {
  unsigned int mRefCnt = 0;
public:
  // NS_IMPL_ISUPPORTS expands to implementations like:
  unsigned int AddRef() override { return ++mRefCnt; }
  unsigned int Release() override {
    if (--mRefCnt == 0) { delete this; return 0; }
    return mRefCnt;
  }
};

void explain() {
  printf("\nXPCOM Interface Pattern:\n");
  printf("  Requires: Virtual methods, reference counting, QueryInterface\n");
  printf("  Reflect provides: Compile-time member info only\n");
  printf("  Conclusion: Reflect CANNOT replace NS_IMPL_ISUPPORTS\n");
}

}

int main() {
  printf("=== qlibs/reflect Research Summary ===\n\n");
  
  manual::Settings s1{5000, true, 10};
  manual::print_settings(s1);
  
  printf("\n");
  
  with_reflect::Settings s2{5000, true, 10};
  with_reflect::print_settings_simulated(s2);
  
  xpcom::explain();
  
  printf("\n=== Recommendation ===\n");
  printf("✓ Use reflect for: settings, config, debug utils\n");
  printf("✗ Don't use for: XPCOM interfaces (NS_IMPL_ISUPPORTS)\n");
  
  return 0;
}
