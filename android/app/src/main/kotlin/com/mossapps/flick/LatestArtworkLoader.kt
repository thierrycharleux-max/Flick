package com.mossapps.flick

import java.util.concurrent.Executor

/** Never waits for storage on the caller thread; stale results cannot replace a new cover. */
internal class LatestArtworkLoader<T>(
    private val worker: Executor,
    private val main: Executor,
    private val decode: (String) -> T?,
    private val ready: () -> Unit,
) {
    private var path: String? = null
    private var generation = 0
    private var value: T? = null
    private var closed = false

    fun get(requested: String?): T? {
        if (closed) return null
        if (requested == path) return value
        path = requested
        value = null
        val token = ++generation
        if (!requested.isNullOrEmpty()) {
            worker.execute {
                val result = try { decode(requested) } catch (_: Exception) { null }
                main.execute {
                    if (!closed && token == generation) {
                        value = result
                        ready()
                    }
                }
            }
        }
        return value
    }

    fun close() {
        closed = true
        generation++
        value = null
    }
}
