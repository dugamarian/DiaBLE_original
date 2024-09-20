import Foundation
import CoreBluetooth


// https://github.com/bubbledevteam/bubble-client-swift/


@Observable class Bubble: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.bubble) }
    override class var name: String { "Bubble" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case data      = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataWrite = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataRead  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

        var description: String {
            switch self {
            case .data:      "data"
            case .dataWrite: "data write"
            case .dataRead:  "data read"
            }
        }
    }

    override class var knownUUIDs: [String] { UUID.allCases.map(\.rawValue) }

    override class var dataServiceUUID: String             { UUID.data.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.dataWrite.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.dataRead.rawValue }

    enum ResponseType: UInt8, CustomStringConvertible {
        case dataInfo            = 0x80
        case dataPacket          = 0x82
        case decryptedDataPacket = 0x88
        case securityChallenge   = 0x8A
        case noSensor            = 0xBF
        case serialNumber        = 0xC0
        case patchInfo           = 0xC1

        var description: String {
            switch self {
            case .dataInfo:            "data info"
            case .dataPacket:          "data packet"
            case .decryptedDataPacket: "decrypted data packet"
            case .securityChallenge:   "security challenge"
            case .noSensor:            "no sensor"
            case .serialNumber:        "serial number"
            case .patchInfo:           "patch info"
            }
        }
    }


    override func readCommand(interval: Int = 5) -> Data {
        return Data([0x00, 0x00, UInt8(interval)])
    }


    override func parseManufacturerData(_ data: Data) {
        let transmitterData = Data(data[8...11])
        firmware = "\(Int(transmitterData[0])).\(Int(transmitterData[1]))"
        hardware = "\(Int(transmitterData[2])).\(Int(transmitterData[3]))"
        macAddress = Data(data[2...7].reversed())
        var msg = "\(Self.name): advertised manufacturer data: firmware: \(firmware), hardware: \(hardware), MAC address: \(macAddress.hexAddress)"
        if data.count > 12 {
            battery = Int(data[12])
            msg += ", battery: \(battery)"
        }
        log(msg)
    }


    override func read(_ data: Data, for uuid: String) {

        // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Bubble.java

        let response = ResponseType(rawValue: data[0])
        log("\(name) response: \(response?.description ?? "unknown") (0x\(data[0...0].hex))")

        if response == .noSensor {
            main.status("\(name): no sensor")

        } else if response == .dataInfo {
            battery = Int(data[4])
            firmware = "\(data[2]).\(data[3])"
            hardware = "\(data[data.count - 2]).\(data[data.count - 1])"
            log("\(name): battery: \(battery), firmware: \(firmware), hardware: \(hardware)")
            let libreType = settings.currentPatchInfo.count > 0 ? SensorType(patchInfo: settings.currentPatchInfo) : .unknown
            if Double(firmware)! >= 2.6 && (libreType == .libre2 || libreType == .libreUS14day) {
                write(Data([0x08, 0x01, 0x00, 0x00, 0x00, 0x2B]))
            } else {
                write(Data([0x02, 0x01, 0x00, 0x00, 0x00, 0x2B]))
            }

        } else {
            // TODO: instantiate specifically a Libre2() (when detecting A4 in the uid, i. e.)
            if sensor == nil {
                sensor = Libre(transmitter: self)
                app.sensor = sensor
            }
            if response == .serialNumber {
                sensorUid = Data(data[2...9])
                sensor!.uid = sensorUid
                settings.currentSensorUid = sensorUid
                log("\(name): patch uid: \(sensor!.uid.hex)")

            } else if response == .patchInfo {
                (sensor! as! Libre).patchInfo = Data(Double(firmware)! < 1.35 ? data[3...8] : data[5...10])
                settings.currentPatchInfo = (sensor! as! Libre).patchInfo
                settings.activeSensorSerial = sensor!.serial
                log("\(name): patch info: \((sensor! as! Libre).patchInfo.hex), sensor type: \(sensor!.type.rawValue), serial number: \(sensor!.serial)")

            } else if response == .securityChallenge {
                if buffer.count == 0 {
                    buffer.append(data.suffix(from: 5))
                } else if buffer.count == 15 {
                    buffer.append(data.suffix(from: 4))
                }
                log("\(name): partial buffer size: \(buffer.count)")
                if buffer.count == 28 {
                    log("\(name): gen2 security challenge: \(buffer.prefix(25).hex)")
                    buffer = Data()
                }

            } else if response == .dataPacket || response == .decryptedDataPacket {
                if buffer.count == 0 {
                    app.lastReadingDate = app.lastConnectionDate
                    sensor!.lastReadingDate = app.lastConnectionDate
                }
                buffer.append(data.suffix(from: 4))
                log("\(name): partial buffer size: \(buffer.count)")
                if buffer.count >= 344 {
                    let fram = buffer[..<344]
                    // let footer = buffer.suffix(8)    // when firmware < 2.0
                    (sensor! as! Libre).fram = Data(fram)
                    main.status("\(sensor!.type)  +  \(name)")
                }
            }
        }
    }
}
