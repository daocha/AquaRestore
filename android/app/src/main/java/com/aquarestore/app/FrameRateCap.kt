package com.aquarestore.app

import android.content.Context
import androidx.media3.common.GlObjectsProvider
import androidx.media3.common.GlTextureInfo
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

/** Unlike nearest-interval dropping, accumulated slots correctly convert 30 → 24 fps. */
class FrameRateCap(private val fps: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        object : UnderwaterEffect.Shader(GradeState(Grade.Neutral), useHdr) {
            private val cadence = FrameCadence(fps)
            override fun queueInputFrame(glObjectsProvider: GlObjectsProvider, inputTexture: GlTextureInfo, presentationTimeUs: Long) {
                if (cadence.accept(presentationTimeUs)) {
                    super.queueInputFrame(glObjectsProvider, inputTexture, presentationTimeUs)
                } else {
                    getInputListener().onInputFrameProcessed(inputTexture)
                    getInputListener().onReadyToAcceptInputFrame()
                }
            }
            override fun flush() { cadence.reset(); super.flush() }
        }
}
