/*
 Bedrockifier

 Copyright (c) 2021 Adam Thayer
 Licensed under the MIT license, as follows:

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
 */

import Foundation
import Logging
import PTYKit

private let usePty = false
private let logger = Logger(label: "BedrockifierCLI:WorldBackup")

public class WorldBackup {
    enum Action {
        case keep
        case trim
    }

    var action: Action = .keep
    let modificationDate: Date
    let world: World

    init(world: World, date: Date) {
        self.modificationDate = date
        self.world = world
    }
}

extension WorldBackup {
    public static func fixOwnership(at folder: URL, config: OwnershipConfig) throws {
        let (uid, gid) = try config.parseOwnerAndGroup()
        let (permissions) = try config.parsePosixPermissions()
        let backups = try getBackups(at: folder)
        for backup in backups.flatMap({ $1 }) {
            try backup.world.applyOwnership(owner: uid, group: gid, permissions: permissions)
        }
    }

    public static func trimBackups(at folder: URL, dryRun: Bool, trimDays: Int?, keepDays: Int?, minKeep: Int?) throws {
        let trimDays = trimDays ?? 3
        let keepDays = keepDays ?? 14
        let minKeep = minKeep ?? 1

        let deletingString = dryRun ? "Would Delete" : "Deleting"

        let backups = try WorldBackup.getBackups(at: folder)
        for (worldName, worldBackups) in backups {
            Library.log.debug("Processing: \(worldName)")
            let processedBackups = worldBackups.process(trimDays: trimDays, keepDays: keepDays, minKeep: minKeep)
            for processedBackup in processedBackups.filter({ $0.action == .trim }) {
                Library.log.info("\(deletingString): \(processedBackup.world.location.lastPathComponent)")
                if !dryRun {
                    do {
                        try FileManager.default.removeItem(at: processedBackup.world.location)
                    } catch {
                        Library.log.error("Unable to delete \(processedBackup.world.location)")
                    }
                }
            }
        }
    }

    static func getBackups(at folder: URL) throws -> [String: [WorldBackup]] {
        var results: [String: [WorldBackup]] = [:]

        let keys: [URLResourceKey] = [.contentModificationDateKey]

        let files = try FileManager.default.contentsOfDirectory(at: folder,
                                                                includingPropertiesForKeys: keys,
                                                                options: [])

        for possibleWorld in files {
            let resourceValues = try possibleWorld.resourceValues(forKeys: Set(keys))
            let modificationDate = resourceValues.contentModificationDate!
            if let world = try? World(url: possibleWorld) {
                var array = results[world.name] ?? []
                array.append(WorldBackup(world: world, date: modificationDate))
                results[world.name] = array
            }
        }

        return results
    }
}

extension Array where Element: WorldBackup {
    func trimBucket(keepLast count: Int = 1) {
        var keep: [Int] = []

        for (index, item) in self.enumerated() {
            if keep.count < count {
                keep.append(index)
                continue
            }

            for (keepIndex, keepItem) in keep.enumerated() {
                if self[keepItem].modificationDate < item.modificationDate {
                    keep[keepIndex] = index
                    self[keepItem].action = .trim
                    Library.log.debug("Ejecting \(self[keepItem].world.location.lastPathComponent) from keep list")
                } else {
                    Library.log.debug("Rejecting \(item.world.location.lastPathComponent) from keep list")
                    item.action = .trim
                }
            }
        }
    }

    func process(trimDays: Int, keepDays: Int, minKeep: Int) -> [WorldBackup] {
        let trimDays = DateComponents(day: -(trimDays - 1))
        let keepDays = DateComponents(day: -(keepDays - 1))
        let today = Calendar.current.date(from: Date().toDayComponents())!
        let trimDay = Calendar.current.date(byAdding: trimDays, to: today)!
        let keepDay = Calendar.current.date(byAdding: keepDays, to: today)!

        // Sort from oldest to newest first
        let modifiedBackups = self.sorted(by: { $0.modificationDate > $1.modificationDate })

        // Mark very old backups, but also bucket for trimming to dailies
        var buckets: [DateComponents: [WorldBackup]] = [:]
        for backup in modifiedBackups {
            if backup.modificationDate < keepDay {
                backup.action = .trim
            } else if backup.modificationDate < trimDay {
                let modificationDay = backup.modificationDate.toDayComponents()
                var bucket = buckets[modificationDay] ?? []
                bucket.append(backup)
                buckets[modificationDay] = bucket
            }
        }

        // Process Buckets
        for (bucketComponents, bucket) in buckets {
            Library.log.debug("Trimming a Bucket: \(bucketDateString(bucketComponents))")
            bucket.trimBucket()
        }

        // Go back and force any backups to be retained if required
        let keepCount = modifiedBackups.reduce(0, { $0 + ($1.action == .keep ? 1 : 0)})
        var forceKeepCount = Swift.min(modifiedBackups.count, Swift.max(minKeep - keepCount, 0))
        if forceKeepCount > 0 {
            for backup in modifiedBackups {
                if backup.action != .keep {
                    backup.action = .keep
                    forceKeepCount -= 1
                }
                if forceKeepCount <= 0 {
                    break
                }
            }
        }

        return modifiedBackups
    }

    private func bucketDateString(_ dateComponents: DateComponents) -> String {
        let bucketDate = Calendar.current.nextDate(
            after: Date(),
            matching: dateComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward)
        if let realDate = bucketDate {
            return Library.dayFormatter.string(from: realDate)
        }

        return "<<UNKNOWN DATE>>"
    }
}
