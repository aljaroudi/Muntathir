package com.aljaroudi.muntathir.core.feed

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlin.io.encoding.Base64

/** One HTTP GET. The app implements this with Ktor (20 s timeout); tests use fakes. */
fun interface FeedTransport {
    suspend fun get(
        url: String,
        ifNoneMatch: String?,
    ): FeedResponse
}

class FeedResponse(
    val status: Int,
    val body: ByteArray,
    val etag: String? = null,
    /** The URL after redirects; must stay https. */
    val finalUrl: String,
)

class FeedException(
    message: String,
) : Exception(message)

/**
 * Fetches the corrections feed with ETag revalidation and a last-good cache. Port of Swift `FeedClient`:
 * failures fall back to the last good feed, and concurrent refreshes share one request.
 */
class FeedClient(
    private val url: String,
    private val cacheFile: File,
    private val transport: FeedTransport,
) {
    @Serializable
    private class Cache(
        val etag: String?,
        /** Base64, matching Swift `Data` coding. */
        val payload: String,
    )

    private val mutex = Mutex()
    private var running: CompletableDeferred<CorrectionsFeed>? = null

    fun cachedFeed(): CorrectionsFeed? =
        readCache()?.let { runCatching { CorrectionsFeed.decode(it.second) }.getOrNull() }

    suspend fun refresh(): CorrectionsFeed {
        val (task, owner) =
            mutex.withLock {
                running?.let { it to false }
                    ?: CompletableDeferred<CorrectionsFeed>().also { running = it }.let { it to true }
            }
        if (owner) {
            try {
                task.complete(fetch())
            } catch (error: Throwable) {
                task.completeExceptionally(error)
            } finally {
                mutex.withLock { running = null }
            }
        }
        return task.await()
    }

    private suspend fun fetch(): CorrectionsFeed {
        val cached = readCache()
        val lastGood = cached?.let { runCatching { CorrectionsFeed.decode(it.second) }.getOrNull() }
        return try {
            if (!url.startsWith("https://")) throw FeedException("Insecure feed URL")
            val response = transport.get(url, if (lastGood != null) cached.first else null)
            if (!response.finalUrl.startsWith("https://")) throw FeedException("Insecure redirect")
            if (response.status == 304 && lastGood != null) return lastGood
            if (response.status != 200 || response.body.size > MAX_BYTES) throw FeedException("HTTP ${response.status}")
            val text = response.body.decodeToString()
            val feed = CorrectionsFeed.decode(text)
            writeCache(Cache(response.etag, Base64.encode(response.body)))
            feed
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastGood ?: throw error
        }
    }

    private fun readCache(): Pair<String?, String>? =
        runCatching {
            val cache = json.decodeFromString<Cache>(cacheFile.readText())
            cache.etag to Base64.decode(cache.payload).decodeToString()
        }.getOrNull()

    private fun writeCache(cache: Cache) {
        cacheFile.parentFile?.mkdirs()
        val temporary = File(cacheFile.parentFile, "${cacheFile.name}.tmp")
        temporary.writeText(json.encodeToString(cache))
        Files.move(
            temporary.toPath(),
            cacheFile.toPath(),
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.ATOMIC_MOVE,
        )
    }

    companion object {
        /** `منتظر.com` in punycode. */
        const val PRODUCTION_URL = "https://xn--pgbou4cf.com/calendar/corrections-v1.json"
        const val MAX_BYTES = 5_000_000
        private val json = Json { ignoreUnknownKeys = true }
    }
}
