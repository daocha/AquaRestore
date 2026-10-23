package com.aquarestore.app

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReleaseUpdatesTest {
    private fun release(code: Int = 4, tag: String = "v2026.10.24", host: String = "github.com") = JSONObject("""
        {"tag_name":"$tag","draft":false,"prerelease":false,"assets":[
          {"name":"AquaRestore-2026.10.24-$code.apk","size":1234,
           "browser_download_url":"https://$host/daocha/AquaRestore/releases/download/$tag/AquaRestore-2026.10.24-$code.apk"},
          {"name":"AquaRestore-2026.10.24-$code.SHA256SUMS",
           "browser_download_url":"https://$host/daocha/AquaRestore/releases/download/$tag/AquaRestore-2026.10.24-$code.SHA256SUMS"}
        ]}
    """.trimIndent())

    @Test fun onlyNewerCompleteTrustedReleaseIsSelected() {
        assertEquals(4L, ReleaseUpdates.select(release(), 3)?.versionCode)
        assertNull(ReleaseUpdates.select(release(), 4))
        assertNull(ReleaseUpdates.select(release(tag = "vwrong"), 3))
        assertNull(ReleaseUpdates.select(release(host = "example.com"), 3))
        assertNull(ReleaseUpdates.select(release().apply { put("prerelease", true) }, 3))
        assertNull(ReleaseUpdates.select(release().apply { getJSONArray("assets").remove(1) }, 3))
    }

    @Test fun checksumMustMatchSelectedApk() {
        val hash = "a".repeat(64)
        assertEquals(hash, ReleaseUpdates.checksum("$hash  AquaRestore-2026.10.24-4.apk", "AquaRestore-2026.10.24-4.apk"))
        assertNull(ReleaseUpdates.checksum("$hash  other.apk", "AquaRestore-2026.10.24-4.apk"))
        assertNull(ReleaseUpdates.checksum("bad  AquaRestore-2026.10.24-4.apk", "AquaRestore-2026.10.24-4.apk"))
    }

    @Test fun lanUpdateMustBeNewerAndNamedForItsVersion() {
        val base = "http://10.0.0.2:8765/"
        fun lan(code: Int = 9, apk: String = "AquaRestore-debug-$code.apk", size: Int = 1234) =
            JSONObject("""{"versionCode":$code,"versionName":"2026.10.25-debug","apk":"$apk","size":$size}""")
        val update = ReleaseUpdates.selectLan(lan(), 8, base)!!
        assertEquals("http://10.0.0.2:8765/AquaRestore-debug-9.apk", update.apkUrl)
        assertEquals("http://10.0.0.2:8765/AquaRestore-debug-9.SHA256SUMS", update.checksumUrl)
        assertNull(ReleaseUpdates.selectLan(lan(), 9, base))
        assertNull(ReleaseUpdates.selectLan(lan(apk = "../other.apk"), 8, base))
        assertNull(ReleaseUpdates.selectLan(lan(size = 0), 8, base))
    }
}
