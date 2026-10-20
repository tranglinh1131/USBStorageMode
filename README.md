# USB Storage Mode

**v1.1.1 · Author: Trang Linh**

Turn your device's **MicroSD card into a USB drive** by connecting it to your computer through the USB-C port on the bottom of the device.

Transfer ROMs, save files, photos, and music **without removing the MicroSD card**.

Compatible with the **TrimUI Brick Pro** running **NX Redux** or **NextUI**.

---

## Installation

1. **Power off** the device, remove the MicroSD card, and insert it into a card reader connected to your computer.
2. Extract the ZIP archive to obtain the `USBStorageMode.pak` folder, then copy that folder into the `Tools` directory on the MicroSD card.
3. Reinsert the card and power on the device.
4. Open the menu and select **USBStorageMode**.

---

## How to Use

1. **Connect a USB-C cable** to the Type-C port on the bottom of the device and plug it into your computer.
2. Open **USBStorageMode** from the menu.
3. Select **Start USB Storage Mode**.
4. Wait until the device displays *USB Mode active*. Your computer should now recognize the card as a drive.
5. Transfer files to and from the card as usual.
6. When finished, **press B and wait 10 seconds**. The device will reboot.
7. The device will automatically return to the menu after rebooting.

> **If the app does not display the *Start / Cancel* screen** (some NextUI builds do not include this interface), simply connect the cable and the app will start automatically. You can open the app first and then connect the cable. No additional input is required.

### Status Messages

| Screen Message | Meaning |
| --- | --- |
| *Preparing the SD card* | Preparing the card for access by your computer |
| *Plug the USB cable…* | No USB cable detected |
| *Waiting for the computer…* | USB storage is enabled and waiting for the computer to recognize the drive |
| **USB Mode active** | **Ready! You can now transfer files.** |
| *Ejecting in Ns* | Countdown before the session ends |
| *The computer did not see the drive* | The computer failed to recognize the drive. Disconnect and reconnect the USB cable. |

---

## Things to Know

- **Your card is protected against simultaneous access.** Before entering USB mode, the app unmounts the MicroSD card from the device's system, preventing the device and computer from accessing the card at the same time. Your computer sees the card just as it would when using a card reader.
- **No manual recovery should be necessary if the app gets stuck.** If the app freezes while running, the device will attempt to reboot automatically. If the reboot fails, the app will remount the card and restore the menu. You should never need to hold down the power button.
- **Connect the cable before opening the app.** This is the most reliable way to start USB Storage Mode.
- **Computer does not recognize the drive? Try another cable first.** A power-only cable may look identical to a data cable. The device may detect the cable even though the computer cannot see the drive. This is a common cause. If the problem persists, try another USB port on your computer.
- **Smaller screens are supported.** The app automatically scales text and icons to fit the display, keeping the interface readable on devices with smaller screens than the Brick Pro.
- **You can also use a card reader.** Once USB Storage Mode is active, you can remove the MicroSD card and connect it to your computer using a card reader instead. It works the same way.
