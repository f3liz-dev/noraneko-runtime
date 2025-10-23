# Makefile for reflect research examples

CXX_20 = clang++
CXXFLAGS_20 = -std=c++20 -Wall -Wextra -I.
CXXFLAGS_SIMPLE = -std=c++11 -Wall -Wextra

# Disable reflect tests for faster compilation
CXXFLAGS_20_FAST = $(CXXFLAGS_20) -DNTEST

.PHONY: all clean run test

all: simple_demo practical_example

# Simple demo works with older C++ standards
simple_demo: simple_demo.cpp
	$(CXX_20) $(CXXFLAGS_SIMPLE) -o simple_demo simple_demo.cpp

# Practical example requires C++20 and reflect library
practical_example: practical_example.cpp
	$(CXX_20) $(CXXFLAGS_20_FAST) -o practical_example practical_example.cpp

# Run all examples
run: all
	@echo "=== Running Simple Demo ==="
	./simple_demo
	@echo ""
	@echo "=== Running Practical Example ==="
	./practical_example

# Test compilation times
test:
	@echo "Testing compilation time with reflect..."
	@time $(CXX_20) $(CXXFLAGS_20) -DNTEST -c reflect -x c++ -o /tmp/reflect_test.o
	@echo ""
	@echo "Reflect header compiled successfully!"

clean:
	rm -f simple_demo practical_example *.o
