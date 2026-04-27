# App Store Review Notes

Copy the section below into App Store Connect → App Review Information → Notes.

---

## TL;DR

MioCam is a peer-to-peer baby-monitor app. The `audio` value in `UIBackgroundModes` exists so that the **Monitor** device can keep playing the live audio received from the **Camera** device while the Monitor is locked or backgrounded. This is the core listening feature of a baby monitor and the Monitor is where audible content is played.

## Important: two devices are required

Background audio playback **cannot be reproduced with a single device**. Please prepare two devices (any combination of iPhone/iPad) and sign in to the same Apple ID on both.

- Device A = Camera (captures video/mic, streams via WebRTC)
- Device B = Monitor (receives and **plays** video and audio)

## How to locate the background audio feature

1. On **Device A (Camera)**
   - Launch MioCam and Sign in with Apple.
   - Tap **Camera** on the role-selection screen.
   - A QR code and a 6-digit pairing code are shown. Leave this screen open.
2. On **Device B (Monitor)**
   - Launch MioCam and Sign in with the **same** Apple ID.
   - Tap **Monitor**.
   - Scan Device A's QR code (or enter the 6-digit pairing code).
   - Live video + audio from Device A starts playing on Device B.
3. **Verify background audio on Device B**
   - While the connection is live, press Device B's side/home button to **lock the screen**, or swipe up to send MioCam to the background.
   - Speak into Device A (or make any sound near it).
   - Device B continues to play the audio through its speaker while backgrounded/locked. This is the feature that requires `UIBackgroundModes=audio`.

## Why the `audio` key is required

Without `UIBackgroundModes=audio`, iOS suspends the Monitor app the moment the parent locks the phone, and the baby's room audio immediately stops — which defeats the entire purpose of a monitor. The key is used to keep the received WebRTC audio track audible in the background on the Monitor device.

## Note on the Camera device

The Camera device (Device A) does **not** play audible content. It only captures microphone input and streams it to the Monitor. Please verify background audio playback on the **Monitor (Device B)**, not on the Camera.

## Test credentials

Sign in with Apple is used for authentication, so no shared test account is required. Any Apple ID works; the same ID must be used on both devices for pairing.

## Contact

If anything is unclear or you cannot reproduce the flow above, please reply to this message in App Store Connect and we will respond promptly.
