package com.aljaroudi.muntathir.search

import com.aljaroudi.muntathir.core.search.SemanticSearchTransport
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType

/** Swift `SemanticSearchClient.request`: JSON POST, 15 s timeout, `Muntathir/1.0` user agent. */
class KtorSemanticSearchTransport(
    private val client: HttpClient =
        HttpClient(OkHttp) {
            expectSuccess = false
            install(HttpTimeout) { requestTimeoutMillis = 15_000 }
        },
) : SemanticSearchTransport {
    override suspend fun post(
        url: String,
        body: String,
    ): Pair<Int, String> {
        val response =
            client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.UserAgent, "Muntathir/1.0")
                setBody(body)
            }
        return response.status.value to response.bodyAsText()
    }
}
