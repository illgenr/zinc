#include "core/types.hpp"

// Implementation is entirely in the header for this simple types module.
// This file exists for build system compatibility.

namespace zinc {

// Static assertions to ensure type properties
static_assert(sizeof(Uuid) == 16, "Uuid should be 16 bytes");
static_assert(std::is_trivially_copyable_v<Uuid>, "Uuid should be trivially copyable");
static_assert(std::is_trivially_copyable_v<Timestamp>, "Timestamp should be trivially copyable");

} // namespace zinc

