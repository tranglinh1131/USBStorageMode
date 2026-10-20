# USB Storage Mode

**v1.1.1 · Author: Trang Linh**

Turn your device's **MicroSD card into a USB drive** by connecting it to your computer via the USB-C port on the bottom of the device.

Transfer ROMs, save files, photos, and music **without removing the MicroSD card**.

Compatible with the **TrimUI Brick, Brick Hammer, Brick Pro, Smart Pro, Smart Pro S** running **NX Redux** or **NextUI**.

---

## Installation

1. **Power off** the device, remove the MicroSD card, and insert it into a card reader connected to your computer.
2. Extract the ZIP archive. Copy the `USBStorageMode.pak` folder into the `Tools` directory on the MicroSD card.
3. Reinsert the card and power on the device.
4. Open the menu and select **USBStorageMode**.

---

## How to Use

1. **Connect a USB-C cable** to the Type-C port on the bottom of the device and plug the other end into your computer.
2. Open **USBStorageMode** from the menu.
3. Select **Start USB Storage Mode**.
4. Wait until the device displays *USB Mode active*. Your computer should now recognize the MicroSD card as a drive.
5. Transfer files as you normally would.
6. When finished, follow the instructions in [Ending a USB Session](#ending-a-usb-session).
7. The device will automatically reboot back to the menu.

> **If the app does not display the Start / Cancel screen** (some NextUI builds do not include this interface), simply connect the cable and the app will start automatically. You can also open the app first and connect the cable afterward. No additional input is required.

### Status Messages

| Screen Message | Meaning |
| --- | --- |
| *Preparing the SD card* | Preparing the card for access by your computer |
| *Plug the USB cable…* | No USB cable detected |
| *Waiting for the computer…* | USB storage is enabled; waiting for the computer to recognize the drive |
| **USB Mode active** | **Ready! You can now transfer files.** |
| *Ejecting in Ns* | Countdown before the session ends |
| *The computer did not see the drive* | The computer failed to recognize the drive. See [If the Computer Does Not Recognize the Drive](#if-the-computer-does-not-recognize-the-drive). |

---

## Ending a USB Session

**When you're done transferring files, press the Back button on the device.**

The app will start a **10-second countdown** before ending the session.

Once the countdown finishes, the device will **automatically reboot**. This is intentional: rebooting allows the system to detect the card and initialize it cleanly after the computer has written files to it.

---

## Things to Know

- **Your card is protected against simultaneous access.** Before entering USB mode, the app unmounts the MicroSD card from the device's system. This prevents the device and computer from accessing the card at the same time. Your computer sees the card just as it would in a card reader.
- **No manual recovery should be necessary.** If the app freezes while running, the device will attempt to reboot automatically. If the reboot fails, the app will remount the card and restore the menu. You should not need to hold down the power button.
- **Connect the cable before opening the app.** This is the most reliable way to start USB Storage Mode.
- **Computer does not recognize the drive? Try another cable first.** A power-only cable may look identical to a data cable. The device may detect the cable even though the computer cannot see the drive. This is the most common cause. If the problem persists, try another USB port on your computer.
- **Smaller screens are supported.** The app automatically scales text and icons to fit the screen, keeping the interface readable on devices with smaller displays than the Brick Pro.
- **You can also use a card reader.** Once USB Storage Mode is active, you can remove the MicroSD card and connect it to your computer using a card reader instead. The result is the same.
