// OS detection struct for the cz module
// This provides runtime OS information

#ifndef CZ_OS_H
#define CZ_OS_H

#include <stdbool.h>
#include <string.h>

#ifdef __linux__
    #include <sys/utsname.h>
#endif

#ifdef _WIN32
    #define CZ_OS_WINDOWS 1
    #define CZ_OS_LINUX 0
    #define CZ_OS_MACOS 0
#elif __APPLE__
    #include <TargetConditionals.h>
    #if TARGET_OS_MAC
        #define CZ_OS_MACOS 1
        #define CZ_OS_LINUX 0
        #define CZ_OS_WINDOWS 0
    #endif
#elif __linux__
    #define CZ_OS_LINUX 1
    #define CZ_OS_WINDOWS 0
    #define CZ_OS_MACOS 0
#else
    #define CZ_OS_LINUX 0
    #define CZ_OS_WINDOWS 0
    #define CZ_OS_MACOS 0
#endif

// Undefine potentially conflicting system macros
#ifdef linux
#undef linux
#endif
#ifdef unix
#undef unix
#endif
#ifdef windows
#undef windows
#endif

// OS struct definition - internal type with _cz_ prefix
typedef struct {
    const char* name;      // "linux", "windows", "macos", etc.
    const char* version;   // kernel version string only
    const char* kernel;    // kernel name lowercased ("linux", "darwin", "windows", etc.)
    bool linux;            // true if running on Linux
    bool windows;          // true if running on Windows
    bool macos;            // true if running on macOS
} cz_os;

// Global OS instance
static cz_os _cz_os;
static bool _cz_os_initialized = false;

// Initialize OS detection - called once on first access
// Internal function with _cz_ prefix
static void cz_os_init() {
    if (_cz_os_initialized) {
        return;
    }
    _cz_os_initialized = true;

    #if CZ_OS_WINDOWS
        _cz_os.name = "windows";
        _cz_os.linux = false;
        _cz_os.windows = true;
        _cz_os.macos = false;
        _cz_os.kernel = "windows";
        // On Windows, we could use GetVersionEx but it's deprecated
        // For simplicity, we'll just use a generic version string
        _cz_os.version = "unknown";
    #elif CZ_OS_MACOS
        _cz_os.name = "macos";
        _cz_os.linux = false;
        _cz_os.windows = false;
        _cz_os.macos = true;
        _cz_os.kernel = "darwin";
        // On macOS, we could use uname or sysctl
        _cz_os.version = "unknown";
    #elif CZ_OS_LINUX
        _cz_os.name = "linux";
        _cz_os.linux = true;
        _cz_os.windows = false;
        _cz_os.macos = false;
        _cz_os.kernel = "linux";

        // Try to get kernel version using uname
        struct utsname buffer;
        if (uname(&buffer) == 0) {
            // Allocate static buffer for version string
            static char version_buf[256];
            // Safely copy release version (just the version, not the sysname)
            size_t release_len = strlen(buffer.release);
            if (release_len >= sizeof(version_buf)) {
                release_len = sizeof(version_buf) - 1;
            }
            memcpy(version_buf, buffer.release, release_len);
            version_buf[release_len] = '\0';

            _cz_os.version = version_buf;
        } else {
            _cz_os.version = "unknown";
        }
    #else
        _cz_os.name = "unknown";
        _cz_os.linux = false;
        _cz_os.windows = false;
        _cz_os.macos = false;
        _cz_os.kernel = "unknown";
        _cz_os.version = "unknown";
    #endif
}

// Get OS struct - returns pointer to OS data
// Raw C function with _cz_ prefix, called from generated code
// NOTE: cz_os_init() must be called via #init macro before accessing this
static inline cz_os* cz_os_get() {
    return &_cz_os;
}

#endif // CZ_OS_H
