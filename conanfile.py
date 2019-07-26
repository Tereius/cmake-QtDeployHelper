from conans import ConanFile


class QtDeployHelper(ConanFile):
    name = "QtDeployHelper"
    version = "1.0.0"
    license = "The Unlicense"
    url = "https://github.com/Tereius/cmake-QtDeployHelper.git"
    description = "CMake files that help deploy a Qt5 based app to different platforms"
    author = "Björn Stresing"
    homepage = "https://cmake.org/"
    settings = "os"
    exports = "LICENSE"
    exports_sources = "*"

    def package(self):
        self.copy("*", src="Common", dst="CMake")
        if self.settings.os == "Android":
            self.copy("*", src="Android", dst="CMake")
        elif self.settings.os == "Emscripten":
            self.copy("*", src="Emscripten", dst="CMake")
        else:
            self.output.warn("This os is not supported: " + self.settings.os)
            
    def package_info(self):
        self.cpp_info.builddirs = ["CMake"]
