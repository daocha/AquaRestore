package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class ReferralCampaignTest {
    @Test fun identityIsStableScopedToPackageAndMatchesIosAndServer() {
        val identity = ReferralIdentity.deviceId("com.aquarestore.app.debug", "example-device")
        assertEquals("c0601a35a34fdbb2e2301d1aa9eaf67449ebe97535273a9be2b9c35eda096e4a", identity)
        assertEquals("27rmwzCkFT", ReferralIdentity.code(identity))
        assertNotEquals(identity, ReferralIdentity.deviceId("com.aquarestore.app", "example-device"))
        assertEquals("1WMXIE6mD6", ReferralIdentity.code("0".repeat(64)))
        assertEquals("30StFvia8u", ReferralIdentity.code("f".repeat(64)))
    }
    @Test fun theCodeTheServerIssuedWinsOverTheCalculatedOne() {
        val identity = "0".repeat(64)
        assertEquals("1WMXIE6mD6", ReferralIdentity.ownCode(identity, null))
        assertEquals("40094aXX1F", ReferralIdentity.ownCode(identity, "40094aXX1F"))
    }
    @Test fun stateRestoresExistingBindingAndReadsIndependentGrants() {
        val state = ReferralState.parse(JSONObject("""{"referralCount":5,"referredByCode":"40094aXX1F","unlocked":{"batchPhoto":true,"batchVideo":false}}"""))
        assertEquals(5, state.count)
        assertEquals("40094aXX1F", state.referredBy)
        assertTrue(state.photo)
        assertFalse(state.video)
    }
    @Test fun registrationResponseWithItsExtraFieldRestoresState() {
        val state = ReferralState.parse(JSONObject("""{"referralCode":"40094aXX1F","referralCount":0,"referredByCode":"0000000001","unlocked":{"batchPhoto":false,"batchVideo":false},"alreadyRegistered":true}"""))
        assertEquals("0000000001", state.referredBy)
        assertEquals("40094aXX1F", state.code)
    }
    @Test fun aDeviceStateWithoutACodeIsAllowedButAMalformedCodeIsNot() {
        assertNull(ReferralState.parse(JSONObject("""{"referralCode":null,"referralCount":0,"referredByCode":null,"unlocked":{"batchPhoto":false,"batchVideo":false}}""")).code)
        assertTrue(runCatching { ReferralState.parse(JSONObject("""{"referralCode":"short","referralCount":0,"unlocked":{"batchPhoto":false,"batchVideo":false}}""")) }.isFailure)
    }
    @Test fun onlyWellFormedCodesFromOtherDevicesAreSent() {
        assertTrue(ReferralIdentity.acceptable("40094aXX1F", "0000000001"))
        for (code in listOf("", "short", "40094aXX1F0", "40094aXX1-", "0000000001")) {
            assertFalse(code, ReferralIdentity.acceptable(code, "0000000001"))
        }
    }
    @Test fun inviteKeepsTheCodeOnItsOwnLineInBothLanguages() {
        for (chinese in listOf(false, true)) {
            val lines = ReferralInvite.message(Strings(chinese), "40094aXX1F", ReferralInvite.githubApkUrl).lines()
            assertTrue(lines.contains("40094aXX1F"))
            assertTrue(lines.any { ReferralInvite.githubApkUrl in it })
        }
    }
    @Test fun inviteLinksToTheDistributionTheAppCameFrom() {
        assertEquals("https://github.com/daocha/AquaRestore/releases/latest/download/AquaRestore.apk", ReferralInvite.appUrl(false, "com.aquarestore.app"))
        assertEquals("https://play.google.com/store/apps/details?id=com.aquarestore.app", ReferralInvite.appUrl(true, "com.aquarestore.app"))
    }
    @Test fun pastingAWholeInviteEntersOnlyTheCode() {
        for (chinese in listOf(false, true)) {
            val invite = ReferralInvite.message(Strings(chinese), "3n4AaioTlF", ReferralInvite.githubApkUrl)
            assertEquals("3n4AaioTlF", ReferralIdentity.codeIn(invite))
            assertEquals("3n4AaioTlF", ReferralIdentity.codeIn(invite.replace("\n", " ")))
        }
        assertEquals("3n4AaioTlF", ReferralIdentity.codeIn("Your referral code: 3n4AaioTlF"))
        assertEquals("3n4AaioTlF", ReferralIdentity.codeIn("3n4AaioTlF"))
        assertEquals("abc", ReferralIdentity.codeIn("abc"))
        assertEquals("code: 3n4AaioTlFX", ReferralIdentity.codeIn("code: 3n4AaioTlFX"))
    }
    @Test fun malformedStateCannotUnlock() {
        for (body in listOf("{}", """{"referralCount":-1,"unlocked":{"batchPhoto":true,"batchVideo":true}}""")) {
            assertTrue(runCatching { ReferralState.parse(JSONObject(body)) }.isFailure)
        }
    }
}
