cmake_minimum_required(VERSION 3.16)

project(zinc VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_AUTOMOC ON)

# Options
option(ZINC_BUILD_TESTS "Build unit tests" OFF)
option(ZINC_USE_SQLCIPHER "Use SQLCipher for database encryption" OFF)
option(ZINC_USE_SYSTEM_SODIUM "Use system libsodium" OFF)

# Find Qt packages
find_package(Qt6 REQUIRED COMPONENTS Quick Sql Network)

qt_standard_project_setup(REQUIRES 6.8)

# Find system dependencies (optional)
find_package(PkgConfig QUIET)

# SQLite setup
set(SQLITE_LIBRARIES "")
set(SQLITE_INCLUDE_DIRS "")
set(USE_BUNDLED_SQLITE OFF)

if(ANDROID)
    # Always use bundled SQLite on Android
    set(USE_BUNDLED_SQLITE ON)
elseif(PkgConfig_FOUND)
    # SQLite (or SQLCipher) - optional, use system if available
    if(ZINC_USE_SQLCIPHER)
        pkg_check_modules(SQLCIPHER sqlcipher)
        if(SQLCIPHER_FOUND)
            set(SQLITE_LIBRARIES ${SQLCIPHER_LIBRARIES})
            set(SQLITE_INCLUDE_DIRS ${SQLCIPHER_INCLUDE_DIRS})
            add_compile_definitions(ZINC_USE_SQLCIPHER)
        else()
            set(USE_BUNDLED_SQLITE ON)
        endif()
    else()
        pkg_check_modules(SQLITE3 sqlite3)
        if(SQLITE3_FOUND)
            set(SQLITE_LIBRARIES ${SQLITE3_LIBRARIES})
            set(SQLITE_INCLUDE_DIRS ${SQLITE3_INCLUDE_DIRS})
        else()
            set(USE_BUNDLED_SQLITE ON)
        endif()
    endif()
else()
    set(USE_BUNDLED_SQLITE ON)
endif()

# Bundled SQLite library (for Android and systems without system sqlite)
if(USE_BUNDLED_SQLITE)
    message(STATUS "Using bundled SQLite")
    add_library(sqlite3_bundled STATIC
        third_party/sqlite/sqlite3.c
    )
    target_include_directories(sqlite3_bundled PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/sqlite
    )
    # SQLite compile options for better performance
    target_compile_definitions(sqlite3_bundled PRIVATE
        SQLITE_ENABLE_FTS5
        SQLITE_ENABLE_JSON1
        SQLITE_THREADSAFE=2
        SQLITE_DEFAULT_MEMSTATUS=0
        SQLITE_DEFAULT_WAL_SYNCHRONOUS=1
        SQLITE_LIKE_DOESNT_MATCH_BLOBS
        SQLITE_OMIT_DEPRECATED
    )
    if(ANDROID)
        target_compile_definitions(sqlite3_bundled PRIVATE
            SQLITE_OS_UNIX=1
        )
    endif()
    set(SQLITE_LIBRARIES sqlite3_bundled)
    set(SQLITE_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/third_party/sqlite)
endif()

if(PkgConfig_FOUND AND NOT ANDROID)
    # libsodium for cryptography - optional for now
    if(ZINC_USE_SYSTEM_SODIUM)
        pkg_check_modules(SODIUM libsodium)
        if(SODIUM_FOUND)
            add_compile_definitions(ZINC_HAS_SODIUM)
        endif()
    endif()

    # Avahi for mDNS discovery (Linux desktop only)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        pkg_check_modules(AVAHI avahi-client)
        if(AVAHI_FOUND)
            add_compile_definitions(ZINC_HAS_AVAHI)
        endif()
    endif()
endif()

# Core library (pure business logic, no Qt dependencies where possible)
add_library(zinc_core STATIC
    src/core/result.hpp
    src/core/types.hpp
    src/core/types.cpp
    src/core/block_types.hpp
    src/core/block_types.cpp
    src/core/fractional_index.hpp
    src/core/fractional_index.cpp
    src/core/commands.hpp
    src/core/commands.cpp
    src/core/page.hpp
    src/core/page.cpp
    src/core/workspace.hpp
    src/core/workspace.cpp
    src/core/search.hpp
    src/core/search.cpp
)

target_include_directories(zinc_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_compile_features(zinc_core PUBLIC cxx_std_20)

# Storage library (SQLite layer)
add_library(zinc_storage STATIC
    src/storage/database.hpp
    src/storage/database.cpp
    src/storage/migrations.hpp
    src/storage/migrations.cpp
    src/storage/block_repository.hpp
    src/storage/block_repository.cpp
    src/storage/page_repository.hpp
    src/storage/page_repository.cpp
    src/storage/workspace_repository.hpp
    src/storage/workspace_repository.cpp
    src/storage/crdt_repository.hpp
    src/storage/crdt_repository.cpp
)

target_include_directories(zinc_storage PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${SQLITE_INCLUDE_DIRS}
)

target_link_libraries(zinc_storage PUBLIC
    zinc_core
    ${SQLITE_LIBRARIES}
)

# Crypto library (libsodium wrapper)
add_library(zinc_crypto STATIC
    src/crypto/keys.hpp
    src/crypto/keys.cpp
    src/crypto/encryption.hpp
    src/crypto/encryption.cpp
    src/crypto/noise_session.hpp
    src/crypto/noise_session.cpp
)

target_include_directories(zinc_crypto PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if(SODIUM_FOUND)
    target_include_directories(zinc_crypto PUBLIC ${SODIUM_INCLUDE_DIRS})
    target_link_libraries(zinc_crypto PUBLIC ${SODIUM_LIBRARIES})
endif()

target_link_libraries(zinc_crypto PUBLIC
    zinc_core
)

# Network library (discovery + sync)
add_library(zinc_network STATIC
    src/network/discovery.hpp
    src/network/discovery.cpp
    src/network/transport.hpp
    src/network/transport.cpp
    src/network/sync_manager.hpp
    src/network/sync_manager.cpp
    src/network/pairing.hpp
    src/network/pairing.cpp
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND NOT ANDROID AND AVAHI_FOUND)
    target_sources(zinc_network PRIVATE
        src/platform/linux/avahi_discovery.cpp
    )
    target_include_directories(zinc_network PRIVATE ${AVAHI_INCLUDE_DIRS})
    target_link_libraries(zinc_network PRIVATE ${AVAHI_LIBRARIES})
endif()

target_include_directories(zinc_network PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(zinc_network PUBLIC
    zinc_core
    zinc_crypto
    Qt6::Network
)

# UI library (Qt/QML bridge)
add_library(zinc_ui STATIC
    src/ui/qml_types.hpp
    src/ui/qml_types.cpp
    src/ui/DataStore.hpp
    src/ui/DataStore.cpp
    src/ui/models/BlockModel.hpp
    src/ui/models/BlockModel.cpp
    src/ui/models/PageTreeModel.hpp
    src/ui/models/PageTreeModel.cpp
    src/ui/models/SearchResultModel.hpp
    src/ui/models/SearchResultModel.cpp
    src/ui/controllers/EditorController.hpp
    src/ui/controllers/EditorController.cpp
    src/ui/controllers/SyncController.hpp
    src/ui/controllers/SyncController.cpp
    src/ui/controllers/PairingController.hpp
    src/ui/controllers/PairingController.cpp
)

target_include_directories(zinc_ui PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(zinc_ui PUBLIC
    Qt6::Sql
)

target_link_libraries(zinc_ui PUBLIC
    zinc_core
    zinc_storage
    zinc_network
    Qt6::Quick
)

# Main executable
qt_add_executable(appzinc
    src/main.cpp
)

# Mark ThemeManager as a singleton BEFORE qt_add_qml_module
set_source_files_properties(qml/theme/ThemeManager.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(appzinc
    URI zinc
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/BlockEditor.qml
        qml/components/Block.qml
        qml/components/blocks/ParagraphBlock.qml
        qml/components/blocks/HeadingBlock.qml
        qml/components/blocks/TodoBlock.qml
        qml/components/blocks/CodeBlock.qml
        qml/components/blocks/QuoteBlock.qml
        qml/components/blocks/DividerBlock.qml
        qml/components/blocks/ToggleBlock.qml
        qml/components/blocks/LinkBlock.qml
        qml/components/SlashMenu.qml
        qml/components/PageTree.qml
        qml/components/SearchDialog.qml
        qml/dialogs/PairingDialog.qml
        qml/dialogs/QRCodeDialog.qml
        qml/dialogs/SettingsDialog.qml
        qml/dialogs/PagePickerDialog.qml
        qml/theme/Theme.qml
        qml/theme/ThemeManager.qml
    SOURCES
        src/ui/qml_types.hpp
        src/ui/qml_types.cpp
)

set_target_properties(appzinc PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appzinc PRIVATE
    zinc_ui
    zinc_storage
    zinc_network
    zinc_crypto
    Qt6::Quick
    Qt6::Sql
)

include(GNUInstallDirs)
install(TARGETS appzinc
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Testing
if(ZINC_BUILD_TESTS)
    enable_testing()
    
    # Fetch Catch2
    include(FetchContent)
    FetchContent_Declare(
        Catch2
        GIT_REPOSITORY https://github.com/catchorg/Catch2.git
        GIT_TAG v3.5.2
    )
    FetchContent_MakeAvailable(Catch2)
    
    # Fetch rapidcheck for property-based testing
    FetchContent_Declare(
        rapidcheck
        GIT_REPOSITORY https://github.com/emil-e/rapidcheck.git
        GIT_TAG master
    )
    FetchContent_MakeAvailable(rapidcheck)
    
    # Unit tests
    add_executable(zinc_tests
        tests/unit/test_main.cpp
        tests/unit/test_result.cpp
        tests/unit/test_block_types.cpp
        tests/unit/test_fractional_index.cpp
        tests/unit/test_commands.cpp
        tests/unit/test_storage.cpp
    )
    
    target_link_libraries(zinc_tests PRIVATE
        zinc_core
        zinc_storage
        Catch2::Catch2WithMain
    )
    
    target_include_directories(zinc_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${SQLITE_INCLUDE_DIRS}
    )
    
    # Property-based tests
    add_executable(zinc_property_tests
        tests/property/prop_main.cpp
        tests/property/prop_fractional_index.cpp
        tests/property/prop_crdt_convergence.cpp
    )
    
    target_link_libraries(zinc_property_tests PRIVATE
        zinc_core
        zinc_storage
        rapidcheck
        Catch2::Catch2WithMain
    )
    
    target_include_directories(zinc_property_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    
    # Integration tests
    add_executable(zinc_integration_tests
        tests/integration/test_main.cpp
        tests/integration/test_sync.cpp
        tests/integration/test_storage_roundtrip.cpp
    )
    
    target_link_libraries(zinc_integration_tests PRIVATE
        zinc_core
        zinc_storage
        zinc_network
        Catch2::Catch2WithMain
    )
    
    target_include_directories(zinc_integration_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    
    include(CTest)
    include(Catch)
    catch_discover_tests(zinc_tests)
    catch_discover_tests(zinc_property_tests)
    catch_discover_tests(zinc_integration_tests)
endif()
