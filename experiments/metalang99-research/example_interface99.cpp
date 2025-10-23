/* Example 2: interface99 Approach (Hypothetical) */

/*
 * This is a HYPOTHETICAL example showing how interface99 COULD be used
 * if we were to adopt it for internal interfaces. This is NOT meant to
 * replace XPCOM but rather complement it for specific use cases.
 *
 * NOTE: This code will not compile in the Firefox build system without
 * additional setup. It is for demonstration purposes only.
 */

#include <interface99.h>  // Would need to be integrated

// Define the interface using interface99 syntax
#define Plugin_IFACE                                    \
    vfunc(bool, initialize, VSelf)                      \
    vfunc(void, shutdown, VSelf)                        \
    vfunc(const char*, getName, const VSelf)

interface(Plugin);

// Implementation structure
typedef struct {
    char name[64];
    bool initialized;
} LoggingPlugin;

// Implement the functions
bool LoggingPlugin_initialize(VSelf) {
    VSELF(LoggingPlugin);
    self->initialized = true;
    return true;
}

void LoggingPlugin_shutdown(VSelf) {
    VSELF(LoggingPlugin);
    self->initialized = false;
}

const char* LoggingPlugin_getName(const VSelf) {
    VSELF(const LoggingPlugin);
    return self->name;
}

// Generate vtable (one line!)
impl(Plugin, LoggingPlugin);

// Usage
void example() {
    LoggingPlugin logger = {.name = "Logger", .initialized = false};
    Plugin plugin = DYN(LoggingPlugin, Plugin, &logger);
    
    // Call methods polymorphically
    if (VCALL(plugin, initialize)) {
        printf("Initialized: %s\n", VCALL(plugin, getName));
        VCALL(plugin, shutdown);
    }
}

/*
 * Pros of interface99:
 * - Much simpler syntax (fewer lines)
 * - Clear interface definition
 * - No inheritance needed
 * - Can implement multiple interfaces easily
 * - Works with plain C structs
 * - Zero-cost abstraction
 * - Easy to understand vtable layout
 *
 * Cons vs XPCOM:
 * - No reference counting (must manage manually)
 * - No QueryInterface (no runtime type discovery)
 * - Not compatible with XPCOM ABI
 * - Cannot call from JavaScript
 * - No cycle collection support
 * - Would be a new pattern for Firefox developers
 *
 * RECOMMENDED USE CASES:
 * - Internal C++ utility interfaces
 * - Test mocks and stubs
 * - Plugin architectures (no XPCOM needed)
 * - Isolated new subsystems
 * - Situations where reference counting not needed
 *
 * NOT RECOMMENDED FOR:
 * - Public XPCOM interfaces
 * - JavaScript-accessible components
 * - Cross-component communication
 * - Anywhere reference counting is needed
 * - Existing codebases (don't replace working code)
 */
