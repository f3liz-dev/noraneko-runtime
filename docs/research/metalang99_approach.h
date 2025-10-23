// Metalang99 + Datatype99 approach example
// Demonstrates potential improvements over current RLBox reflection

#ifndef METALANG99_APPROACH_H
#define METALANG99_APPROACH_H

#include <metalang99.h>
#include <datatype99.h>

// Approach using metalang99 for reflection
// Pros: Type-safe, less boilerplate, compile-time verification, maintainable
// Cons: Requires metalang99/datatype99 dependency, learning curve

// Define field types and metadata using metalang99 lists
#define PACKET_FIELDS \
  ML99_list(          \
    v((unsigned char *, data)),      \
    v((long, size)),                 \
    v((long, timestamp))             \
  )

#define STATE_FIELDS  \
  ML99_list(          \
    v((int, status)),                \
    v((unsigned char *, buffer)),    \
    v((int, buf_size))               \
  )

// Generate field reflection using metalang99 list operations
// This macro generates the same reflection info as the current approach
// but with type safety and compile-time verification

#define GENERATE_FIELD_REFLECTION(type_name, fields) \
  ML99_listForEach(                                  \
    ML99_appl(v(FIELD_REFLECTION_IMPL), v(type_name)), \
    fields                                           \
  )

// Helper to generate individual field reflection
#define FIELD_REFLECTION_IMPL(type_name, field_info) \
  ML99_INVOKE(                                       \
    EMIT_FIELD_REFLECTION,                           \
    v(type_name),                                    \
    ML99_tupleGet(v(0), v(field_info)),             \
    ML99_tupleGet(v(1), v(field_info))              \
  )

// Using datatype99 for variant types (sum types)
// This provides additional type safety for different packet types
datatype(
    PacketType,
    (DataPacket, unsigned char *, long),
    (ControlPacket, int),
    (AckPacket, long)
);

// Interface for packet handling
typedef struct {
    int (*process)(const void* packet_data, long size);
    void (*cleanup)(void* packet_data);
} PacketHandler;

// Example showing type-safe field access with compile-time validation
#define SAFE_FIELD_ACCESS(struct_type, field_name, ptr) \
  ML99_ASSERT(                                           \
    ML99_listContains(                                   \
      v(field_name),                                     \
      ML99_CAT(struct_type, _FIELDS)                    \
    )                                                    \
  )                                                      \
  ((ptr)->field_name)

#endif // METALANG99_APPROACH_H
