the old libcrsqlite.{dylib,so,dll} build(s) of the old rust cr-sqlite implementation was chonkier than sqlite itself
i believe this is because rust includes some about of runtime stuff that gets included in the build
i expect that a properly optimized build of our zig-based re-implementation should be significantly smaller than sqlite itself
if our zig build is big, that smells like we screwed something up somehow
that, or I'm confused about something
