import Foundation
import CoreBluetooth

let defaultTarget: UInt16 = 0x2036
let defaultName = "Akshat’s AirPods"

var mine: [UInt16: String] = [defaultTarget: defaultName]

struct Args {
    var scanSeconds: Double? = nil
    var quiet = false
    var findMy = false
    var model: UInt16? = nil
    var showAll = false
    init() {
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--scan-seconds": scanSeconds = it.next().flatMap(Double.init)
            case "--quiet": quiet = true
            case "--findmy": findMy = true
            case "--all": showAll = true
            case "--hunt": showAll = true; findMy = true
            case "--model": model = it.next().flatMap { UInt16($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
            case "-h", "--help":
                print("usage: airpods-finder [--quiet] [--all] [--findmy] [--hunt] [--model 0xPID] [--scan-seconds N]")
                exit(0)
            default: break
            }
        }
    }
}

final class Device {
    let id: UUID
    var label: String
    var kind: String
    var ema: Double
    var lastRSSI: Int
    var lastSeen = Date()
    var history: [(Date, Double)] = []
    var battery: String = ""
    var isMine = false
    init(id: UUID, label: String, kind: String, rssi: Int) {
        self.id = id; self.label = label; self.kind = kind
        self.ema = Double(rssi); self.lastRSSI = rssi
    }
    func update(rssi: Int) {
        lastRSSI = rssi
        ema = 0.3 * Double(rssi) + 0.7 * ema
        lastSeen = Date()
        history.append((lastSeen, ema))
        history.removeAll { lastSeen.timeIntervalSince($0.0) > 6 }
    }
    var trend: String {
        guard let old = history.first(where: { lastSeen.timeIntervalSince($0.0) <= 3 }),
              lastSeen.timeIntervalSince(old.0) > 1.5 else { return "  ...  " }
        let d = ema - old.1
        if d > 3 { return "WARMER ^" }
        if d < -3 { return "COLDER v" }
        return " steady "
    }
    var distance: Double { pow(10, (-59 - ema) / 20) }
    var zone: String {
        switch ema {
        case (-55)...: return "VERY CLOSE (< 1 m)"
        case (-67)...: return "CLOSE (1 to 3 m)"
        case (-80)...: return "NEARBY (same room?)"
        default: return "FAR"
        }
    }
}

func pct(_ n: UInt8) -> String { n <= 10 ? "\(Int(n) * 10)%" : "--" }

func parse(_ data: Data, wantFindMy: Bool) -> (String, String, String)? {
    let b = [UInt8](data)
    guard b.count >= 4, b[0] == 0x4C, b[1] == 0x00 else { return nil }
    if b[2] == 0x07, b.count >= 10 {
        let pid = UInt16(b[6]) << 8 | UInt16(b[5])
        let batt = "buds \(pct(b[8] >> 4))/\(pct(b[8] & 0x0F)) case \(pct(b[9] & 0x0F))"
        if let n = mine[pid] { return ("\(n) (TARGET, 0x\(String(format: "%04X", pid)))", "mine", batt) }
        return (String(format: "Other AirPods 0x%04X (not the target)", pid), "airpods", batt)
    }
    if wantFindMy, b[2] == 0x12 {
        return ("Find My beacon (unknown owner)", "findmy", "")
    }
    return nil
}

final class Finder: NSObject, CBCentralManagerDelegate {
    let args: Args
    var central: CBCentralManager!
    var devices: [UUID: Device] = [:]
    var status = "Starting Bluetooth..."
    var nextBeep = Date()

    init(args: Args) {
        self.args = args
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            status = "Scanning"
            c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .unauthorized:
            status = "No Bluetooth permission. Allow your terminal app in System Settings > Privacy & Security > Bluetooth."
        case .poweredOff:
            status = "Bluetooth is off. Turn it on."
        default:
            status = "Bluetooth state: \(c.state.rawValue)"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let r = rssi.intValue
        guard r < 0, r > -110 else { return }
        var info: (String, String, String)? = nil
        if let md = ad[CBAdvertisementDataManufacturerDataKey] as? Data {
            info = parse(md, wantFindMy: args.findMy)
        }
        let advName = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
        if info == nil, let n = advName, n.localizedCaseInsensitiveContains("airpods") {
            info = (n, mine.isEmpty ? "mine" : "airpods", "")
        }
        guard let (name, kind, batt) = info else { return }
        if kind == "airpods", !args.showAll, !mine.isEmpty { return }
        let label = name
        if let d = devices[p.identifier] {
            d.update(rssi: r); d.label = label
            if !batt.isEmpty { d.battery = batt }
        } else {
            let d = Device(id: p.identifier, label: label, kind: kind, rssi: r)
            d.battery = batt
            devices[p.identifier] = d
        }
    }

    func live() -> [Device] {
        devices.values
            .filter { Date().timeIntervalSince($0.lastSeen) < 15 }
            .sorted { ($0.kind == "mine" ? 1 : 0, $0.ema) > ($1.kind == "mine" ? 1 : 0, $1.ema) }
    }

    func bar(_ ema: Double) -> String {
        let n = max(0, min(30, Int((ema + 100) / 60 * 30)))
        return String(repeating: "#", count: n) + String(repeating: ".", count: 30 - n)
    }

    func render() {
        var out = "\u{1B}[2J\u{1B}[H"
        out += "AirPods Finder   \(status)   (Ctrl+C to quit)\n"
        out += "Looking for: \(mine.map { "\($0.value) 0x\(String(format: "%04X", $0.key))" }.joined(separator: ", "))\n"
        out += "Open the AirPods case lid or take a bud out. Walk slowly and watch the meter.\n\n"
        let list = live()
        if list.first?.kind != "mine" {
            out += "  No signal from the target AirPods yet. Keep looking, they advertise only when out of the case or with the lid open.\n"
        }
        if let t = list.first, t.kind == "mine" {
            out += "  TARGET: \(t.label)\n"
            out += "  [\(bar(t.ema))]  \(Int(t.ema)) dBm   \(t.trend)\n"
            out += "  \(t.zone)   approx \(String(format: "%.1f", t.distance)) m   \(t.battery)\n\n"
        }
        for (i, d) in list.enumerated() {
            let age = Int(Date().timeIntervalSince(d.lastSeen))
            out += String(format: "  %2d. %@  %4d dBm  [%@]  %@  seen %ds ago\n", i + 1, d.label, Int(d.ema), bar(d.ema), d.trend, age)
        }
        print(out, terminator: "")
        fflush(stdout)
    }

    func beepTick() {
        guard !args.quiet, let t = live().first, t.kind == "mine",
              Date().timeIntervalSince(t.lastSeen) < 4 else { return }
        if Date() >= nextBeep {
            print("\u{7}", terminator: ""); fflush(stdout)
            let f = max(0, min(1, (t.ema + 95) / 55))
            nextBeep = Date().addingTimeInterval(2.0 - 1.85 * f)
        }
    }

    func dump() {
        print("status: \(status)")
        print("looking for: \(mine.map { "\($0.value) 0x\(String(format: "%04X", $0.key))" }.joined(separator: ", "))")
        let list = live()
        if !list.contains(where: { $0.kind == "mine" }) { print("target AirPods: no signal") }
        for d in list {
            print("\(d.label) | \(Int(d.ema)) dBm | \(d.zone) | ~\(String(format: "%.1f", d.distance)) m | \(d.battery)")
        }
    }
}

setvbuf(stdout, nil, _IOFBF, 1 << 16)
let args = Args()
if let m = args.model { mine = [m: "AirPods 0x\(String(format: "%04X", m))"] }
let finder = Finder(args: args)

if let s = args.scanSeconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + s) { finder.dump(); exit(0) }
} else {
    print("\u{1B}[?25l", terminator: "")
    signal(SIGINT) { _ in print("\u{1B}[?25h"); exit(0) }
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in finder.render() }
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in finder.beepTick() }
}
RunLoop.main.run()
