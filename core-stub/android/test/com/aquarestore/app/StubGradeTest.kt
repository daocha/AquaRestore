package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

/** The contract the app relies on, whichever core is in use. */
class StubGradeTest {
    @Test fun zeroIntensityIsBitExact() {
        val pixel = 0x80205f9f.toInt()
        assertEquals(pixel, ColorGrade.pixel(pixel, Grade.Blue.copy(strength = 0f)))
    }
    @Test fun neutralGradeIsIdentity() {
        val pixel = 0xff205f9f.toInt()
        assertEquals(pixel, ColorGrade.pixel(pixel, Grade.Neutral.copy(strength = 1f)))
    }
    @Test fun blackFramesGetNoRecommendation() {
        val analysis = AutoGrade.analyze(listOf(IntArray(64) { 0xff000000.toInt() }))
        assertEquals(0f, analysis.confidence, 0f)
    }
    @Test fun blueWaterGetsRedRecovery() {
        val analysis = AutoGrade.analyze(listOf(IntArray(64) { 0xff2080c0.toInt() }))
        assertTrue(analysis.grade.red > 0f)
        assertEquals("blue", analysis.cast)
    }
}
