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

// OS struct definition
typedef struct {
    const char* name;      // "linux", "windows", "macos", etc.
    const char* version;   // kernel version string
    const char* kernel;    // full kernel string (name + version)
    bool linux;            // true if running on Linux
    bool windows;          // true if running on Windows
    bool macos;            // true if running on macOS
} cz_os_t;

// Global OS instance
static cz_os_t __cz_os;
static bool __cz_os_initialized = false;

// Initialize OS detection - called once on first access
static void cz_os_init() {
    if (__cz_os_initialized) {
        return;
    }
    __cz_os_initialized = true;
    
    #if CZ_OS_WINDOWS
        __cz_os.name = "windows";
        __cz_os.linux = false;
        __cz_os.windows = true;
        __cz_os.macos = false;
        // On Windows, we could use GetVersionEx but it's deprecated
        // For simplicity, we'll just use a generic version string
        __cz_os.version = "unknown";
        __cz_os.kernel = "windows unknown";
    #elif CZ_OS_MACOS
        __cz_os.name = "macos";
        __cz_os.linux = false;
        __cz_os.windows = false;
        __cz_os.macos = true;
        // On macOS, we could use uname or sysctl
        __cz_os.version = "unknown";
        __cz_os.kernel = "darwin unknown";
    #elif CZ_OS_LINUX
        __cz_os.name = "linux";
        __cz_os.linux = true;
        __cz_os.windows = false;
        __cz_os.macos = false;
        
        // Try to get kernel version using uname
        struct utsname buffer;
        if (uname(&buffer) == 0) {
            // Allocate static buffers for version and kernel strings
            static char version_buf[256];
            static char kernel_buf[512];
            // Safely copy release version
            size_t release_len = strlen(buffer.release);
            if (release_len >= sizeof(version_buf)) {
                release_len = sizeof(version_buf) - 1;
            }
            memcpy(version_buf, buffer.release, release_len);
            version_buf[release_len] = '\0';
            
            // Safely construct kernel string (sysname + space + release)
            size_t sysname_len = strlen(buffer.sysname);
            size_t total_len = 0;
            if (sysname_len < sizeof(kernel_buf) - 1) {
                memcpy(kernel_buf, buffer.sysname, sysname_len);
                kernel_buf[sysname_len] = ' ';
                total_len = sysname_len + 1;
                
                size_t remaining = sizeof(kernel_buf) - total_len - 1;
                if (release_len > remaining) {
                    release_len = remaining;
                }
                memcpy(kernel_buf + total_len, buffer.release, release_len);
                total_len += release_len;
            }
            kernel_buf[total_len] = '\0';
            
            __cz_os.version = version_buf;
            __cz_os.kernel = kernel_buf;
        } else {
            __cz_os.version = "unknown";
            __cz_os.kernel = "linux unknown";
        }
    #else
        __cz_os.name = "unknown";
        __cz_os.linux = false;
        __cz_os.windows = false;
        __cz_os.macos = false;
        __cz_os.version = "unknown";
        __cz_os.kernel = "unknown unknown";
    #endif
}

// Get OS struct - initializes on first call
static inline cz_os_t* cz_os_get() {
    cz_os_init();
    return &__cz_os;
}

#endif // CZ_OS_H
