package com.aquarestore.app

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.GlObjectsProvider
import androidx.media3.common.GlTextureInfo
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect

class GradeState(@Volatile var grade: Grade = Grade()) {
    @Volatile var compare = false
    /** Source frames per second that are graded and shown; the rest are dropped before grading. 0 keeps every frame. */
    @Volatile var frameRate = 0f
}

/** Compiled once. Slider changes update uniforms without rebuilding the player or decoder. */
class UnderwaterEffect(private val state: GradeState) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): BaseGlShaderProgram {
        return Shader(state, useHdr)
    }

    internal open class Shader(private val state: GradeState, private val hdr: Boolean) : BaseGlShaderProgram(hdr, 1) {
        private val program = GlProgram(VERTEX, GradeShader.FRAGMENT).apply {
            setBufferAttribute("aPosition", floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f), 2)
        }
        private var texel = floatArrayOf(1f, 1f)
        private var radius = 1f
        private var cadence: FrameCadence? = null
        private var cadenceRate = 0f
        override fun queueInputFrame(glObjectsProvider: GlObjectsProvider, inputTexture: GlTextureInfo, presentationTimeUs: Long) {
            val rate = state.frameRate
            if (rate != cadenceRate) { cadenceRate = rate; cadence = if (rate > 0f) FrameCadence(rate) else null }
            if (cadence?.accept(presentationTimeUs) == false) {
                getInputListener().onInputFrameProcessed(inputTexture)
                getInputListener().onReadyToAcceptInputFrame()
                return
            }
            super.queueInputFrame(glObjectsProvider, inputTexture, presentationTimeUs)
        }
        override fun flush() { cadence?.reset(); super.flush() }
        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            texel = floatArrayOf(1f / inputWidth, 1f / inputHeight)
            radius = Clarity.radius(inputWidth, inputHeight).toFloat()
            return Size(inputWidth, inputHeight)
        }
        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            try {
                val p = state.grade.effective()
                program.use()
                program.setSamplerTexIdUniform("uTexture", inputTexId, 0)
                program.setFloatsUniform("uA", floatArrayOf(p.red, p.temperature, p.tint, p.exposure))
                program.setFloatsUniform("uB", floatArrayOf(p.haze, p.contrast, p.saturation, p.shadows))
                program.setFloatsUniform("uBlack", floatArrayOf(p.blackR, p.blackG, p.blackB, 0f))
                program.setFloatsUniform("uWhite", floatArrayOf(p.whiteR, p.whiteG, p.whiteB, 1f))
                // HDR uses only the amount; its SDR thumbnail endpoints are never sent into the HDR curve.
                program.setFloatUniform("uLevels", p.levels)
                program.setIntUniform("uHdr", if (hdr) 1 else 0)
                program.setFloatUniform("uStrength", if (state.compare) 0f else p.strength)
                program.setFloatUniform("uCoolProtection", p.coolProtection)
                program.setFloatUniform("uClarity", p.clarity)
                program.setFloatsUniform("uTexel", texel)
                program.setFloatUniform("uRadius", radius)
                program.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GlUtil.checkGlError()
            } catch (e: GlUtil.GlException) {
                throw VideoFrameProcessingException(e, presentationTimeUs)
            }
        }
        override fun release() {
            super.release()
            program.delete()
        }
    }
    companion object {
        private const val VERTEX = """
            attribute vec2 aPosition;
            varying vec2 vUv;
            void main() { gl_Position = vec4(aPosition, 0.0, 1.0); vUv = aPosition * 0.5 + 0.5; }
        """
    }
}
