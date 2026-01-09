//
//  ArchitectureDetector.swift
//  TheQuickFox
//
//  Detects CPU architecture to optimize for Intel vs Apple Silicon.
//

import Foundation

enum ArchitectureDetector {

    /// Returns true if running on an Intel Mac (x86_64 architecture)
    static var isIntelMac: Bool = {
        #if arch(x86_64)
        print("🏛️ ArchitectureDetector: Compiled for x86_64")
        // Compiled for x86_64 - either native Intel or Rosetta on Apple Silicon
        // Check if running under Rosetta translation
        var isRosetta: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &isRosetta, &size, nil, 0)

        if result == 0 && isRosetta == 1 {
            // Running under Rosetta - actually Apple Silicon
            return false
        }
        // Native x86_64 - Intel Mac
        return true
        #else
        // ARM64 binary - Apple Silicon
        print("🏛️ ArchitectureDetector: Compiled for arm64 (Apple Silicon)")
        return false
        #endif
    }()

    /// Returns true if running on Apple Silicon
    static var isAppleSilicon: Bool {
        return !isIntelMac
    }
}
