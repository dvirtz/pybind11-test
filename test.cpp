#include <pybind11/pybind11.h>
#include <iostream>

int main()
{
    namespace py = pybind11;
    
    Py_Initialize();
    
    try
    {
        auto sys = py::module::import("sys");
        py::list pythonPath(sys.attr("path"));
        py::print(pythonPath);
    }
    catch (py::error_already_set& e)
    {
        std::cerr << e.what() << '\n';
    }
}