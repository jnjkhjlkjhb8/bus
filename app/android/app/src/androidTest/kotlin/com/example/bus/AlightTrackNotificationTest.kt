package com.example.bus

import android.app.Notification
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.test.runner.AndroidJUnit4
import io.flutter.plugin.common.BinaryMessenger
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * On-device checks for the alight-tracking card.
 *
 * The interesting assertion here cannot be made off-device: whether the system
 * will actually promote the notification to a status-bar chip is decided by
 * `Notification.hasPromotableCharacteristics()` inside the platform, against
 * rules (allowed styles, ongoing flag, required title) that our builder can
 * only try to satisfy. A unit test would assert our own intent back to us.
 *
 * `POST_ALL` posts every state to the device's shade so the card can be looked
 * at as well as asserted.
 */
@RunWith(AndroidJUnit4::class)
class AlightTrackNotificationTest {

    private lateinit var context: Context
    private lateinit var card: TrackNotification
    private lateinit var plugin: LiveActivityPlugin

    /** Set true to leave the cards on screen for a visual pass. */
    private val postToShade = true

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        card = TrackNotification(context)
        plugin = LiveActivityPlugin(
            context,
            NotificationPermissionCoordinator(
                alreadyGranted = { true },
                requiresRuntimePermission = { false },
                launchRequest = {},
            ),
        )
        card.ensureChannel()
    }

    private fun payload(
        mode: String = "metro",
        phase: String = "riding",
        vehicleLabel: String = "板南線",
        vehicleId: String? = "1021",
        board: String = "台北車站",
        target: String = "南港展覽館",
        next: String = "忠孝復興",
        hopCount: Int = 9,
        currentIndex: Int = 5,
        remainingStops: Int = 4,
        leadStops: Int = 2,
        etaMinutes: Int? = null,
        trackId: String? = null,
    ) = mapOf<String, Any?>(
        "trackId" to trackId,
        "mode" to mode,
        "phase" to phase,
        "vehicleLabel" to vehicleLabel,
        "vehicleId" to vehicleId,
        "boardStation" to board,
        "targetStation" to target,
        "nextStation" to next,
        "hopCount" to hopCount,
        "currentIndex" to currentIndex,
        "remainingStops" to remainingStops,
        "leadStops" to leadStops,
        "etaMinutes" to etaMinutes,
        "walkMinutes" to 0,
    )

    private fun show(id: Int, notification: Notification) {
        if (!postToShade) return
        NotificationManagerCompat.from(context).notify(id, notification)
    }

    @Test
    fun aRidingCardIsPromotable() {
        assumeTrue(Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA)
        val n = card.buildTrack(payload())
        show(9001, n)

        // The single assertion the platform, not we, decide.
        assertTrue(
            "the riding card must satisfy the Live Update promotion rules",
            n.hasPromotableCharacteristics(),
        )
        assertEquals("往 南港展覽館", n.extras.getString(Notification.EXTRA_TITLE))
        assertEquals(
            "板南線 1021 · 下一站 忠孝復興",
            n.extras.getString(Notification.EXTRA_TEXT),
        )
        assertEquals("剩4站", n.shortCriticalText)
        // ProgressStyle is one of the handful of styles a promoted card may
        // use; the segmented bar is the whole reason this card exists.
        assertTrue(
            "expected a ProgressStyle card, got " +
                n.extras.getString(Notification.EXTRA_TEMPLATE),
            n.extras.getString(Notification.EXTRA_TEMPLATE)
                ?.contains("ProgressStyle") == true,
        )
        assertNotNull("取消追蹤 must be reachable from the card", n.actions)
        assertEquals(1, n.actions.size)
        assertEquals("取消追蹤", n.actions[0].title)
    }

    /**
     * The four networks share one card: only the strings inside it change.
     * If a mode ever grows its own layout again, this is what fails.
     */
    @Test
    fun everyNetworkProducesTheSameCard() {
        assumeTrue(Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA)
        val cards = listOf(
            payload(mode = "bus", vehicleLabel = "307", vehicleId = "KKA-1234"),
            payload(mode = "tra", vehicleLabel = "自強 408", vehicleId = null),
            payload(mode = "thsr", vehicleLabel = "高鐵 663", vehicleId = null),
            payload(mode = "metro"),
        ).mapIndexed { i, p ->
            card.buildTrack(p).also { show(9010 + i, it) }
        }

        cards.forEach { n ->
            assertTrue(n.hasPromotableCharacteristics())
            assertEquals("往 南港展覽館", n.extras.getString(Notification.EXTRA_TITLE))
            assertEquals("剩4站", n.shortCriticalText)
            assertEquals(1, n.actions.size)
        }
        // One card, but the chip still names the network: the small icon is
        // the only mode-specific thing on the whole surface.
        assertEquals(
            listOf(
                R.drawable.ic_track_bus,
                R.drawable.ic_track_rail,
                R.drawable.ic_track_rail,
                R.drawable.ic_track_metro,
            ),
            cards.map { it.smallIcon.resId },
        )
        assertEquals(
            listOf(
                "307 KKA-1234 · 下一站 忠孝復興",
                "自強 408 · 下一站 忠孝復興",
                "高鐵 663 · 下一站 忠孝復興",
                "板南線 1021 · 下一站 忠孝復興",
            ),
            cards.map { it.extras.getString(Notification.EXTRA_TEXT) },
        )
    }

    /**
     * The colour ramp is keyed on the rider's own 提前站數.
     *
     * `Notification.color` only tints the header — on a Pixel 8 / Android 17
     * the status-bar chip stays a system neutral and the action text follows
     * the device accent, whatever we pass. Distance is therefore carried by
     * the progress bar (Segment.setColor, which is honoured) and by the chip's
     * wording; this test pins the header tint and the wording.
     */
    @Test
    fun theChipStaysInkUntilTheLastStop() {
        val ink = context.getColor(R.color.track_ink)
        val arriving = context.getColor(R.color.track_arriving)

        val far = card.buildTrack(payload(remainingStops = 6, leadStops = 2))
        val past = card.buildTrack(payload(remainingStops = 2, leadStops = 2))
        val last = card.buildTrack(payload(remainingStops = 1, leadStops = 2))
        show(9020, far)
        show(9021, past)
        show(9022, last)

        assertEquals(ink, far.color)
        // Past the rider's own threshold the bar warms up, but the chip does
        // not: "get ready" is not "you are out of time".
        assertEquals(ink, past.color)
        assertEquals(arriving, last.color)

        assertEquals("剩6站", far.shortCriticalText)
        assertEquals("剩2站", past.shortCriticalText)
        assertEquals("下一站", last.shortCriticalText)
        assertEquals(
            "準備下車 · 下一站 忠孝復興",
            last.extras.getString(Notification.EXTRA_TEXT),
        )
    }

    /**
     * Waiting is the same card at hop zero, counting minutes instead of stops
     * — not the separate card it used to be.
     */
    @Test
    fun waitingIsTheSameCardAtHopZero() {
        val n = card.buildTrack(
            payload(
                phase = "waiting",
                mode = "bus",
                vehicleLabel = "307",
                vehicleId = null,
                currentIndex = 0,
                remainingStops = 9,
                etaMinutes = 8,
            ),
        )
        show(9030, n)

        assertEquals("往 南港展覽館", n.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("307 · 於 台北車站 上車", n.extras.getString(Notification.EXTRA_TEXT))
        assertEquals("8分", n.shortCriticalText)
    }

    /**
     * An ending must be seen. It drops the chip and the cancel action, but it
     * is still a card until Dart dismisses the lease.
     */
    @Test
    fun terminalStatesStopBeingOngoingButStillRead() {
        val arrived = card.buildTrack(payload(phase = "arrived", remainingStops = 0))
        val lost = card.buildTrack(payload(phase = "lost"))
        show(9040, arrived)
        show(9041, lost)

        assertEquals("已到 南港展覽館", arrived.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("已到站", arrived.shortCriticalText)
        assertEquals(0, arrived.flags and Notification.FLAG_ONGOING_EVENT)
        assertTrue(arrived.actions == null || arrived.actions.isEmpty())

        assertEquals("追蹤失效", lost.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("請重新綁定", lost.extras.getString(Notification.EXTRA_TEXT))
        assertEquals("失效", lost.shortCriticalText)
    }

    /**
     * A live card carries its own retirement so a process the system kills
     * mid-ride cannot leave an un-swipeable card whose numbers never move
     * again. Per mode, because the feeds behind them are not one cadence — and
     * never on a terminal card, which Dart dismisses after its own linger.
     */
    @Test
    fun aLiveCardRetiresItselfPerModeAndATerminalOneDoesNot() {
        val bus = card.buildTrack(payload(mode = "bus"))
        val metro = card.buildTrack(payload(mode = "metro"))
        val rail = card.buildTrack(payload(mode = "tra"))
        val arrived = card.buildTrack(payload(phase = "arrived", remainingStops = 0))

        assertEquals(6 * 60 * 1000L, bus.timeoutAfter)
        assertEquals(12 * 60 * 1000L, metro.timeoutAfter)
        assertEquals(40 * 60 * 1000L, rail.timeoutAfter)
        assertEquals(0L, arrived.timeoutAfter)

        // Each window has to outlast the gap between two updates of a living
        // session, or a card would vanish under a rider who is still riding.
        assertTrue(bus.timeoutAfter > 60 * 1000L)
    }

    /**
     * register() registers a context-wide BroadcastReceiver and installs a
     * channel handler, both of which outlive the FlutterEngine that created
     * them unless dispose() takes them back down. unregisterReceiver throws
     * IllegalArgumentException for a receiver that is not registered, so a
     * second unregister succeeding-by-throwing is the proof the first one
     * actually happened.
     */
    @Test
    fun disposeUnregistersTheCancelReceiver() {
        plugin.register(NoopMessenger())
        plugin.dispose()

        var threw = false
        try {
            context.unregisterReceiver(plugin.cancelReceiverForTest)
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue("dispose() left the cancel receiver registered", threw)

        // Idempotent: a second dispose must not throw on the already-gone
        // receiver, so an engine teardown after an activity finish is safe.
        plugin.dispose()
    }

    /**
     * A server-pushed refresh (ADR-0018) arrives over FCM, whose data values
     * are all strings — the same fields reach the MethodChannel path as
     * numbers. One builder serves both, so it has to read either.
     */
    @Test
    fun buildsTheSameCardFromStringValuedFields() {
        val numbers = card.buildTrack(payload(remainingStops = 4, leadStops = 2))
        val strings = card.buildTrack(
            payload(remainingStops = 4, leadStops = 2).mapValues { (_, value) ->
                if (value is Number) value.toString() else value
            },
        )

        assertEquals(
            numbers.extras.getCharSequence(Notification.EXTRA_TITLE),
            strings.extras.getCharSequence(Notification.EXTRA_TITLE),
        )
        assertEquals(
            numbers.extras.getCharSequence(Notification.EXTRA_TEXT),
            strings.extras.getCharSequence(Notification.EXTRA_TEXT),
        )
        assertEquals(
            numbers.extras.getCharSequence(Notification.EXTRA_SHORT_CRITICAL_TEXT),
            strings.extras.getCharSequence(Notification.EXTRA_SHORT_CRITICAL_TEXT),
        )
    }

    /**
     * A cancel has to stick through the refresh already in flight behind it.
     * Ending the session stops new pushes, but one in the air still lands, and
     * reposting a card the rider just dismissed is worse than never having
     * pushed at all.
     */
    @Test
    fun refusesARefreshForASessionJustCancelled() {
        card.beginSession()
        assertTrue(card.post(payload(trackId = "ride-1")))

        card.cancel("ride-1")

        assertFalse(
            "a refresh in flight reposted a card the rider had just cancelled",
            card.post(payload(trackId = "ride-1", remainingStops = 3)),
        )
        // Scoped to the session, not to the card: the next ride must not
        // inherit the last one's dismissal.
        assertTrue(card.post(payload(trackId = "ride-2", remainingStops = 3)))

        card.cancel("ride-2")
        // And starting a session clears it outright, so re-tracking the same
        // ride right after cancelling it still works.
        card.beginSession()
        assertTrue(card.post(payload(trackId = "ride-2", remainingStops = 3)))
        card.cancel()
    }

    /**
     * Dart dismisses a terminal card after its own linger, but a card pushed to
     * a process that is gone has no Dart to do it, and 已到站 would sit in the
     * shade until someone swiped it. This is iOS's `dismissal-date`, Android
     * side.
     */
    @Test
    fun aTerminalCardRetiresItselfWithoutAnApp() {
        val arrived = card.buildTrack(payload(phase = "arrived", remainingStops = 0))
        val lost = card.buildTrack(payload(phase = "lost"))

        for (n in listOf(arrived, lost)) {
            assertTrue("a terminal card was left with no timeout", n.timeoutAfter > 0)
            // Longer than Dart's own linger, so the app still owns the
            // dismissal whenever it is alive to do it.
            assertTrue(n.timeoutAfter in 6_000..30_000)
        }
    }

    /**
     * Two writers now reach one card — the app while it is awake, and a server
     * push while it is not — and they can race. Ordering them by clock is not
     * available (two machines, one card), so the card takes the reading that is
     * further along: a ride only ever moves toward the alight stop.
     */
    @Test
    fun dropsAPushedReadingOlderThanTheOneOnScreen() {
        card.beginSession()

        assertTrue("the first reading of a session must always draw", card.post(payload(remainingStops = 4)))
        assertTrue("a later reading must draw", card.post(payload(remainingStops = 2)))
        assertFalse(
            "a push that lost its race to a local update must not put the ride back",
            card.post(payload(remainingStops = 3)),
        )
        // An ending is the one reading that is never discarded.
        assertTrue(card.post(payload(phase = "arrived", remainingStops = 0)))

        // A new ride is not judged against the last one's progress.
        card.beginSession()
        assertTrue(card.post(payload(remainingStops = 9)))

        card.cancel()
    }
}

/** A BinaryMessenger that goes nowhere — register() only needs one to exist. */
private class NoopMessenger : BinaryMessenger {
    override fun send(channel: String, message: java.nio.ByteBuffer?) = Unit

    override fun send(
        channel: String,
        message: java.nio.ByteBuffer?,
        callback: BinaryMessenger.BinaryReply?,
    ) = Unit

    override fun setMessageHandler(
        channel: String,
        handler: BinaryMessenger.BinaryMessageHandler?,
    ) = Unit
}
