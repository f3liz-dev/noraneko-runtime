// Practical comparison of Current vs Metalang99 approaches
#include <stdio.h>

// ========== CURRENT RLBOX APPROACH ==========
// Simulated RLBox reflection macros
#define FIELD_NORMAL 0

// Traditional approach: Verbose macro definitions
#define current_reflect_packet_fields(f, g, ...) \
  f(unsigned char *, data     , FIELD_NORMAL, ##__VA_ARGS__) g() \
  f(long           , size     , FIELD_NORMAL, ##__VA_ARGS__) g() \
  f(long           , timestamp, FIELD_NORMAL, ##__VA_ARGS__) g()

// Manual counting of fields
#define CURRENT_PACKET_FIELD_COUNT 3

// Struct definition (still manual)
typedef struct {
    unsigned char* data;
    long size;
    long timestamp;
} current_packet_t;

// Helper to print field info (manual implementation)
#define PRINT_FIELD(type, name, flag, ...) \
  printf("  Field: %s (type: %s)\n", #name, #type);

void current_approach_demo() {
    printf("=== Current RLBox Reflection Approach ===\n");
    printf("Packet structure fields:\n");
    current_reflect_packet_fields(PRINT_FIELD, ML99_empty)
    printf("Total fields: %d (manually tracked)\n\n", CURRENT_PACKET_FIELD_COUNT);
}

// ========== METALANG99 APPROACH ==========
#include <metalang99.h>

// More concise field list definition
#define PACKET_FIELDS_ML99 \
  v((unsigned char *, data)), \
  v((long, size)), \
  v((long, timestamp))

// Automatic field counting using metalang99
#define PACKET_FIELD_COUNT \
  ML99_unwrap(ML99_listLen(ML99_list(PACKET_FIELDS_ML99)))

// Generate field names using metalang99 list operations
#define FIELD_PAIR_GET_NAME(pair) ML99_tupleGet(v(1), pair)

#define PRINT_ML99_FIELD(field_def) \
  v(printf("  Field: %s\n", ML99_stringify(ML99_unwrap(ML99_tupleGet(v(1), field_def))));)

typedef struct {
    unsigned char* data;
    long size;
    long timestamp;
} ml99_packet_t;

void metalang99_approach_demo() {
    printf("=== Metalang99 Reflection Approach ===\n");
    printf("Packet structure fields:\n");
    
    // Use metalang99 to iterate over fields
    ML99_listForEach(
        v(PRINT_ML99_FIELD),
        ML99_list(PACKET_FIELDS_ML99)
    )
    
    printf("Total fields: %d (automatically computed)\n\n", PACKET_FIELD_COUNT);
}

// ========== COMPARISON SUMMARY ==========
int main(void) {
    printf("COMPARISON: Current RLBox vs Metalang99 Reflection\n");
    printf("====================================================\n\n");
    
    current_approach_demo();
    metalang99_approach_demo();
    
    printf("Key Differences:\n");
    printf("1. Conciseness: Metalang99 reduces boilerplate\n");
    printf("2. Type Safety: Metalang99 provides compile-time validation\n");
    printf("3. Maintainability: Field count auto-computed in metalang99\n");
    printf("4. Composability: Metalang99 list operations more flexible\n");
    printf("5. Learning Curve: Current approach is simpler but less powerful\n");
    
    return 0;
}
