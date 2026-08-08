const header = @import("rpm_header");
const pkgfile = @import("rpm_pkgfile");

pub const FileHandle = struct {
    file: pkgfile.RpmFile,

    pub fn mainHeader(self: *const FileHandle) header.Header {
        return self.file.main;
    }
};
