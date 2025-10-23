// Current RLBox reflection approach example
// Based on OggStructsForRLBox.h

#ifndef CURRENT_APPROACH_H
#define CURRENT_APPROACH_H

// Current approach: Manual macro definition for field reflection
// Pros: Explicit control, integrates with RLBox framework
// Cons: Verbose, manual maintenance, error-prone for complex structures

#if defined(__clang__)
#  pragma clang diagnostic push
#  pragma clang diagnostic ignored "-Wgnu-zero-variadic-macro-arguments"
#elif defined(__GNUC__) || defined(__GNUG__)
#  pragma GCC system_header
#endif

// Example: Simple packet structure
#define sandbox_fields_reflection_test_class_packet(f, g, ...) \
  f(unsigned char *, data     , FIELD_NORMAL, ##__VA_ARGS__) g() \
  f(long           , size     , FIELD_NORMAL, ##__VA_ARGS__) g() \
  f(long           , timestamp, FIELD_NORMAL, ##__VA_ARGS__) g()

// Example: State structure
#define sandbox_fields_reflection_test_class_state(f, g, ...) \
  f(int            , status   , FIELD_NORMAL, ##__VA_ARGS__) g() \
  f(unsigned char *, buffer   , FIELD_NORMAL, ##__VA_ARGS__) g() \
  f(int            , buf_size , FIELD_NORMAL, ##__VA_ARGS__) g()

// Register all classes
#define sandbox_fields_reflection_test_allClasses(f, ...) \
  f(packet, test, ##__VA_ARGS__)                          \
  f(state , test, ##__VA_ARGS__)

#if defined(__clang__)
#  pragma clang diagnostic pop
#endif

#endif // CURRENT_APPROACH_H
