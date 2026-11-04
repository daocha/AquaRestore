package com.aquarestore.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.opengl.EGL14
import android.opengl.GLES20
import android.opengl.GLES30
import androidx.media3.common.C
import androidx.media3.common.util.GlUtil
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextureOverlay
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Runs the overlay in Media3's HDR mode directly, because an emulator has no HDR encoder for a whole comparison. */
@RunWith(AndroidJUnit4::class)
class ComparisonCreditTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    /** A frame of dark red, with the left half of the credit white and the right half clear. Returns one pixel each. */
    private fun draw(overlay: (Bitmap) -> TextureOverlay): Pair<FloatArray, FloatArray> {
        val size = 16
        val credit = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(credit).drawRect(0f, 0f, size / 2f, size.toFloat(), android.graphics.Paint().apply { color = Color.WHITE })
        val display = GlUtil.getDefaultEglDisplay()
        val egl = GlUtil.createEglContext(EGL14.EGL_NO_CONTEXT, display, 3, GlUtil.EGL_CONFIG_ATTRIBUTES_RGBA_8888)
        try {
            val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
            val found = IntArray(1)
            assertTrue(EGL14.eglChooseConfig(display, GlUtil.EGL_CONFIG_ATTRIBUTES_RGBA_8888, 0, configs, 0, 1, found, 0))
            val surface = EGL14.eglCreatePbufferSurface(display, configs[0],
                intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
            assertTrue(EGL14.eglMakeCurrent(display, surface, surface, egl))
            val input = GlUtil.createTexture(size, size, true)
            val inputFbo = GlUtil.createFboForTexture(input)
            GlUtil.focusFramebufferUsingCurrentContext(inputFbo, size, size)
            GLES20.glClearColor(0.1f, 0f, 0f, 1f); GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            val output = GlUtil.createTexture(size, size, true)
            GlUtil.focusFramebufferUsingCurrentContext(GlUtil.createFboForTexture(output), size, size)
            val program = OverlayEffect(java.util.ArrayList(listOf(overlay(credit)))).toGlShaderProgram(context, true)
            program.configure(size, size)
            program.drawFrame(input, 0)
            val pixels = ByteBuffer.allocateDirect(size * size * 16).order(ByteOrder.nativeOrder())
            GLES30.glReadPixels(0, 0, size, size, GLES20.GL_RGBA, GLES20.GL_FLOAT, pixels)
            GlUtil.checkGlError()
            val floats = pixels.asFloatBuffer()
            fun at(x: Int) = FloatArray(4) { floats.get((size / 2 * size + x) * 4 + it) }
            program.release()
            return at(2) to at(size - 2)
        } finally {
            GlUtil.destroyEglContext(display, egl)
            credit.recycle()
        }
    }

    @Test fun aPlainBitmapOverlayIsRefusedInHdr() {
        val failure = assertThrows(IllegalArgumentException::class.java) {
            draw { BitmapOverlay.createStaticBitmapOverlay(it) }
        }
        assertNotNull(failure)
    }

    @Test fun theCreditDrawsInHdrAtReferenceWhite() {
        for ((transfer, white) in listOf(C.COLOR_TRANSFER_ST2084 to 0.0203f, C.COLOR_TRANSFER_HLG to 0.265f)) {
            val (credited, clear) = draw { ShareMediaMaker.creditOverlay(it, transfer) }
            assertEquals(white, credited[0], 0.002f)
            assertEquals(white, credited[1], 0.002f)
            assertEquals(white, credited[2], 0.002f)
            assertEquals(0.1f, clear[0], 0.002f)
            assertEquals(0f, clear[1], 0.002f)
        }
    }
}
