package com.aljaroudi.muntathir.feed

import com.aljaroudi.muntathir.core.feed.FeedClient
import com.aljaroudi.muntathir.core.feed.FeedException
import com.aljaroudi.muntathir.core.feed.FeedResponse
import com.aljaroudi.muntathir.core.feed.FeedTransport
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.header
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.HttpHeaders
import io.ktor.utils.io.readRemaining
import kotlinx.io.readByteArray

/** The corrections feed over HTTPS: 20 s timeout, conditional GET, body capped at [FeedClient.MAX_BYTES]. */
class KtorFeedTransport(
    private val client: HttpClient = defaultClient(),
) : FeedTransport {
    override suspend fun get(
        url: String,
        ifNoneMatch: String?,
    ): FeedResponse =
        client
            .prepareGet(url) {
                if (ifNoneMatch != null) header(HttpHeaders.IfNoneMatch, ifNoneMatch)
            }.execute { response ->
                val length = response.headers[HttpHeaders.ContentLength]?.toLongOrNull()
                if (length != null && length > FeedClient.MAX_BYTES) throw FeedException("Feed too large")
                // Reads one byte past the limit so FeedClient can reject oversized bodies without buffering them all.
                val body = response.bodyAsChannel().readRemaining(FeedClient.MAX_BYTES + 1L).readByteArray()
                FeedResponse(
                    status = response.status.value,
                    body = body,
                    etag = response.headers[HttpHeaders.ETag],
                    finalUrl = response.call.request.url.toString(),
                )
            }

    companion object {
        fun defaultClient() =
            HttpClient(OkHttp) {
                expectSuccess = false
                install(HttpTimeout) { requestTimeoutMillis = 20_000 }
            }
    }
}
