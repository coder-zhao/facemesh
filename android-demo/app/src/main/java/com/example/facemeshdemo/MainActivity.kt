package com.example.facemeshdemo

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.os.Bundle
import android.widget.SeekBar
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import com.example.facemeshdemo.databinding.ActivityMainBinding
import com.google.android.material.switchmaterial.SwitchMaterial
import com.google.mediapipe.framework.image.MediaImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker

class MainActivity : ComponentActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var faceLandmarker: FaceLandmarker
    private var meshScale = 1.0f
    private var stickerEnabled = true

    private val cameraExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    private val requestPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) startCamera() else finish()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val stickerBitmap = runCatching {
            assets.open("glasses.png").use { BitmapFactory.decodeStream(it) }
        }.getOrNull() ?: createFallbackSticker()
        binding.stickerOverlay.setStickerBitmap(stickerBitmap)

        setupControls(binding.seekScale, binding.labelScale, binding.switchSticker)
        setupFaceLandmarker()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            requestPermission.launch(Manifest.permission.CAMERA)
        }
    }

    private fun setupControls(seekBar: SeekBar, label: TextView, switchView: SwitchMaterial) {
        label.text = "Mesh缩放: ${"%.2f".format(meshScale)}x"
        seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                meshScale = (progress.coerceAtLeast(60)) / 100f
                label.text = "Mesh缩放: ${"%.2f".format(meshScale)}x"
            }

            override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
            override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
        })

        switchView.setOnCheckedChangeListener { _, isChecked ->
            stickerEnabled = isChecked
            if (!isChecked) binding.stickerOverlay.clearSticker()
        }
    }

    private fun setupFaceLandmarker() {
        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("face_landmarker.task").build())
            .setRunningMode(RunningMode.VIDEO)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        faceLandmarker = FaceLandmarker.createFromOptions(this, options)
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(binding.previewView.surfaceProvider)
            }

            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor) { imageProxy ->
                        val mediaImage = imageProxy.image
                        if (mediaImage == null) {
                            imageProxy.close()
                            return@setAnalyzer
                        }

                        val mpImage = MediaImageBuilder(mediaImage).build()
                        val imageProcessingOptions = ImageProcessingOptions.builder()
                            .setRotationDegrees(imageProxy.imageInfo.rotationDegrees)
                            .build()

                        val timestamp = imageProxy.imageInfo.timestamp / 1_000_000
                        val result = faceLandmarker.detectForVideo(mpImage, timestamp, imageProcessingOptions)

                        runOnUiThread {
                            if (!stickerEnabled || result.faceLandmarks().isEmpty()) {
                                binding.stickerOverlay.clearSticker()
                            } else {
                                renderSticker(result.faceLandmarks()[0])
                            }
                        }
                        imageProxy.close()
                    }
                }

            provider.unbindAll()
            provider.bindToLifecycle(this, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis)
        }, ContextCompat.getMainExecutor(this))
    }

    private fun renderSticker(landmarks: List<NormalizedLandmark>) {
        val requiredIndices = StickerOverlayView.REQUIRED_LANDMARKS
        val maxIndex = requiredIndices.maxOrNull() ?: return
        if (landmarks.size <= maxIndex) {
            binding.stickerOverlay.clearSticker()
            return
        }

        val width = binding.previewView.width.toFloat()
        val height = binding.previewView.height.toFloat()

        val points = mutableMapOf<Int, PointF>()
        requiredIndices.forEach { index ->
            val lm = landmarks[index]
            points[index] = PointF((1f - lm.x()) * width, lm.y() * height)
        }

        binding.stickerOverlay.updateStickerMesh(points, meshScale)
    }

    private fun createFallbackSticker(): Bitmap {
        val width = 500
        val height = 220
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(220, 40, 220, 255)
            style = Paint.Style.STROKE
            strokeWidth = 16f
        }
        canvas.drawCircle(130f, 95f, 75f, paint)
        canvas.drawCircle(370f, 95f, 75f, paint)
        canvas.drawLine(205f, 95f, 295f, 95f, paint)
        canvas.drawLine(55f, 95f, 0f, 90f, paint)
        canvas.drawLine(445f, 95f, 500f, 90f, paint)
        return bitmap
    }

    override fun onDestroy() {
        super.onDestroy()
        faceLandmarker.close()
        cameraExecutor.shutdown()
    }
}
