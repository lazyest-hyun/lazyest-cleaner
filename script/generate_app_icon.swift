#!/usr/bin/env swift
import Foundation
guard let output = CommandLine.arguments.dropFirst().first else { exit(64) }
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", root.appendingPathComponent("scripts/generate-brand-icon.swift").path, "cleaner", output]
try process.run(); process.waitUntilExit(); exit(process.terminationStatus)
