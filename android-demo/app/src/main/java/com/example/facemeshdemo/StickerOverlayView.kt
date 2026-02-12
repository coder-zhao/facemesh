package com.example.facemeshdemo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs

class StickerOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    companion object {
        val REQUIRED_LANDMARKS = setOf(33, 263, 168, 133, 362, 105, 334, 127, 356)
    }

    private data class MeshVertex(
        val landmarkIndex: Int,
        val sx: Float,
        val sy: Float
    )

    private val meshVertices = listOf(
        MeshVertex(33, 0.26f, 0.42f),
        MeshVertex(263, 0.74f, 0.42f),
        MeshVertex(168, 0.50f, 0.60f),
        MeshVertex(133, 0.34f, 0.44f),
        MeshVertex(362, 0.66f, 0.44f),
        MeshVertex(105, 0.30f, 0.30f),
        MeshVertex(334, 0.70f, 0.30f),
        MeshVertex(127, 0.10f, 0.44f),
        MeshVertex(356, 0.90f, 0.44f)
    )

    private val meshTriangles = listOf(
        intArrayOf(33, 133, 105),
        intArrayOf(133, 168, 105),
        intArrayOf(263, 362, 334),
        intArrayOf(362, 168, 334),
        intArrayOf(33, 168, 133),
        intArrayOf(263, 168, 362),
        intArrayOf(33, 127, 168),
        intArrayOf(263, 356, 168),
        intArrayOf(33, 263, 168)
    )

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val drawMatrix = Matrix()
    private val clipPath = Path()

    private var sticker: Bitmap? = null
    private var meshScale = 1f
    private var landmarkPoints: Map<Int, PointF> = emptyMap()
    private var visible = false

    fun setStickerBitmap(bitmap: Bitmap?) {
        sticker = bitmap
        invalidate()
    }

    fun clearSticker() {
        visible = false
        invalidate()
    }

    fun updateStickerMesh(
        landmarkPoints: Map<Int, PointF>,
        meshScale: Float
    ) {
        this.landmarkPoints = landmarkPoints
        this.meshScale = meshScale
        visible = true
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!visible) return
        val bmp = sticker ?: return
        if (landmarkPoints.keys.containsAll(REQUIRED_LANDMARKS).not()) return

        val center = centerPoint() ?: return

        val srcPoints = meshVertices.associate { v ->
            v.landmarkIndex to PointF(v.sx * bmp.width, v.sy * bmp.height)
        }
        val dstPoints = meshVertices.associate { v ->
            val p = landmarkPoints[v.landmarkIndex]!!
            v.landmarkIndex to scaleAroundCenter(p, center, meshScale)
        }

        meshTriangles.forEach { tri ->
            val s1 = srcPoints[tri[0]] ?: return@forEach
            val s2 = srcPoints[tri[1]] ?: return@forEach
            val s3 = srcPoints[tri[2]] ?: return@forEach
            val t1 = dstPoints[tri[0]] ?: return@forEach
            val t2 = dstPoints[tri[1]] ?: return@forEach
            val t3 = dstPoints[tri[2]] ?: return@forEach

            val dst = floatArrayOf(t1.x, t1.y, t2.x, t2.y, t3.x, t3.y)
            if (triangleArea(dst) < 1f) return@forEach

            val src = floatArrayOf(s1.x, s1.y, s2.x, s2.y, s3.x, s3.y)
            drawMatrix.reset()
            drawMatrix.setPolyToPoly(src, 0, dst, 0, 3)

            val saveId = canvas.save()
            clipPath.reset()
            clipPath.moveTo(t1.x, t1.y)
            clipPath.lineTo(t2.x, t2.y)
            clipPath.lineTo(t3.x, t3.y)
            clipPath.close()
            canvas.clipPath(clipPath)
            canvas.drawBitmap(bmp, drawMatrix, paint)
            canvas.restoreToCount(saveId)
        }
    }

    private fun centerPoint(): PointF? {
        val anchorKeys = listOf(33, 263, 168)
        val pts = anchorKeys.mapNotNull { landmarkPoints[it] }
        if (pts.size != anchorKeys.size) return null
        return PointF(
            pts.sumOf { it.x.toDouble() }.toFloat() / pts.size,
            pts.sumOf { it.y.toDouble() }.toFloat() / pts.size
        )
    }

    private fun scaleAroundCenter(point: PointF, center: PointF, scale: Float): PointF {
        return PointF(
            center.x + (point.x - center.x) * scale,
            center.y + (point.y - center.y) * scale
        )
    }

    private fun triangleArea(pts: FloatArray): Float {
        val x1 = pts[0]
        val y1 = pts[1]
        val x2 = pts[2]
        val y2 = pts[3]
        val x3 = pts[4]
        val y3 = pts[5]
        return abs((x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2)) * 0.5f)
    }
}
