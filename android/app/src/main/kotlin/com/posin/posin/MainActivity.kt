package com.posin.posin

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "posin/printer"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBondedDevices" -> getBondedDevices(result)
                    "connect" -> connect(call.argument<String>("address"), result)
                    "writeBytes" -> writeBytes(call.argument<ByteArray>("bytes"), result)
                    "isConnected" -> result.success(socket?.isConnected == true)
                    "disconnect" -> { closeQuietly(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun adapter(): BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    private fun getBondedDevices(result: MethodChannel.Result) {
        try {
            val a = adapter()
            if (a == null || !a.isEnabled) {
                result.success(emptyList<Map<String, String>>())
                return
            }
            val list = a.bondedDevices.map { d ->
                mapOf("name" to (d.name ?: ""), "address" to d.address)
            }
            result.success(list)
        } catch (e: Exception) {
            result.error("BONDED_ERR", e.message, null)
        }
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        if (address.isNullOrEmpty()) {
            result.success(mapOf("connected" to false, "error" to "Alamat printer kosong"))
            return
        }
        Thread {
            try {
                val a = adapter()
                if (a == null || !a.isEnabled) {
                    reply(result, mapOf("connected" to false, "error" to "Bluetooth tidak aktif. Nyalakan Bluetooth HP."))
                    return@Thread
                }
                try { a.cancelDiscovery() } catch (_: Exception) {}

                // Tutup koneksi lama yang mungkin masih nyangkut
                closeQuietly()

                val device = a.getRemoteDevice(address)
                val s = openSocketWithFallback(device)
                if (s == null) {
                    reply(result, mapOf("connected" to false, "error" to "Gagal terhubung ke printer. Pastikan printer menyala dan tidak sedang dipakai aplikasi lain."))
                    return@Thread
                }
                socket = s
                outputStream = s.outputStream
                reply(result, mapOf("connected" to true, "error" to null))
            } catch (e: Exception) {
                closeQuietly()
                reply(result, mapOf("connected" to false, "error" to (e.message ?: "Gagal konek ke printer")))
            }
        }.start()
    }

    /**
     * Buka RFCOMM socket dengan 3 tingkat fallback. Banyak firmware Bluetooth
     * (mis. MIUI/Redmi) menolak socket "secure" dengan error
     * "read failed, socket might closed", tapi berhasil lewat socket "insecure"
     * atau lewat reflection createRfcommSocket(channel 1).
     */
    private fun openSocketWithFallback(device: BluetoothDevice): BluetoothSocket? {
        // 1. Secure RFCOMM (cara standar, jalan di kebanyakan device)
        try {
            val s = device.createRfcommSocketToServiceRecord(sppUuid)
            s.connect()
            if (s.isConnected) return s
            closeSocket(s)
        } catch (_: Exception) {}

        // 2. Insecure RFCOMM (tanpa auth/enkripsi — lebih kompatibel)
        try {
            val s = device.createInsecureRfcommSocketToServiceRecord(sppUuid)
            s.connect()
            if (s.isConnected) return s
            closeSocket(s)
        } catch (_: Exception) {}

        // 3. Reflection createRfcommSocket(1) — workaround device bandel
        try {
            val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
            val s = m.invoke(device, 1) as BluetoothSocket
            s.connect()
            if (s.isConnected) return s
            closeSocket(s)
        } catch (_: Exception) {}

        return null
    }

    private fun writeBytes(bytes: ByteArray?, result: MethodChannel.Result) {
        Thread {
            try {
                val os = outputStream
                if (os == null || socket?.isConnected != true) {
                    reply(result, mapOf("ok" to false, "error" to "Printer tidak terhubung"))
                    return@Thread
                }
                if (bytes == null) {
                    reply(result, mapOf("ok" to false, "error" to "Data cetak kosong"))
                    return@Thread
                }
                os.write(bytes)
                os.flush()
                reply(result, mapOf("ok" to true, "error" to null))
            } catch (e: Exception) {
                reply(result, mapOf("ok" to false, "error" to (e.message ?: "Gagal mengirim data ke printer")))
            }
        }.start()
    }

    private fun closeQuietly() {
        try { outputStream?.flush() } catch (_: Exception) {}
        try { outputStream?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        outputStream = null
        socket = null
    }

    private fun closeSocket(s: BluetoothSocket) {
        try { s.close() } catch (_: Exception) {}
    }

    private fun reply(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }
}
