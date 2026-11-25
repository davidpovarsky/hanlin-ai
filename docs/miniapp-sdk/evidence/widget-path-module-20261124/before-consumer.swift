import HanlinPlatformContracts

public func presentationPathIsNormalized(_ sourcePath: String) -> Bool {
    HanlinArchivePolicy.normalizedRelativePath(sourcePath) == sourcePath
}
