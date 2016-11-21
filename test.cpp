#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <iostream>

int main()
{
    namespace py = pybind11;
    
    Py_Initialize();
    
    try
    {
        auto sys = py::module::import("sys");
        py::str version(sys.attr("version"));
        py::print(version);

        auto gmusicapi = py::module::import("gmusicapi");
        version = gmusicapi.attr("__version__");
        std::cout << "gmusicapi version " << version << '\n';
    }
    catch (py::error_already_set& e)
    {
        std::cerr << e.what() << '\n';
    }
}