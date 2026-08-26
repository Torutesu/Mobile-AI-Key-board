package com.torutesu.mobileaikeyboard.core

/** Only typed, content-free events can be emitted by the mobile foundation. */
sealed interface TelemetryEvent {
    data class KeyboardOpened(val cold: Boolean, val locale: String, val version: String) : TelemetryEvent
    data class CommandStarted(val skillId: String, val riskClass: String, val sourceTypes: Set<InputSource>) : TelemetryEvent
    data class PlanReviewed(val planType: String, val outcome: ReviewOutcome, val latencyBucket: String) : TelemetryEvent
    data class ExecutionFinished(val operation: String, val outcome: ExecutionOutcome, val latencyBucket: String) : TelemetryEvent
    data class ResultApplied(val method: ApplyMethod, val characterCountBucket: String) : TelemetryEvent
}

enum class ReviewOutcome { ACCEPTED, EDITED, CANCELLED }
enum class ExecutionOutcome { SUCCEEDED, FAILED, PARTIAL, UNKNOWN }
enum class ApplyMethod { INSERTION, REPLACEMENT, COPY }

fun interface ContentFreeTelemetry {
    fun record(event: TelemetryEvent)
}

object NoOpTelemetry : ContentFreeTelemetry {
    override fun record(event: TelemetryEvent) = Unit
}
