package com.mossapps.flick

import java.util.concurrent.Executor
import org.junit.Assert.*
import org.junit.Test

class LatestArtworkLoaderTest {
    private class Queue : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) { tasks.add(command) }
        fun runNext() = tasks.removeFirst().run()
    }
    @Test fun slowStorageNeverRunsOnCallerAndStaleArtIsDiscarded() {
        val worker = Queue(); val main = Queue()
        var reads = 0; var notifications = 0
        val loader = LatestArtworkLoader(worker, main, { path -> reads++; path }, { notifications++ })
        assertNull(loader.get("first"))
        assertEquals(0, reads)
        assertNull(loader.get("second"))
        worker.runNext(); main.runNext()
        assertEquals(0, notifications)
        worker.runNext(); main.runNext()
        assertEquals("second", loader.get("second"))
        assertEquals(1, notifications)
        assertEquals(2, reads)
    }
    @Test fun closedServiceAndRemovedArtworkIgnorePendingResults() {
        val worker = Queue(); val main = Queue()
        var notifications = 0
        val loader = LatestArtworkLoader(worker, main, { path -> path }, { notifications++ })
        loader.get("first"); loader.get(null)
        worker.runNext(); main.runNext()
        assertEquals(0, notifications)
        loader.get("second"); loader.close()
        worker.runNext(); main.runNext()
        assertNull(loader.get("second"))
        assertEquals(0, notifications)
    }
}
