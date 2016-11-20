#include <pybind11/pybind11.h>
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
    }
    catch (py::error_already_set& e)
    {
        std::cerr << e.what() << '\n';
    }
}