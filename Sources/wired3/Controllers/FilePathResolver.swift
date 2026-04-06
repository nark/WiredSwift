import Foundation

enum FileSystemLinkKind: Equatable {
    case none
    case symlink
    case macAlias
}

struct ResolvedVirtualPath: Equatable {
    let normalizedVirtualPath: String
    let joinedRealPath: String
    let resolvedRealPath: String
    let linkKind: FileSystemLinkKind
}

extension FilesController {
    func normalizeVirtualPath(_ path: String) -> String {
        NSString(string: path).standardizingPath
    }

    func resolvedVirtualPath(for path: String) -> ResolvedVirtualPath {
        let normalizedVirtualPath = normalizeVirtualPath(path)
        let joinedRealPath = real(path: normalizedVirtualPath)
        let resolvedRealPath = resolveAliasesAndSymlinks(in: joinedRealPath)
        let linkKind = exactLinkKind(atPath: joinedRealPath)

        return ResolvedVirtualPath(
            normalizedVirtualPath: normalizedVirtualPath,
            joinedRealPath: joinedRealPath,
            resolvedRealPath: resolvedRealPath,
            linkKind: linkKind
        )
    }

    func resolvedVirtualPathByResolvingParent(for path: String) -> ResolvedVirtualPath {
        let normalizedVirtualPath = normalizeVirtualPath(path)
        let joinedRealPath = real(path: normalizedVirtualPath)
        let lastComponent = URL(fileURLWithPath: joinedRealPath).lastPathComponent
        let joinedParentPath = URL(fileURLWithPath: joinedRealPath).deletingLastPathComponent().path
        let resolvedParentPath = resolveAliasesAndSymlinks(in: joinedParentPath)
        let resolvedRealPath = URL(fileURLWithPath: resolvedParentPath).appendingPathComponent(lastComponent).path

        return ResolvedVirtualPath(
            normalizedVirtualPath: normalizedVirtualPath,
            joinedRealPath: joinedRealPath,
            resolvedRealPath: resolvedRealPath,
            linkKind: .none
        )
    }

    func resolveAliasesAndSymlinks(in path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let components = NSString(string: standardizedPath).pathComponents
        var current = components.first == "/" ? "/" : ""

        for component in components {
            if component.isEmpty || component == "/" {
                if current.isEmpty {
                    current = "/"
                }
                continue
            }

            current = URL(fileURLWithPath: current).appendingPathComponent(component).path

            #if os(macOS)
            let currentURL = URL(fileURLWithPath: current)
            if let values = try? currentURL.resourceValues(forKeys: [.isAliasFileKey]),
               values.isAliasFile == true,
               let resolvedAliasURL = try? URL(resolvingAliasFileAt: currentURL, options: [] as URL.BookmarkResolutionOptions) {
                current = resolvedAliasURL.standardizedFileURL.path
                continue
            }
            #endif

            current = URL(fileURLWithPath: current).resolvingSymlinksInPath().standardized.path
        }

        return URL(fileURLWithPath: current).standardizedFileURL.path
    }

    func exactLinkKind(atPath path: String) -> FileSystemLinkKind {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil {
            return .symlink
        }

        let url = URL(fileURLWithPath: path)

        #if os(macOS)
        if let values = try? url.resourceValues(forKeys: [.isAliasFileKey]),
           values.isAliasFile == true {
            return .macAlias
        }
        #endif

        return .none
    }
}
