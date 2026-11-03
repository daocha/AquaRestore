package com.aquarestore.app

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

/** Composites the original over the existing grader's output while its input texture is still valid. */
class ComparisonEffect(private val grade: Grade, private val durationUs: Long) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        object : UnderwaterEffect.Shader(GradeState(grade), useHdr) {
            private val copy = GlProgram("""
                attribute vec4 aPosition;
                varying vec2 vUv;
                void main() { gl_Position = aPosition; vUv = (aPosition.xy + 1.0) * 0.5; }
            """.trimIndent(), """
                precision highp float;
                uniform sampler2D uTexture;
                varying vec2 vUv;
                void main() { gl_FragColor = texture2D(uTexture, vUv); }
            """.trimIndent()).apply { setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4) }
            private var width = 0
            private var height = 0
            private var firstTime: Long? = null
            override fun configure(inputWidth: Int, inputHeight: Int): Size = super.configure(inputWidth, inputHeight).also {
                width = it.width; height = it.height
            }
            override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
                super.drawFrame(inputTexId, presentationTimeUs)
                if (firstTime == null) firstTime = presentationTimeUs
                val fraction = (presentationTimeUs - firstTime!!).toFloat() / durationUs.coerceAtLeast(1)
                val split = (width * ((fraction - .25f) / .5f).coerceIn(0f, 1f)).toInt()
                GLES20.glEnable(GLES20.GL_SCISSOR_TEST)
                try {
                    GLES20.glScissor(split, 0, width - split, height)
                    copy.use(); copy.setSamplerTexIdUniform("uTexture", inputTexId, 0)
                    copy.bindAttributesAndUniforms(); GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                    if (split in 1 until width) {
                        GLES20.glScissor(split, 0, maxOf(1, width / 400), height)
                        GLES20.glClearColor(1f, 1f, 1f, 1f); GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                    }
                } finally { GLES20.glDisable(GLES20.GL_SCISSOR_TEST); GLES20.glClearColor(0f, 0f, 0f, 0f) }
                GlUtil.checkGlError()
            }
            override fun flush() { firstTime = null; super.flush() }
            override fun release() { try { copy.delete() } finally { super.release() } }
        }
}
