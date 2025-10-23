/* -*- Mode: C++; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=8 sts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * EXPERIMENTAL: Partial Replacement Concept
 * 
 * This demonstrates what a PARTIAL replacement might look like for a simple
 * internal utility that doesn't need full XPCOM features.
 * 
 * WARNING: This is for RESEARCH PURPOSES ONLY. Do not use in production.
 */

#include <stdio.h>
#include <string.h>

// ============================================================
// BEFORE: Traditional XPCOM Pattern
// ============================================================

// Example: Simple logger interface in XPCOM style
namespace traditional {

class nsILogger {
public:
    virtual void LogMessage(const char* msg) = 0;
    virtual void LogError(const char* error) = 0;
    virtual int GetLogCount() const = 0;
};

class SimpleLogger : public nsILogger {
private:
    int mLogCount;
    
public:
    SimpleLogger() : mLogCount(0) {}
    
    void LogMessage(const char* msg) override {
        printf("[BEFORE] Message: %s\n", msg);
        mLogCount++;
    }
    
    void LogError(const char* error) override {
        printf("[BEFORE] Error: %s\n", error);
        mLogCount++;
    }
    
    int GetLogCount() const override {
        return mLogCount;
    }
};

void demonstrateBefore() {
    printf("=== BEFORE: Traditional Pattern ===\n");
    
    SimpleLogger logger;
    nsILogger* iLogger = &logger;
    
    iLogger->LogMessage("System initialized");
    iLogger->LogError("Warning: Low memory");
    printf("[BEFORE] Total logs: %d\n\n", iLogger->GetLogCount());
}

} // namespace traditional

// ============================================================
// AFTER: interface99 Pattern (Hypothetical)
// ============================================================

namespace experimental {

/*
 * In a real implementation, you would:
 * 
 * #include <interface99.h>
 * 
 * #define Logger_IFACE \
 *     vfunc(void, logMessage, VSelf, const char* msg) \
 *     vfunc(void, logError, VSelf, const char* error) \
 *     vfunc(int, getLogCount, const VSelf)
 * 
 * interface(Logger);
 * 
 * But since we can't compile it easily, here's the conceptual equivalent:
 */

// Simulated interface99 structure (what the macro would generate)
struct Logger;

typedef struct LoggerVTable {
    void (*logMessage)(void* self, const char* msg);
    void (*logError)(void* self, const char* error);
    int (*getLogCount)(const void* self);
} LoggerVTable;

typedef struct Logger {
    void* self;
    const LoggerVTable* vptr;
} Logger;

// Implementation
typedef struct {
    int logCount;
} SimpleLoggerImpl;

void SimpleLoggerImpl_logMessage(void* self, const char* msg) {
    SimpleLoggerImpl* impl = (SimpleLoggerImpl*)self;
    printf("[AFTER] Message: %s\n", msg);
    impl->logCount++;
}

void SimpleLoggerImpl_logError(void* self, const char* error) {
    SimpleLoggerImpl* impl = (SimpleLoggerImpl*)self;
    printf("[AFTER] Error: %s\n", error);
    impl->logCount++;
}

int SimpleLoggerImpl_getLogCount(const void* self) {
    const SimpleLoggerImpl* impl = (const SimpleLoggerImpl*)self;
    return impl->logCount;
}

// VTable (what impl() macro would generate)
static const LoggerVTable SimpleLoggerImpl_Logger_impl = {
    .logMessage = SimpleLoggerImpl_logMessage,
    .logError = SimpleLoggerImpl_logError,
    .getLogCount = SimpleLoggerImpl_getLogCount
};

// Helper to create Logger instance (what DYN() macro would do)
Logger createLogger(SimpleLoggerImpl* impl) {
    return (Logger){
        .self = impl,
        .vptr = &SimpleLoggerImpl_Logger_impl
    };
}

void demonstrateAfter() {
    printf("=== AFTER: interface99 Pattern ===\n");
    
    SimpleLoggerImpl loggerData = { .logCount = 0 };
    Logger logger = createLogger(&loggerData);
    
    logger.vptr->logMessage(logger.self, "System initialized");
    logger.vptr->logError(logger.self, "Warning: Low memory");
    printf("[AFTER] Total logs: %d\n\n", logger.vptr->getLogCount(logger.self));
}

} // namespace experimental

// ============================================================
// ANALYSIS
// ============================================================

void printAnalysis() {
    printf("=== ANALYSIS ===\n\n");
    
    printf("Lines of Code:\n");
    printf("  BEFORE (traditional): ~25 lines\n");
    printf("  AFTER (interface99):  ~35 lines (but vtable is auto-generated)\n");
    printf("  AFTER (with macros):  ~15 lines\n");
    printf("\n");
    
    printf("Features:\n");
    printf("  BEFORE:\n");
    printf("    + Virtual inheritance\n");
    printf("    + Simple C++ pattern\n");
    printf("    + Type-safe\n");
    printf("    - Requires vtable in every instance\n");
    printf("    - Inheritance-based (can be limiting)\n");
    printf("\n");
    printf("  AFTER:\n");
    printf("    + Composition over inheritance\n");
    printf("    + Explicit vtable (more control)\n");
    printf("    + Can implement multiple interfaces easily\n");
    printf("    + Works with plain structs\n");
    printf("    - More boilerplate without macros\n");
    printf("    - Different from Firefox patterns\n");
    printf("\n");
    
    printf("Missing from interface99:\n");
    printf("  ✗ No reference counting\n");
    printf("  ✗ No QueryInterface\n");
    printf("  ✗ No cycle collection\n");
    printf("  ✗ No thread safety checks\n");
    printf("  ✗ Not compatible with XPCOM\n");
    printf("\n");
    
    printf("When AFTER would be acceptable:\n");
    printf("  • Internal utility (no XPCOM needed)\n");
    printf("  • No JavaScript access required\n");
    printf("  • No reference counting needed\n");
    printf("  • Isolated subsystem\n");
    printf("  • Test utilities\n");
    printf("\n");
    
    printf("When to use BEFORE (traditional):\n");
    printf("  • Public API\n");
    printf("  • XPCOM integration needed\n");
    printf("  • Reference counting required\n");
    printf("  • QueryInterface needed\n");
    printf("  • Existing codebases (always!)\n");
    printf("\n");
}

// ============================================================
// VERDICT
// ============================================================

void printVerdict() {
    printf("╔════════════════════════════════════════════════════════╗\n");
    printf("║                    VERDICT                             ║\n");
    printf("╠════════════════════════════════════════════════════════╣\n");
    printf("║                                                        ║\n");
    printf("║  Partial replacement is TECHNICALLY POSSIBLE but       ║\n");
    printf("║  NOT RECOMMENDED for the following reasons:           ║\n");
    printf("║                                                        ║\n");
    printf("║  1. Loss of XPCOM features (refcounting, QI)          ║\n");
    printf("║  2. Two interface patterns in codebase (confusion)    ║\n");
    printf("║  3. Limited benefit for the added complexity          ║\n");
    printf("║  4. Existing pattern works well                       ║\n");
    printf("║  5. Risk of misuse by developers                      ║\n");
    printf("║                                                        ║\n");
    printf("║  RECOMMENDATION:                                       ║\n");
    printf("║  Keep using traditional patterns for ALL code.        ║\n");
    printf("║  Only consider interface99 for NEW, ISOLATED          ║\n");
    printf("║  utilities after thorough evaluation.                 ║\n");
    printf("║                                                        ║\n");
    printf("╚════════════════════════════════════════════════════════╝\n");
}

// ============================================================
// MAIN
// ============================================================

int main() {
    printf("╔════════════════════════════════════════════════════════╗\n");
    printf("║     Partial Replacement Experiment                    ║\n");
    printf("║     (Research purposes only - DO NOT USE)             ║\n");
    printf("╚════════════════════════════════════════════════════════╝\n\n");
    
    traditional::demonstrateBefore();
    experimental::demonstrateAfter();
    printAnalysis();
    printVerdict();
    
    return 0;
}

/*
 * NOTES FOR REVIEWERS:
 * 
 * This example shows that partial replacement is POSSIBLE but demonstrates
 * why it's NOT RECOMMENDED:
 * 
 * 1. The "after" version is more complex without real benefit
 * 2. Missing critical XPCOM features
 * 3. Would introduce pattern confusion
 * 4. The traditional pattern is simpler and more maintainable
 * 
 * CONCLUSION: Keep using traditional patterns. The libraries are interesting
 * but not beneficial enough to justify introduction to the codebase.
 */
