cmake_minimum_required(VERSION 3.21)
project(torchform-gamepad LANGUAGES CXX)

# Out-of-tree QuickShell QML plugin: exposes a `Gamepad` singleton under the
# `Torchform.Gamepad` URI. Reads the torchform-inputd virtual pad via raw evdev
# (<linux/input.h>), so it needs only Qt6 Core+Qml and kernel headers — no
# libevdev/SDL. Kept independent of the QuickShell rebuild for fast iteration.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml)
qt_standard_project_setup()

qt_add_qml_module(torchform-gamepad
    URI Torchform.Gamepad
    VERSION 1.0
    # Lay the module out at <build>/Torchform/Gamepad/ so that adding <build> to
    # QML_IMPORT_PATH lets `import Torchform.Gamepad` resolve.
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/Torchform/Gamepad
    SOURCES
        gamepad.h
        gamepad.cpp
)

target_link_libraries(torchform-gamepad PRIVATE Qt6::Core Qt6::Qml)

# Build the QML module tree under build/Torchform/Gamepad. Point QuickShell at it
# with:  QML_IMPORT_PATH=<build-dir>  quickshell   (start-hdmi.sh exports this).
