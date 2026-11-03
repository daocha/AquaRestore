package com.aquarestore.app
import org.junit.Assert.*
import org.junit.Test

class BatchVerifierTest {
    @Test fun acceptsUtf8BuildVerifierAndRejectsIncorrectCode() {
        val salt = "000102030405060708090a0b0c0d0e0f"
        val verifier = "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3"
        assertTrue(BatchAccess.verify("sample-測試-5678", salt, verifier))
        assertFalse(BatchAccess.verify("wrong", salt, verifier))
    }
}
