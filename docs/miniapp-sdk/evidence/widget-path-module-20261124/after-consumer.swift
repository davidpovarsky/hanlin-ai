import HanlinPlatformContracts

public func presentationPathIsNormalized(_ sourcePath: String) -> Bool {
    HanlinPackagePath.normalizedRelativePath(sourcePath) == sourcePath
}
