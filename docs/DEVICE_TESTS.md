# Device test checklist

Unit tests cover the recommendation direction, low confidence, robustness to unusual video samples, intensity at 0 / 50 / 100%, alpha, portrait sizes and the Original bitrate. Compiling and passing unit tests is not the same as verifying encoding and decoding on a real device.

## Required media

- 1080p30 H.264, 4K60 HEVC, portrait 1080×1920, 29.97 fps, variable frame rate, with and without an audio track.
- Blue water, green water, natural colors in shallow water, dark areas, overexposed reflections, clips with several scenes.
- JPEG with EXIF rotation, transparent PNG, large 48 MP photos.
- HDR10 / PQ and HLG: on a device with Android 13+ and an HDR-capable encoder, BT.2020, 10-bit and the source transfer curve must be kept; unsupported devices must say so clearly, never silently fall back to SDR. Dolby Vision and tagged HDR10+ must show that dynamic metadata is not supported yet.

## Workflow checks

1. Import: six-point sampling produces a recommendation, with a confidence hint for dark footage; after analysis the clip plays and can be adjusted at once, without waiting for a transcode; importing again does not show the previous result.
2. Playback: drag the intensity and advanced sliders and check that playback does not restart; while paused, color and compare changes also update the still frame.
3. Compare: switching between original and corrected keeps the timeline continuous; intensity 0 is the original.
4. Export: compare Original against the source for size, audio sync, rotation, timestamps, bitrate and codec. An encoder that cannot handle the source must not quietly lower the quality.
5. Custom: test landscape and portrait at 960 / 1920, 24 / 30 fps, low and high quality, JPEG / PNG, size and image orientation.
6. Lifecycle: rotate the screen, go to the background and back, turn the screen off during an export, cancel from the service notification. After cancelling, no partial file is left in the gallery.
7. Errors: storage full, source permission revoked, corrupt file, unsupported codec; the app does not crash and shows a message.
8. Chinese / English and light / dark / system theme; preferences survive a restart; small screens and large fonts can scroll.

## Performance

On at least one mid-range and one flagship phone, test the preview playing the original video directly (1080p, 4K30) and the switch to the background proxy for 4K60. Record dropped frames, UI frame time, temperature and memory over 60 continuous seconds; check that the position does not jump and no error appears when switching after the proxy is ready. Verify that 4K export does not use the proxy and that the graded result is close to the preview. When the device cannot encode the source codec, Original must fail clearly, and Custom H.264 can be tried instead.

## Interaction and speed acceptance

- Expand the advanced adjustments, scroll to shadows and keep dragging: the preview stays visible and updates. Also test small screens, landscape and large fonts.
- Holding compare shows the original; releasing, dragging out or a system touch cancel restores it.
- Compare images and videos at 0%, 85%, 100% and 200%, and check that the advanced base values are not overwritten.
- 0.5× / 2× / 4× preview, Original and Custom fps export; check lip sync, pitch and duration on long clips, media without audio, and encoder limits at high fps.
