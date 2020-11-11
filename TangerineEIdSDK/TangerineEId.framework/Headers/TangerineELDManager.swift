//
//  TangerineELDManager.swift
//  TangerineKey
//
//  Created by Reenu Deswal on 06/03/20.
//  Copyright © 2020 Reenu Deswal . All rights reserved.
//

import Foundation
import CoreBluetooth
import UIKit



public enum APIError:Error  {
case noNetworkConnection(message: String)
case dataFormatError(message: String)
case noData(message: String)
case serverError(message: String)
case slotExpired(message : String)
case unknownError(message : String)
    
}

public protocol TangerineELDManagerDelegate  : class{
    
    func gotConnected()
    func receivedResponse(_ data : String?)
    func didDisconnect(_ error : Error?)
    func errorOccured(_ errorState : ELDState)
    func deviceFound(_ deviceName : String?)
}


public enum ELDState {
    
    case getStarted
    case connecting
    case bluetoothPoweredOff
    case bluetoothUnauthorised
    case failedToConnect
    case connected
    case disconnected
    case unKnown
    case deviceNotSaved
}


public enum CarState: String {
    case notDetermined = "notDetermined"
    case locked        =  "#l"
    case unLocked      = "#u"
    
    var command: NSString {
        let timeString = (Date().timeIntervalSince1970*1000).cleanStringValue
        let message = BLEMessageContent.payload + BLEMessageContent.separator + timeString as NSString
        return message
    }
    var rawCommand: String {
        switch self {
        case .locked:
            return "00"
        case .unLocked:
            return "01"
        default:
            return ""
        }
    }
}

public class TangerineELDManager : NSObject {
    
    var centralManager : CBCentralManager!
    var characteristics = [String : CBCharacteristic]()
    var readWriteCharacteristic : CBCharacteristic?
    var blePeripheral : CBPeripheral?
    var lastStatus : CarState?
   public static let sharedInstance = TangerineELDManager()
    
    public weak var delegate : TangerineELDManagerDelegate?
    
    var timer: Timer!
    var countTime: Int = 0
    
    
    private  override init(){
        centralManager = CBCentralManager.init()
        lastStatus = .notDetermined
    }
    
    
    @objc func updateScanningStatus(){
        if !isConnected() && centralManager.state == .poweredOn  {
                   if self.countTime >= 30{
                       centralManager.stopScan()
                       resetTimer()
                       self.countTime = 0
                        delegate?.errorOccured(.failedToConnect)
                   } else {
                     countTime += 1
            }
                  
        } else {
            resetTimer()
        }
       
    }
    
    public  func connectToDevice(){
        if isDeviceSaved() {
            if centralManager.state == .poweredOn {
                self.timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.updateScanningStatus), userInfo: nil, repeats: true)
                       refreshBLEState()
            } else if centralManager.state == .poweredOff {
                 delegate?.errorOccured(.bluetoothPoweredOff)
            } else {
                // register for connection call back
                centralManager.delegate = self
            }
            
        } else {
            delegate?.errorOccured(.deviceNotSaved)
        }
    }
    
    
    public  func scanForDevices(){
        print("scan called")
            if centralManager.state == .poweredOn {
                self.timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.updateScanningStatus), userInfo: nil, repeats: true)
                refreshBLEState()
            } else if centralManager.state == .poweredOff {
                 delegate?.errorOccured(.bluetoothPoweredOff)
            } else {
                           // register for connection call back
                centralManager.delegate = self
            }
    }
    
    public func disconnect(){
        if let peripheral = blePeripheral, centralManager.state == .poweredOn {
            TangerineELDManager.sharedInstance.centralManager?.cancelPeripheralConnection(peripheral)
        } else if centralManager.state == .poweredOff {
            delegate?.errorOccured(.bluetoothPoweredOff)
        } else {
            delegate?.errorOccured(.unKnown)
        }
    }

    private var state:ELDState = .getStarted {
        didSet {
            didChangeViewState()
        }
    }
    
    func didChangeViewState()  {
      //  delegate?.gotConnected(state : self.state)
    }
    
    func refreshBLEState()  {
        switch TangerineELDManager.sharedInstance.centralManager.state {
        case .unknown:
            break
        case .resetting:
            break
        case .unsupported:
            delegate?.errorOccured(.bluetoothUnauthorised)
        case .unauthorized:
            resetTimer()
            delegate?.errorOccured(.bluetoothUnauthorised)
            self.state = .bluetoothUnauthorised
        case .poweredOff:
            resetTimer()
            delegate?.errorOccured(.bluetoothPoweredOff)
            self.state = .bluetoothPoweredOff
        case .poweredOn:
            self.state = .connecting
            if !isConnected() {
                centralManager.delegate = self
                TangerineELDManager.sharedInstance.centralManager.scanForPeripherals(withServices: [BLEService_UUID])
            }
        @unknown default:
            break
        }
    }
    
    
   public func getVinAndVersionCommand() {
       if isConnected(){
        if let peripheral = blePeripheral {
        if let charecterstic = characteristics[kBLE_Characteristic_uuid_Read_Write.lowercased()] {
             self.timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.updateScanningStatus), userInfo: nil, repeats: true)

                if let data = try? TangerineELDManager.encryptedCommands(text: CarState.unLocked.command as String) {
                    peripheral.writeValue(data, for: charecterstic, type: CBCharacteristicWriteType.withResponse)
                }
        }
        }
        }
       
    }
        
    
    public func isConnected() -> Bool {
        if self.state == .connected {
            return true
        }
        return false
    }
    
    public func isDeviceSaved() -> Bool {
            return TangerineEldDataManager.shared.deviceName  != nil && TangerineEldDataManager.shared.deviceName != ""
    }
    
    
    public func saveDevice(_ name : String) {
        TangerineEldDataManager.shared.deviceName = name
    }
    
    public func clearDevice() {
        TangerineEldDataManager.shared.clearAllData()
    }
	
	
    class func encryptedCommands(text : String) throws -> Data {
        var message = NSString()
        message = text as NSString
        guard let dataStr = DESEncryptor.doCipher(encryptValue: message), let data = (dataStr + BLEMessageContent.eom).data(using: .utf8) else {
            throw APIError.dataFormatError(message: "No data")
        }
        return data
    }
    
    func resetTimer(){
        if timer != nil {
                   timer.invalidate()
                   timer = nil
               }
    }
    
    
    func parseResponse(_ response : String) -> [String]? {
        var result = [String]()
        result = response.components(separatedBy: BLEMessageContent.responseSeparator)
        return result
        
    }
    
    
    // -------------------------
    // MARK: - BLE Response processing
    // -------------------------
    func didReceiveResponseFromBLE(response: String) {
            resetTimer()
        if response == CarState.unLocked.rawValue || response == CarState.locked.rawValue {
          getVinAndVersionCommand()
        } else {
            // shuold be trip data   or vin and version data.....
            if response.contains(BLEMessageContent.eom) {
                let mySubstring = response.dropLast(2) // to remove #e from the end.
                let result = parseResponse(String(mySubstring))
                if result?.first == BLEResponseTypes.tripData.rawValue {
                    let eldData = ELDData()
                    let outputString = eldData.createDataSource(result)
                    delegate?.receivedResponse(outputString)
                } else { // vin data
                    if let vin = result?[1] {
                        TangerineEldDataManager.shared.vin = vin
                    }
                    if let appVersion = result?[2] {
                        TangerineEldDataManager.shared.appVersion = appVersion
                    }
                    
                }
            }
        }
        
    }
}
    
extension TangerineELDManager : CBCentralManagerDelegate {
        
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshBLEState()
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if isDeviceSaved() {
            if peripheral.name?.lowercased() == TangerineEldDataManager.shared.deviceName?.lowercased() {
                       TangerineELDManager.sharedInstance.blePeripheral = peripheral
                       TangerineELDManager.sharedInstance.blePeripheral?.delegate = self
                       central.stopScan()
                        resetTimer()
                       central.connect(peripheral)
                   }
            
        } else {
             delegate?.deviceFound(peripheral.name)
        }
       
       
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        resetTimer()
        peripheral.discoverServices([BLEService_UUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.state = .disconnected
        if let error = error {
            delegate?.didDisconnect(error)
        } else{
            
            delegate?.didDisconnect(nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.state = .failedToConnect
        delegate?.errorOccured(.failedToConnect)
    }
    
}


extension TangerineELDManager : CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.properties.contains(.write) {
                TangerineELDManager.sharedInstance.characteristics[characteristic.uuid.uuidString.lowercased()] = characteristic
                self.state = .connected
                delegate?.gotConnected()
            }
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
       /* if let error = error {
            AlertHandler.showAlert(withTitle: "Error", message: error.localizedDescription, cancelButtonTitle: "OK")
            self.state = .writingFailed
        } */
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value, let response = String(data: data, encoding: .utf8)?.lowercased(), !response.isEmpty {
                didReceiveResponseFromBLE(response: response)
            }
    }
}
