import Foundation

/// 一轮采样中的物理身份与传输别名。名称只能经已知 MAC 的当前别名链关联，
/// 不把两个独立的已配对身份或带独立读数的未知 UUID 按同名合并。
nonisolated struct BluetoothDeviceIdentity {
    let profilerDevices: [BluetoothDeviceInfo]
    let pmsetDevices: [BluetoothDeviceInfo]
    let bleSnapshots: [BLEDeviceSnapshot]
    let bindings: [String: String]
    let learnedBindings: [String: String]
    let nameAliases: [String: Set<String>]

    static func isAudio(_ device: BluetoothDeviceInfo) -> Bool {
        device.type == .headphones || device.type == .headset
    }

    static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func mac(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == ":" || $0 == "-") }) else { return nil }
        let normalized = value.filter(\.isHexDigit)
        return normalized.count == 12 ? normalized : nil
    }

    init(ioDevices: [BluetoothDeviceInfo], profilerDevices: [BluetoothDeviceInfo],
         pmsetDevices: [BluetoothDeviceInfo], bleSnapshots: [BLEDeviceSnapshot],
         bindings: [String: String], cachedAddresses: [UUID: String], nameAliases: [String: Set<String>],
         pairedDevices: [BluetoothDeviceInfo], advertisements: [AirPodsAdvertisement]) {
        let snapshots = BLEDeviceSnapshot.coalesced(bleSnapshots)
        let roots = (pairedDevices + ioDevices).filter(Self.isAudio)
        let physical = roots + profilerDevices.filter { Self.isAudio($0) && !$0.isBLETransportOnly }
        var devicesByMAC: [String: BluetoothDeviceInfo] = [:]
        var claims: [String: Set<String>] = [:]
        for device in physical {
            guard let address = Self.mac(device.address) else { continue }
            if devicesByMAC[address] == nil { devicesByMAC[address] = device }
            let names = (nameAliases[address] ?? []).union([device.name])
                .union(profilerDevices.filter { Self.mac($0.address) == address }.map(\.name))
            for name in names {
                let key = Self.normalizedName(name)
                if !key.isEmpty { claims[key, default: []].insert(address) }
            }
        }

        // 缓存 UUID 只在当前物理主身份唯一时提供线索；冲突缓存不能吞掉另一副耳机。
        var uuidClaims: [UUID: Set<String>] = [:]
        for address in devicesByMAC.keys {
            if let uuid = bindings[address].flatMap(UUID.init(uuidString:)) {
                uuidClaims[uuid, default: []].insert(address)
            }
        }
        for device in pmsetDevices {
            if let address = Self.mac(device.address), devicesByMAC[address] != nil,
               let uuid = device.accessoryIdentifier {
                uuidClaims[uuid, default: []].insert(address)
            }
        }

        func uniqueOwner(name: String, uuid: UUID?) -> String? {
            if let address = uuid.flatMap({ cachedAddresses[$0] }) {
                return devicesByMAC[address] == nil ? nil : address
            }
            let named = claims[Self.normalizedName(name)] ?? []
            let known = uuid.flatMap { uuidClaims[$0] } ?? []
            guard known.count <= 1 else { return nil }
            if let owner = known.first {
                return named.isEmpty || named.contains(owner) ? owner : nil
            }
            return named.count == 1 ? named.first : nil
        }

        let liveUUIDs = Set(snapshots.map(\.identifier))
            .union(pmsetDevices.compactMap(\.accessoryIdentifier))
            .union(advertisements.map(\.identifier))
        // 电源树的分组 UUID 不一定等于任一个 GATT UUID。只有本轮系统画像用同 MAC
        // 明确连起型号名与主设备，且组身份无歧义时，才改写其传输地址；不把组 UUID 随意写入召回缓存。
        self.pmsetDevices = pmsetDevices.map { device in
            guard Self.isAudio(device), Self.mac(device.address) == nil,
                  device.reportedIdentifiers.allSatisfy({ cachedAddresses[$0] == nil }),
                  let uuid = device.accessoryIdentifier,
                  let owner = uniqueOwner(name: device.name, uuid: uuid),
                  profilerDevices.contains(where: {
                      Self.isAudio($0) && Self.normalizedName($0.name) == Self.normalizedName(device.name)
                          && ((Self.mac($0.address) == owner && !$0.isBLETransportOnly)
                              || ($0.isBLETransportOnly && nameAliases[owner]?.contains($0.name) == true))
                  }),
                  Set(pmsetDevices.filter {
                      Self.isAudio($0) && Self.normalizedName($0.name) == Self.normalizedName(device.name)
                  }.compactMap(\.accessoryIdentifier)).count == 1
            else { return device }
            uuidClaims[uuid, default: []].insert(owner)
            return Self.withAddress(device, address: owner, name: devicesByMAC[owner]?.name ?? device.name)
        }
        let pmsetDevices = self.pmsetDevices

        var prepared: [(device: BluetoothDeviceInfo, auxiliary: Bool)] = []
        var resolvedAliases = nameAliases
        for device in profilerDevices {
            var next = device
            var auxiliary = false
            if Self.isAudio(device), let address = Self.mac(device.address), let primary = devicesByMAC[address] {
                next = Self.withAddress(device, address: address, name: primary.name)
            } else if Self.isAudio(device), device.isBLETransportOnly {
                let uuid = device.accessoryIdentifier ?? bindings[device.address].flatMap(UUID.init(uuidString:))
                if let owner = uniqueOwner(name: device.name, uuid: uuid) {
                    resolvedAliases[owner, default: []].insert(device.name)
                    next = Self.withAddress(device, address: owner,
                                            name: devicesByMAC[owner]?.name ?? device.name)
                    auxiliary = true
                }
            }
            resolvedAliases[next.address, default: []].insert(device.name)
            prepared.append((next, auxiliary))
        }
        // 同一轮主设备快照先于辅助记录，缺电量的传输行不能覆盖完整的左右耳/盒读数。
        prepared.sort {
            let firstReportsBattery = $0.device.batteryLevel != nil || !$0.device.components.isEmpty
            let secondReportsBattery = $1.device.batteryLevel != nil || !$1.device.components.isEmpty
            if firstReportsBattery != secondReportsBattery { return firstReportsBattery }
            if $0.auxiliary != $1.auxiliary { return !$0.auxiliary }
            if $0.device.components.count != $1.device.components.count {
                return $0.device.components.count > $1.device.components.count
            }
            if ($0.device.batteryLevel != nil) != ($1.device.batteryLevel != nil) {
                return $0.device.batteryLevel != nil
            }
            return $0.device.address == $1.device.address
                ? $0.device.name < $1.device.name : $0.device.address < $1.device.address
        }
        var seenAddresses = Set<String>()
        var canonicalProfiler = prepared.compactMap {
            seenAddresses.insert($0.device.address).inserted ? $0.device : nil
        }
        self.nameAliases = resolvedAliases

        // 系统独有且有电量的耳机仍能作为主身份，覆盖只开仓、尚未建立音频链路的场景。
        for device in canonicalProfiler where Self.isAudio(device) {
            guard let address = Self.mac(device.address), devicesByMAC[address] == nil else { continue }
            devicesByMAC[address] = device
            let key = Self.normalizedName(device.name)
            if !key.isEmpty { claims[key, default: []].insert(address) }
        }

        var candidates: [String: Set<UUID>] = [:]
        for snapshot in snapshots {
            guard let name = snapshot.name,
                  Self.isCompatibleAudio(snapshot),
                  let owner = uniqueOwner(name: name, uuid: snapshot.identifier) else { continue }
            candidates[owner, default: []].insert(snapshot.identifier)
        }
        var updatedBindings = bindings
        var learned: [String: String] = [:]
        // 只有一个当前 UUID 且旧 UUID 已离场时才更新已配对 MAC；多个传输别名不任选其一持久化。
        let pairedMACs = Set(roots.compactMap { Self.mac($0.address) })
        for (owner, identifiers) in candidates where identifiers.count == 1 && pairedMACs.contains(owner) {
            guard let uuid = identifiers.first,
                  uuidClaims[uuid] == nil || uuidClaims[uuid] == [owner],
                  !pmsetDevices.contains(where: {
                      Self.mac($0.address) == owner && $0.accessoryIdentifier != nil && $0.accessoryIdentifier != uuid
                  }) else { continue }
            if let previous = bindings[owner].flatMap(UUID.init(uuidString:)) {
                guard previous != uuid, !liveUUIDs.contains(previous),
                      !pmsetDevices.contains(where: {
                          $0.accessoryIdentifier == uuid && Self.mac($0.address) != owner
                      }),
                      snapshots.first(where: { $0.identifier == uuid })?.batteryLevel == nil
                        || pmsetDevices.contains(where: { $0.accessoryIdentifier == uuid && Self.mac($0.address) == owner })
                else { continue }
            }
            updatedBindings[owner] = uuid.uuidString
            learned[owner] = uuid.uuidString
        }
        self.bindings = updatedBindings
        self.learnedBindings = learned
        self.bleSnapshots = snapshots.filter { snapshot in
            // 有读数的未知 UUID 仍代表独立设备；只有空占位且主身份唯一时才折叠。
            guard snapshot.batteryLevel == nil, let name = snapshot.name,
                  Self.isCompatibleAudio(snapshot),
                  let owner = uniqueOwner(name: name, uuid: snapshot.identifier) else { return true }
            // 只有 BLE 当前连接证据时也保留一个主条目；已配对清单本身不构成在线证据。
            if !ioDevices.contains(where: { Self.mac($0.address) == owner }),
               !canonicalProfiler.contains(where: { Self.mac($0.address) == owner }),
               let device = devicesByMAC[owner] {
                canonicalProfiler.append(BluetoothDeviceInfo(address: owner, name: device.name,
                    type: device.type, batteryLevel: nil))
            }
            // 有明确 UUID → MAC 的快照留给合并层，以保留实时名称和设备元数据。
            return cachedAddresses[snapshot.identifier] != nil
        }
        self.profilerDevices = canonicalProfiler
    }

    private static func isCompatibleAudio(_ snapshot: BLEDeviceSnapshot) -> Bool {
        guard let type = snapshot.appearance.flatMap(BluetoothDeviceType.fromAppearance) else { return true }
        return type == .headphones || type == .headset
    }

    private static func withAddress(_ device: BluetoothDeviceInfo, address: String, name: String) -> BluetoothDeviceInfo {
        var result = BluetoothDeviceInfo(
            address: address, name: name, type: device.type, batteryLevel: device.batteryLevel,
            services: device.services, components: device.components, isCharging: device.isCharging,
            vendorName: device.vendorName, modelName: device.modelName,
            batterySource: device.batterySource, accessoryIdentifier: device.accessoryIdentifier,
            memberIdentifiers: device.memberIdentifiers
        )
        result.previouslyReportedBatteryParts = device.previouslyReportedBatteryParts
        result.isBLETransportOnly = device.isBLETransportOnly
        return result
    }
}
