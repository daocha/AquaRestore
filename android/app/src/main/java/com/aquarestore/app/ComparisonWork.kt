package com.aquarestore.app

import android.content.Context
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** One optional worker alongside the primary export, independent of its result and lifetime. */
object ComparisonWork {
    class Entry {
        var accepted = false
        var rejected = false
        var done = false
        var assets: List<ShareMedia> = emptyList()
        var job: Job? = null
    }
    private class Session {
        val entries = mutableListOf<Entry>()
        var terminal: ExportStatus? = null
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val worker = Semaphore(1)
    private var session: Session? = null
    fun reset() { dismiss(); session = Session() }
    fun dismiss() {
        val previous = session
        session = null
        previous?.entries?.forEach { it.job?.cancel(); it.assets.forEach { asset -> asset.file.delete() } }
    }
    fun submit(context: Context, request: ExportRequest): Entry? {
        val owner = session ?: return null
        if (owner.entries.count { !it.rejected } >= 2) return null
        val entry = Entry(); owner.entries += entry
        entry.job = scope.launch {
            try {
                entry.assets = worker.withPermit { ShareMediaMaker.make(context.applicationContext, request) }
            } catch (_: CancellationException) { }
            finally {
                entry.done = true
                if (session !== owner || entry.rejected) entry.assets.forEach { it.file.delete() }
                else refresh(owner)
            }
        }
        return entry
    }
    fun accept(entry: Entry?) { entry?.accepted = true }
    fun reject(entry: Entry?) {
        entry ?: return
        entry.rejected = true; entry.job?.cancel(); entry.assets.forEach { it.file.delete() }
    }
    fun finish(terminal: ExportStatus) {
        val owner = session ?: run { Exports.status.value = terminal; return }
        owner.terminal = terminal
        AppLog.i("Export ended, comparisons still running: ${owner.entries.count { !it.done }}")
        refresh(owner)
    }
    private fun refresh(owner: Session) {
        if (session !== owner) return
        val terminal = owner.terminal ?: return
        val entries = owner.entries.filter { it.accepted && !it.rejected }
        Exports.status.value = terminal.copy(comparisons = entries.flatMap { it.assets },
            comparisonsBusy = entries.any { !it.done })
    }
}
