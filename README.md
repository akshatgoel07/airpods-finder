# AirPods Finder

AirPods Finder is a macOS terminal app. It scans Bluetooth Low Energy signals and shows the signal strength of one AirPods model. Use it to find lost AirPods.

The default target is Product ID `0x2036` ("Akshat’s AirPods").

## Limits

- AirPods send their signal only when the case lid is open or a bud is out of the case. The app cannot detect AirPods in a closed case.
- The app identifies AirPods by model only. Other AirPods of the same model show the same Product ID. Use the battery levels to tell two pairs apart.
- The distance value is an estimate. Walls, furniture, and people make the signal weaker.

## Install

Option 1: Download the binary.

1. Download `airpods-finder` from the latest release.
2. Open Terminal in the download folder.
3. Run these commands:

```sh
xattr -d com.apple.quarantine airpods-finder
chmod +x airpods-finder
```

Option 2: Build from source. You must have the Xcode Command Line Tools.

```sh
git clone https://github.com/akshatgoel07/airpods-finder.git
cd airpods-finder
./build.sh
```

## Use

```sh
./airpods-finder
```

1. When macOS asks for Bluetooth access for Terminal, click Allow.
2. If you do not see the request, go to System Settings > Privacy & Security > Bluetooth and turn on Terminal.
3. Carry a MacBook and walk slowly. Stop for 3 seconds at each spot.
4. Go in the direction that shows WARMER. The beep gets faster when you get closer.
5. At "VERY CLOSE (< 1 m)", search the area by hand.

## Options

| Option | Function |
|---|---|
| `--model 0xPID` | Sets a different Product ID as the target. |
| `--all` | Also shows other AirPods. |
| `--hunt` | Shows other AirPods and all Find My beacons. |
| `--findmy` | Shows Find My beacons. The app cannot identify the owner of a beacon. |
| `--quiet` | Stops the beep. |
| `--scan-seconds N` | Scans for N seconds, prints a list, and stops. |

To find the Product ID of your AirPods, pair them with a Mac and run `system_profiler SPBluetoothDataType`.

## How it works

AirPods send an Apple "proximity pairing" advertisement (type `0x07`). Bytes 5 and 6 of that advertisement contain the Product ID. The app reads the RSSI of each advertisement and smooths it. Then it shows the trend over the last 3 seconds.
