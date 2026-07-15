package com.example.bus

/**
 * Serializes POST_NOTIFICATIONS permission requests on Android 13+.
 *
 * The runtime permission is granted or denied through the
 * `onRequestPermissionsResult` callback ([onPermissionResult]) that arrives
 * asynchronously — there is no synchronous return value from requesting it.
 * A caller that needs the permission before posting a notification calls
 * [request] with a completion callback; that callback fires exactly once
 * with the resolved grant state:
 *  - synchronously, if the permission is already granted or the running
 *    OS predates the runtime-permission requirement ([requiresRuntimePermission]
 *    false), so callers never have to special-case "no request needed";
 *  - otherwise after the next [onPermissionResult] call.
 *
 * Only one system request is ever in flight: a [request] that arrives while
 * one is already pending queues its callback behind it instead of issuing a
 * second `requestPermissions` call (which would either throw or be silently
 * ignored by the platform, and would make it ambiguous which caller's
 * callback corresponds to which grant/deny result).
 *
 * Pure Kotlin — no Android SDK types — so it is unit-testable with plain
 * JUnit; the caller (an Activity) supplies the platform checks/request as
 * lambdas.
 */
class NotificationPermissionCoordinator(
    private val alreadyGranted: () -> Boolean,
    private val requiresRuntimePermission: () -> Boolean,
    private val launchRequest: () -> Unit,
) {
    private val pending = ArrayDeque<(Boolean) -> Unit>()

    /** True while a system permission request is in flight, awaiting [onPermissionResult]. */
    val hasPendingRequest: Boolean
        get() = !pending.isEmpty()

    fun request(onResult: (Boolean) -> Unit) {
        if (!requiresRuntimePermission() || alreadyGranted()) {
            onResult(true)
            return
        }
        val wasEmpty = pending.isEmpty()
        pending.addLast(onResult)
        if (wasEmpty) {
            launchRequest()
        }
    }

    /** Called from `onRequestPermissionsResult` with the user's decision. */
    fun onPermissionResult(granted: Boolean) {
        val callbacks = ArrayList<(Boolean) -> Unit>(pending)
        pending.clear()
        for (callback in callbacks) {
            callback(granted)
        }
    }
}
