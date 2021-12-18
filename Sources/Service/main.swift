//
//  main.swift
//  BackupTrimmer
//
//  Created by Alex Hadden on 4/5/21.
//

import ArgumentParser
import Foundation
import Logging

import Bedrockifier

struct Server: ParsableCommand {
    private static let logger = Logger(label: "bedrockifier")

    @Argument(help: "Path to the config file")
    var configPath: String

    @Option(name: .shortAndLong, help: "Path to docker")
    var dockerPath: String?

    @Option(name: .shortAndLong, help: "Folder to write backups to")
    var backupPath: String?

    @Flag(help: "Log debug level information")
    var debug = false

    @Flag(help: "Log trace level information, overriding --debug")
    var trace = false

    mutating func run() throws {
        // Update Logging Level
        if trace {
            ConsoleLogger.logLevelOverride = .trace
            ConsoleLogger.showFilePosition = true
        } else if debug {
            ConsoleLogger.logLevelOverride = .debug
            ConsoleLogger.showFilePosition = true
        }

        Server.logger.info("Initializing Bedrockifier Daemon")

        let configUri = URL(fileURLWithPath: self.configPath)

        guard FileManager.default.fileExists(atPath: configUri.path) else {
            Server.logger.error("Configuration file doesn't exist at path \(configUri.path)")
            return
        }

        guard let config = try? BackupConfig.getBackupConfig(from: configUri) else {
            Server.logger.error("Unable to read configuration file, fix the above errors and try again")
            return
        }

        guard let backupPath = self.backupPath ?? config.backupPath else {
            Server.logger.error("Backup path needs to be specified on command-line or config file")
            return
        }

        guard FileManager.default.fileExists(atPath: backupPath) else {
            Server.logger.error("Backup folder not found at path \(backupPath)")
            return
        }

        guard let dockerPath = self.dockerPath ?? config.dockerPath else {
            Server.logger.error("Docker path needs to be specified on command-line or config file")
            return
        }

        guard FileManager.default.fileExists(atPath: dockerPath) else {
            Server.logger.error("Docker not found at path \(dockerPath)")
            return
        }

        Server.logger.info("Configuration Loaded, Entering Event Loop...")

        // TODO: In service mode, we need to load a configuration on how often we want to backup, and create a timer for it

        // Start Event Loop
        dispatchMain()
    }

    private func readBackupConfig(from uri: URL) -> BackupConfig? {
        do {
            return try BackupConfig.getBackupConfig(from: uri)
        } catch let error {
            Server.logger.error("\(error.localizedDescription)")
        }

        return nil
    }
}

// Initialize Service
ConsoleLogger.showDetails = true
LoggingSystem.bootstrap(ConsoleLogger.init)
Server.main()