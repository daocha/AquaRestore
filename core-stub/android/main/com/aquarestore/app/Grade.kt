package com.aquarestore.app

import kotlin.math.*

// Public stand-in for the private grading core: same API, deliberately basic formula.
// See core-stub/README.md.

/** Immutable snapshots are shared with the GL thread; an export gets its own frozen snapshot. */
data class Grade(
    val red: Float = 0.3f,
    val temperature: Float = 0.1f,
    val tint: Float = 0.05f,
    val exposure: Float = 0f,
    val haze: Float = 0.1f,
    val contrast: Float = 0.05f,
    val saturation: Float = 0.1f,
    val shadows: Float = 0.05f,
    val strength: Float = 1f,
    val levels: Float = 0f,
    val blackR: Float = 0f, val blackG: Float = 0f, val blackB: Float = 0f,
    val whiteR: Float = 1f, val whiteG: Float = 1f, val whiteB: Float = 1f,
    val coolProtection: Float = 0f,
    val clarity: Float = 0f,
) {
    /** Intensity (0–200%) scales every correction parameter; only 0% is a pixel-exact bypass. */
    fun effective(): Grade {
        val k = strength.coerceIn(0f, 2f)
        return copy(red = red * k, temperature = temperature * k,
            tint = tint * k, exposure = exposure * k, haze = haze * k,
            contrast = contrast * k, saturation = (saturation * k).coerceAtLeast(-1f),
            shadows = shadows * k, levels = (levels * k).coerceIn(0f, 1f),
            coolProtection = (coolProtection * k).coerceIn(0f, 1f), clarity = clarity * k,
            strength = if (k == 0f) 0f else 1f)
    }

    companion object {
        val Neutral = Grade(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)
        val Reef = Grade()
        val Blue = Grade(red = 0.5f, temperature = 0.25f, haze = 0.15f)
        val Green = Grade(red = 0.4f, tint = 0.3f, haze = 0.15f)
    }
}

object ColorGrade {
    fun pixel(argb: Int, grade: Grade): Int = pixel(argb, grade.effective(), 2f.pow(grade.effective().exposure))

    /** [detail] is [Clarity.detail] of the source pixel; zero when clarity is off. Matches [GradeShader]. */
    internal fun pixel(argb: Int, p: Grade, gain: Float, detail: Float = 0f): Int {
        if (p.strength == 0f) return argb
        val r0 = (argb ushr 16 and 255) / 255f
        val g0 = (argb ushr 8 and 255) / 255f
        val b0 = (argb and 255) / 255f
        fun level(x: Float, black: Float, white: Float) = x + (((x - black) / (white - black)).coerceIn(0f, 1f) - x) * p.levels
        var r = level(r0, p.blackR, p.whiteR) * (1f + 0.5f * p.red) * (1f + 0.2f * p.temperature) * gain
        var g = level(g0, p.blackG, p.whiteG) * (1f - 0.2f * p.tint) * gain
        var b = level(b0, p.blackB, p.whiteB) * (1f - 0.2f * p.temperature) * gain
        val contrast = 1f + p.contrast + 0.5f * p.haze
        r = (r - 0.5f) * contrast + 0.5f; g = (g - 0.5f) * contrast + 0.5f; b = (b - 0.5f) * contrast + 0.5f
        val luma = 0.2126f * r + 0.7152f * g + 0.0722f * b
        val lift = p.shadows * 0.2f * (1f - luma.coerceIn(0f, 1f)).pow(2)
        r = luma + (r - luma) * (1f + p.saturation) + lift
        g = luma + (g - luma) * (1f + p.saturation) + lift
        b = luma + (b - luma) * (1f + p.saturation) + lift
        r += (min(r, g) - r) * p.coolProtection * 0.5f
        val sharpen = p.clarity * 2f * detail
        r += sharpen; g += sharpen; b += sharpen
        fun out(x: Float, original: Float) = ((original + (x.coerceIn(0f, 1f) - original) * p.strength) * 255f).roundToInt().coerceIn(0, 255)
        return (argb and -0x1000000) or (out(r, r0) shl 16) or (out(g, g0) shl 8) or out(b, b0)
    }
}

/** Luma minus the mean of four taps [radius] pixels away, matching [GradeShader]. */
object Clarity {
    fun radius(width: Int, height: Int) = max(1, (min(width, height) * 0.004f).roundToInt())

    /** Display-encoded BT.709 luma in 0..255, one byte per pixel. */
    fun luma(pixels: IntArray, into: ByteArray = ByteArray(pixels.size), offset: Int = 0): ByteArray {
        for (i in pixels.indices) {
            val p = pixels[i]
            into[offset + i] = (0.2126f * (p ushr 16 and 255) + 0.7152f * (p ushr 8 and 255) + 0.0722f * (p and 255)).roundToInt().toByte()
        }
        return into
    }

    fun detail(luma: ByteArray, width: Int, height: Int, x: Int, y: Int, radius: Int): Float {
        fun at(dx: Int, dy: Int) = luma[(y + dy).coerceIn(0, height - 1) * width + (x + dx).coerceIn(0, width - 1)].toInt() and 255
        val blur = (at(radius, 0) + at(-radius, 0) + at(0, radius) + at(0, -radius)) / 4f
        return (at(0, 0) - blur) / 255f
    }
}
