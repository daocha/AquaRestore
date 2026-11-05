# AquaRestore privacy policy

Last updated: 5 November 2026

This policy covers AquaRestore for Android and iOS, including the Google Play, App Store and GitHub Android releases.

AquaRestore restores the colors of underwater videos and photos. Your media is processed on your device and is not sent to the developer. The app has no account, analytics, advertising or tracking, and does not sell personal data. The referral program described below uses a device identifier.

## Your photos, videos and music

AquaRestore reads the photos, videos and music you select to show, analyze and edit them. Processing and temporary working files stay on your device. Exports are saved only when you choose to save or share them.

- **Android:** media-library browsing requests the permissions needed for your Android version. Where supported, you can grant access to selected photos and videos rather than your whole library. Files selected through a system picker are accessed through that picker.
- **iOS:** you select photos and videos through Apple's system photo picker. AquaRestore accesses the items you select rather than requesting permission to browse your whole Photos library. Music is selected through the system file picker. Saving restored media to Photos requests add-only Photos permission.

You can manage permissions in your device's settings. If you select media from a cloud-backed library or file provider, the operating system or provider may download it. If you save or share an export to a cloud-backed location or another app, that service handles it under its own privacy policy. AquaRestore does not operate a media-upload service.

## Network and updates

- **Google Play Android version:** Google Play handles updates. The app contacts only the referral service below.
- **App Store iOS version:** Apple handles App Store and TestFlight distribution and updates. The app contacts only the referral service below.
- **GitHub Android version:** connects to GitHub to check for updates and download an update when you choose. These requests contain none of your media or app settings. GitHub receives ordinary connection information, including your IP address, and handles it under its own privacy policy. The app also contacts the referral service below.

Apple, Google and any file or sharing providers you choose operate independently of AquaRestore. Their services are governed by their respective privacy policies and your account settings.

## Referral program

The referral program lets you invite friends and unlock batch processing. In versions with the program enabled, the app contacts the developer's referral service automatically on first launch, whether or not you use referrals. If that request fails, the app tries again on later launches until it succeeds.

- **What is sent on first launch:** the app's package or bundle ID and a device identifier. The identifier is a SHA-256 hash made from the app's ID and your device's Android ID or iOS identifier for vendor. The raw device ID is not sent. Your referral code is derived from this hash.
- **What else is sent when you use the program:** any referral or unlock code you submit, and a security proof from your device. The proof comes from Android Key Attestation or Apple App Attest, and on iOS, Apple's service is involved in producing it.
- **What the service stores:** the device identifier and when it was registered, your referral code, which code you entered, how many devices entered yours, your unlocks, unlock code redemptions, and security records such as device key bindings and short-lived challenges.
- **What it is used for:** making your code valid for friends, crediting referrals, restoring your referral code and unlocks after you clear app data or reinstall, and preventing abuse. It is not used for advertising or to track you across apps.
- **Connection information:** the service limits requests by IP address, keeping those counts briefly in memory. The server or hosting provider may also keep ordinary connection logs.
- **How long it is kept:** these records have no automatic expiry, because they keep each referral permanent and enforce limits. Clearing app data or uninstalling does not delete them, and your device identifier normally stays the same afterwards.
- **Removing your records:** open an issue at the address below and include your referral code, shown in Settings. Removal can take away restored unlocks and referral credit.

The identifier is pseudonymous, not anonymous: it is persistent and tied to your device. Anyone who knows your full device identifier could read your referral progress from the service, but it does not contain your name or contact details.

When you tap **Invite**, the invite text is copied to your clipboard and the system share sheet opens. The app you choose handles the text under its own privacy policy. The invite contains your referral code, and each person who enters it adds to your count.

## Settings and saved files

Language, theme, editing preferences and your saved referral state are stored on your device. The developer has no access to the copy on your device; the referral service keeps its own records as described above. You control the original media and exported copies; removing the app does not remove files saved to Photos, shared storage, other apps or cloud providers. Delete those copies from their respective locations if you no longer want them.

## Developer tools

Developer tools are hidden and off until you unlock them by tapping the version number in Settings ten times. They are meant for reporting problems. While they are off, the app writes no log and saves no analysis pictures.

While they are on, the app keeps a log on your device, which can include the names of your files. Saved logs and analysis pictures are copies of your data: the pictures show your photos and videos at full quality. Nothing is sent to the developer unless you choose to share it.

- **Android:** logs and analysis frames are saved when you tap the button for them, to `Download/AquaRestore-analysis` in shared storage. Other apps with access to that storage, and anyone using a file manager on the device, may be able to read them. They remain after you turn developer tools off or remove the app, until you delete them.
- **iOS:** logs and analysis frames are saved to the app's Documents folder, shown in the Files app as On My iPhone › AquaRestore. While developer tools are on, the app can also save pictures of video frames there on its own during playback. They remain after you turn developer tools off, until you delete them or remove the app.

## Children

AquaRestore is not directed at children and does not knowingly collect children's personal information. It provides no advertising or tracking. The app does not ask for anyone's age, so the device identifier described above is handled the same way for every install.

## Changes and contact

Changes to this policy are published in this file with an updated date. For questions, open an issue at https://github.com/daocha/AquaRestore/issues. GitHub issues are public: do not include private media or other sensitive information. Information you voluntarily include in a support request is visible to its recipients and is handled by the support platform under its own privacy policy.
