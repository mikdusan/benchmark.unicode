const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    b.setInstallPrefix(".");

    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("bench", "src/benchmark.zig");
    exe.setBuildMode(mode);

    exe.addIncludeDir("src");
    exe.addCSourceFile("src/atom.hoehrmann.c", [][]const u8{"-std=c11"});
    exe.addCSourceFile("src/atom.wellons.branchless.c", [][]const u8{"-std=c11"});
    exe.addCSourceFile("src/atom.wellons.simple.c", [][]const u8{"-std=c11"});

    const run_cmd = exe.run();

    const run_step = b.step("run", "perform benchmark cases");
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
