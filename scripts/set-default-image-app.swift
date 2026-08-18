#!/usr/bin/env swift
import Foundation
import CoreServices

// 把 Fovea 设成它声明的所有图片类型的默认打开方式。
//
// 用法：swift scripts/set-default-image-app.swift [应用路径]
// 不给路径时用 /Applications/Fovea.app。
//
// 重装应用会换掉 bundle 的签名和 inode，LaunchServices 把它当成新的一份记录，
// 原来「用 Fovea 打开」的绑定不一定跟过来。类型清单直接从应用自己的
// Info.plist 里读，声明里加了新格式，这里不用同步改。

let arguments = Array(CommandLine.arguments.dropFirst())
let applicationPath = arguments.first ?? "/Applications/Fovea.app"
let applicationURL = URL(fileURLWithPath: applicationPath)

guard FileManager.default.fileExists(atPath: applicationPath) else {
    FileHandle.standardError.write(Data("找不到应用：\(applicationPath)\n".utf8))
    exit(1)
}

guard let bundle = Bundle(url: applicationURL),
      let bundleIdentifier = bundle.bundleIdentifier else {
    FileHandle.standardError.write(Data("读不出 bundle 标识：\(applicationPath)\n".utf8))
    exit(1)
}

let documentTypes = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
let contentTypes = documentTypes
    .compactMap { $0["LSItemContentTypes"] as? [String] }
    .flatMap { $0 }
guard !contentTypes.isEmpty else {
    FileHandle.standardError.write(Data("Info.plist 里没有声明任何 LSItemContentTypes\n".utf8))
    exit(1)
}

var failures: [(type: String, status: OSStatus)] = []
var alreadyOurs = 0
var changed = 0

for contentType in contentTypes {
    let currentHandler = LSCopyDefaultRoleHandlerForContentType(
        contentType as CFString,
        LSRolesMask.all
    )?.takeRetainedValue() as String?

    if currentHandler?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
        alreadyOurs += 1
        continue
    }

    let status = LSSetDefaultRoleHandlerForContentType(
        contentType as CFString,
        LSRolesMask.all,
        bundleIdentifier as CFString
    )
    if status == noErr {
        changed += 1
    } else {
        failures.append((contentType, status))
    }
}

print("应用：\(applicationPath)")
print("标识：\(bundleIdentifier)")
print("声明的图片类型：\(contentTypes.count)")
print("本来就是默认：\(alreadyOurs)，这次改过来：\(changed)，失败：\(failures.count)")

for failure in failures {
    print("  失败 \(failure.type)（OSStatus \(failure.status)）")
}

exit(failures.isEmpty ? 0 : 1)
