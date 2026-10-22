package com.aquarestore.app

import kotlin.math.*

/** Color statistics behind a recommendation. */
data class Analysis(val grade: Grade, val confidence: Float, val cast: String, val redLoss: Float)

/** Public stand-in for the private grading core: a basic gray-world estimate. */
object AutoGrade {
    fun analyze(frames: List<IntArray>, hdr: Boolean = false): Analysis {
        require(frames.isNotEmpty())
        var r = 0.0; var g = 0.0; var b = 0.0
        var valid = 0; var visible = 0
        for (frame in frames) for (argb in frame) {
            if ((argb ushr 24) <= 127) continue
            visible++
            val pr = (argb ushr 16 and 255) / 255f
            val pg = (argb ushr 8 and 255) / 255f
            val pb = (argb and 255) / 255f
            // Skip near-black noise and clipped highlights.
            if (max(pr, max(pg, pb)) < 0.04f || max(pr, max(pg, pb)) > 0.97f) continue
            r += pr; g += pg; b += pb; valid++
        }
        if (valid == 0) return Analysis(Grade.Neutral, 0f, "insufficient", 0f)
        val mr = (r / valid).toFloat(); val mg = (g / valid).toFloat(); val mb = (b / valid).toFloat()
        val surviving = max(mg, mb).coerceAtLeast(0.03f)
        val loss = ((surviving - mr) / surviving).coerceIn(0f, 1f)
        val grade = Grade.Neutral.copy(
            red = (loss * 0.8f).coerceIn(0f, 0.8f),
            temperature = ((mb - mr) / surviving * 0.4f).coerceIn(0f, 0.4f),
            tint = ((mg - mb) / surviving * 0.5f).coerceIn(0f, 0.4f),
            contrast = 0.05f,
            saturation = 0.1f * loss,
            strength = 0.8f,
        )
        val cast = when {
            loss < 0.1f -> "balanced"
            mg > mb -> "green"
            else -> "blue"
        }
        return Analysis(grade, valid.toFloat() / max(1, visible), cast, loss)
    }
}
