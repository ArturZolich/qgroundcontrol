# ============================================================================
# Utilities Module
# Core utilities, logging, file system helpers, and platform abstractions
# ============================================================================

# ----------------------------------------------------------------------------
# Core Utility Sources
# ----------------------------------------------------------------------------
target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
<<<<<<< HEAD
        SpectralLogController.cc
        SpectralLogController.h
        DeviceInfo.cc
        DeviceInfo.h
        JsonHelper.cc
        JsonHelper.h
        FileSystem/QGCCachedFileDownload.cc
        FileSystem/QGCCachedFileDownload.h
        FileSystem/QGCFileDownload.cc
        FileSystem/QGCFileDownload.h
        FileSystem/QGCFileHelper.cc
        FileSystem/QGCFileHelper.h
        FileSystem/QGCArchiveWatcher.cc
        FileSystem/QGCArchiveWatcher.h
        FileSystem/QGCFileWatcher.cc
        FileSystem/QGCFileWatcher.h
        FileSystem/QGCFileWriter.cc
        FileSystem/QGCFileWriter.h
        QGC.cc
        QGC.h
=======
        AppMessages.cc
        AppMessages.h
>>>>>>> master
        QGCCommandLineParser.cc
        QGCCommandLineParser.h
)

target_include_directories(${CMAKE_PROJECT_NAME}
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        Compression
)

# ============================================================================
# Utility Subdirectories
# ============================================================================

add_subdirectory(Logging)
add_subdirectory(Audio)
add_subdirectory(Compression)
add_subdirectory(Database)
add_subdirectory(FileSystem)
add_subdirectory(Format)
add_subdirectory(Geo)
add_subdirectory(Math)
add_subdirectory(Network)
add_subdirectory(Parsing)
add_subdirectory(Platform)
add_subdirectory(SDL)
add_subdirectory(Sensors)
add_subdirectory(StateMachine)
