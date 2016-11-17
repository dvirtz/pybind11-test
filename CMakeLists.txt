cmake_minimum_required(VERSION 2.8)

project(pybind11-test)

set(PYBIND11_PYTHON_VERSION 2.7)
add_subdirectory(pybind11)

add_executable(pybind11-test test.cpp)

target_include_directories(pybind11-test PRIVATE 
	${PYBIND11_INCLUDE_DIR}
	${PYTHON_INCLUDE_DIRS})

target_link_libraries(pybind11-test PRIVATE ${PYTHON_LIBRARIES})

enable_testing()

add_test(pybind11-test pybind11-test)