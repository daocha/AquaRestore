package com.aquarestore.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal class ReferralProof(private val context: Context) {
    private val usesDebugToken = BuildConfig.DEBUG && !BuildConfig.REFERRAL_VERIFY_PLATFORM
    val platform: String = if (usesDebugToken) "debug" else "android"
    // Each explicit submission gets fresh hardware attestation of the server's challenge.
    val keyId: String = if (usesDebugToken) ReferralCampaign.identity(context) else UUID.randomUUID().toString()
    suspend fun proof(clientData: String): JSONObject {
        if (usesDebugToken) {
            check(BuildConfig.REFERRAL_DEBUG_TOKEN.length >= 32) { "Configure the debug referral credential" }
            return JSONObject().put("token", BuildConfig.REFERRAL_DEBUG_TOKEN)
        }
        val data = Base64.decode(clientData, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        val alias = "referral-attest-v2-$keyId"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        try {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setAttestationChallenge(MessageDigest.getInstance("SHA-256").digest(data)).build())
            }.generateKeyPair()
            val entry = store.getEntry(alias, null) as KeyStore.PrivateKeyEntry
            val signature = Signature.getInstance("SHA256withECDSA").apply {
                initSign(entry.privateKey); update(data)
            }.sign()
            val chain = JSONArray()
            store.getCertificateChain(alias).forEach { chain.put(encode(it.encoded)) }
            return JSONObject().put("certificateChain", chain).put("signature", encode(signature))
        } finally {
            // No key is needed after signing; retries obtain a new challenge and attestation.
            if (store.containsAlias(alias)) store.deleteEntry(alias)
        }
    }
    private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
}
