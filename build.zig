const std = @import("std");

// TODO: We can't use ext/raylib/src/build.zig because for unknown reasons
// the compilation fails due to a missing X11/Xlib.h when cross compiling
// for a different version of glibc ie)
// -Dtarget=x86_64-linux-gnu.2.17 
//

fn buildRaylib(b: *std.build.Builder) *std.build.RunStep {
    const cmake = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "-B",
        "ext/raylib/build",
        "-S",
        "ext/raylib",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DOpenGL_GL_PREFERENCE=GLVND",
        "-DBUILD_EXAMPLES=OFF",
    });
    const cmake_build = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "--build",
        "ext/raylib/build",
        "--",
        "-j",
        "16",
    });
    cmake_build.step.dependOn(&cmake.step);
    return cmake_build;
}

fn buildCurl(b: *std.build.Builder) *std.build.RunStep {
    const cmake = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "-B",
        "ext/curl/build",
        "-S",
        "ext/curl",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DHTTP_ONLY=ON",
        "-DBUILD_CURL_EXE=OFF",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCURL_ENABLE_SSL=OFF",
        "-DCURL_USE_LIBSSH2=OFF",
        "-DCURL_USE_LIBSSH=OFF",
        "-DCURL_ZLIB=OFF",
    });
    const cmake_build = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "--build",
        "ext/curl/build",
        "--",
        "-j",
        "16",
    });
    cmake_build.step.dependOn(&cmake.step);
    return cmake_build;
}

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const build_ext = b.step("build-ext", "Build External Dependencies");
    build_ext.dependOn(&buildCurl(b).step);
    build_ext.dependOn(&buildRaylib(b).step);

    const exe = b.addExecutable("sandfarm", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addIncludePath("ext/raylib/src");
    exe.addObjectFile("ext/raylib/build/raylib/libraylib.a");
    exe.addIncludePath("ext/curl/include");
    exe.addLibraryPath("ext/curl/build/lib");
    exe.linkSystemLibraryName("curl");
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/tests.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    exe_tests.addIncludePath("ext/raylib/src");
    exe_tests.addObjectFile("ext/raylib/build/raylib/libraylib.a");
    exe_tests.linkLibC();

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
