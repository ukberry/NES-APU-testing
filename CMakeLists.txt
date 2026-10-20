cmake_minimum_required(VERSION 3.30)
project(nes-apu LANGUAGES ASM)

include(NesDefault.cmake)

add_executable(nes example.s)
nes_default(nes)
target_link_libraries(nes PRIVATE)