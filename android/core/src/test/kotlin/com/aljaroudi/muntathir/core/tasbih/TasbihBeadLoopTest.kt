package com.aljaroudi.muntathir.core.tasbih

import kotlin.math.hypot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TasbihBeadLoopTest {
    private fun assertPoint(
        expected: BeadPoint,
        actual: BeadPoint,
    ) {
        assertEquals(expected.x, actual.x, 1e-4f)
        assertEquals(expected.y, actual.y, 1e-4f)
        assertEquals(expected.z, actual.z, 1e-4f)
    }

    @Test
    fun theNearStrandDescendsAndTheRearStrandRises() {
        // Top of the near strand, turned toward the camera on the right.
        assertPoint(BeadPoint(0.21f, 0.95f, 0.36373f), TasbihBeadLoop.position(0f))
        assertPoint(TasbihBeadLoop.position(0f), TasbihBeadLoop.position(1f))
        assertPoint(TasbihBeadLoop.position(0.25f), TasbihBeadLoop.position(-0.75f))
        // Halfway round is the bottom of the rear strand.
        assertPoint(BeadPoint(-0.21f, -0.95f, -0.36373f), TasbihBeadLoop.position(0.5f))
        val front = TasbihBeadLoop.bead(2, 0f)
        val pulled = TasbihBeadLoop.bead(2, 0.5f)
        assertTrue(pulled.y < front.y)
        val rear = TasbihBeadLoop.bead(20, 0f)
        assertTrue(TasbihBeadLoop.bead(20, 0.5f).y > rear.y)
    }

    @Test
    fun beadsAreEvenlySpacedAndOneAdvanceMovesEachToTheNext() {
        val spacing = TasbihBeadLoop.PERIMETER / TasbihBeadLoop.BEAD_COUNT
        assertTrue(spacing > 2 * TasbihBeadLoop.BEAD_RADIUS)
        for (index in 0 until TasbihBeadLoop.BEAD_COUNT) {
            assertPoint(TasbihBeadLoop.bead(index + 1, 0f), TasbihBeadLoop.bead(index, 1f))
            // Straight neighbours sit one spacing apart (arcs a little less, as chords).
            val a = TasbihBeadLoop.bead(index, 0f)
            val b = TasbihBeadLoop.bead(index + 1, 0f)
            val gap = hypot(hypot(a.x - b.x, a.y - b.y), a.z - b.z)
            assertTrue(gap <= spacing + 1e-4f && gap > spacing * 0.9f)
        }
    }

    @Test
    fun layersCrossfadeWithOneCopyAlwaysOpaque() {
        assertEquals(1f, TasbihBeadLoop.opacity(0.36f, front = true))
        assertEquals(0f, TasbihBeadLoop.opacity(0.36f, front = false))
        assertEquals(1f, TasbihBeadLoop.opacity(-0.36f, front = false))
        assertEquals(0f, TasbihBeadLoop.opacity(-0.36f, front = true))
        for (step in -12..12) {
            val z = step / 100f
            val front = TasbihBeadLoop.opacity(z, front = true)
            val rear = TasbihBeadLoop.opacity(z, front = false)
            assertTrue(maxOf(front, rear) == 1f)
        }
        assertEquals(1f, TasbihBeadLoop.opacity(0f, front = true))
        assertEquals(1f, TasbihBeadLoop.opacity(0f, front = false))
    }
}
