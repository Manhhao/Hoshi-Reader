//
//  Merger.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated struct Merger {
    static func mergeStatistics(localStatistics: [Statistics], externalStatistics: [Statistics], syncMode: StatisticsSyncMode) -> [Statistics] {
        if syncMode == .replace {
            return externalStatistics
        }
        
        var grouped: [String: Statistics] = [:]
        
        for stat in localStatistics {
            grouped[stat.dateKey] = stat
        }
        
        for stat in externalStatistics {
            if let existing = grouped[stat.dateKey] {
                if stat.lastStatisticModified > existing.lastStatisticModified {
                    grouped[stat.dateKey] = stat
                }
            } else {
                grouped[stat.dateKey] = stat
            }
        }
        
        return Array(grouped.values)
    }
    
    static func mergeArray<T, S: Hashable>(
        local: [T],
        remote: [T],
        ancestor: [T],
        id: KeyPath<T, S>,
        isOnlyOrderChanged: ([S: T], [S: T]) -> Bool,
        mergeTwoNew: (T, T) -> T,
        threeWayMerge: (T, T, T) -> T,
    ) -> [T] {
        
        let localMap = Self.makeMap(array: local, id: id)
        let remoteMap = Self.makeMap(array: remote, id: id)
        let ancestorMap = Self.makeMap(array: ancestor, id: id)
        
        if isOnlyOrderChanged(localMap, remoteMap) {
            let localOrderChanged = isOnlyOrderChanged(localMap, ancestorMap)
            let remoteOrderChanged = isOnlyOrderChanged(remoteMap, ancestorMap)

            if localOrderChanged && !remoteOrderChanged {
                return local
            }
            return remote
        }
        
        let localNames = localMap.keys
        let remoteNames = remoteMap.keys
        let ancestorNames = ancestorMap.keys
        let allNames = Set(localNames).union(Set(remoteNames)).union(Set(ancestorNames))
        
        var mergedArray = [T]()
        
        for name in allNames {
            let nameInLocal = localMap[name] != nil
            let nameInRemote = remoteMap[name] != nil
            let nameInAncestor = ancestorMap[name] != nil
            
            switch (nameInAncestor, nameInLocal, nameInRemote) {
            case (false, true, false):
                mergedArray.append(
                    localMap[name]!
                )
            case (false, false, true):
                mergedArray.append(
                    remoteMap[name]!
                )
            case (false, true, true):
                mergedArray.append(
                    mergeTwoNew(localMap[name]!, remoteMap[name]!)
                )
            case (true, true, true):
                mergedArray.append(
                    threeWayMerge(localMap[name]!, remoteMap[name]!, ancestorMap[name]!)
                )
            default:
                break
            }
        }
        
        mergedArray.sort { (lhs: T, rhs: T) in
            let lhsInLocal = localMap[lhs[keyPath: id]] != nil
            let rhsInLocal = localMap[rhs[keyPath: id]] != nil
            if lhsInLocal && !rhsInLocal {
                return true
            } else if !lhsInLocal && rhsInLocal {
                return false
            } else if lhsInLocal && rhsInLocal {
                // we can not use `localNames` here since Swift dictionary does not ensure order
                let orderedLocalNames = local.map({$0[keyPath: id]})
                return orderedLocalNames.firstIndex(of: lhs[keyPath: id])! < orderedLocalNames.firstIndex(of: rhs[keyPath: id])!
            } else {
                let orderedRemoteNames = remote.map({$0[keyPath: id]})
                return orderedRemoteNames.firstIndex(of: lhs[keyPath: id])! < orderedRemoteNames.firstIndex(of: rhs[keyPath: id])!
            }
        }
        
        return mergedArray
    }
    
    static func shelvesOnlyOrderChanged(local: [String: BookShelf], remote: [String: BookShelf]) -> Bool {
        if local.count != remote.count {
            return false
        }
        for (name, lhsShelf) in local {
            guard let rhsShelf = remote[name] else { return false }
            if Set(lhsShelf.bookIds) != Set(rhsShelf.bookIds) { return false }
        }
        return true
    }
    
    static func mergeBookIds(
        local: [UUID],
        remote: [UUID],
        ancestor: [UUID],
    ) -> [UUID] {
        let allIds = Set(local).union(Set(remote)).union(Set(ancestor))
        let mergedIds = allIds.filter { bookID in
            if ancestor.contains(bookID) {
                return local.contains(bookID) && remote.contains(bookID)
            } else {
                return local.contains(bookID) || remote.contains(bookID)
            }
        }
        return Array(mergedIds)
    }
    
    private static func makeMap<T, S: Hashable>(array: [T], id: KeyPath<T, S>) -> [S: T] {
        var map: [S: T] = [:]
        
        for element in array {
            map[element[keyPath: id]] = element
        }
        
        return map
    }
}
