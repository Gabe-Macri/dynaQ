"""Unit tests for dynaQ Python backend and Rust bridge."""

import os
import sys
import threading
import time
import unittest

# Add python directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from dynaq import (
    DynaQBackendServer,
    DynaQClient,
    DynaQConnectionError,
    DynaQDSPError,
    DynaQError,
    DynaQOptimizationError,
    HARMAN_OVER_EAR,
    RustBridge,
    interpolate_curve,
)


class TestDynaQPythonBackend(unittest.TestCase):

    def test_rust_bridge_loaded(self):
        bridge = RustBridge.get()
        self.assertTrue(bridge.is_available, "Rust dylib must be found and loaded")
        version = bridge.version()
        self.assertIn("Rust SIMD Pro-DSP", version)

    def test_rust_autoeq_optimization(self):
        bridge = RustBridge.get()
        target = [(20.0, 5.0), (100.0, 4.0), (1000.0, 0.0), (3000.0, 6.0), (10000.0, -2.0)]
        measured = [(20.0, 0.0), (100.0, 1.0), (1000.0, 0.0), (3000.0, 1.0), (10000.0, -4.0)]

        bands, rmse = bridge.optimize_autoeq(target, measured, num_bands=6)
        self.assertEqual(len(bands), 6)
        self.assertLess(rmse, 4.0, "Optimization should converge to lower residual RMSE")

        # Verify bands are within valid pro audio bounds
        for b in bands:
            self.assertTrue(20.0 <= b.frequency_hz <= 20000.0)
            self.assertTrue(-18.0 <= b.gain_db <= 18.0)
            self.assertTrue(0.2 <= b.q <= 10.0)

    def test_rust_fir_generation(self):
        bridge = RustBridge.get()
        taps = bridge.generate_fir(cutoff_hz=2000.0, num_taps=31, fir_type=0, sample_rate=48000.0)
        self.assertEqual(len(taps), 31)
        # Center tap maximum
        center_idx = 15
        self.assertGreater(taps[center_idx], 0.0)

    def test_rust_true_peak_scanning(self):
        bridge = RustBridge.get()
        samples = [0.1] * 50
        samples[25] = 2.0  # +6.02 dBFS peak
        peak_db = bridge.scan_true_peak(samples)
        self.assertAlmostEqual(peak_db, 6.02, delta=0.2)

    def test_rust_phase_correlation(self):
        bridge = RustBridge.get()
        left = [0.5, -0.3, 0.8, -0.1]
        right = list(left)
        corr_in_phase = bridge.measure_phase_correlation(left, right)
        self.assertAlmostEqual(corr_in_phase, 1.0, delta=0.01)

        inverted = [-x for x in left]
        corr_out_phase = bridge.measure_phase_correlation(left, inverted)
        self.assertAlmostEqual(corr_out_phase, -1.0, delta=0.01)

    def test_curve_interpolation(self):
        curve = [(100.0, 0.0), (1000.0, 6.0)]
        val_at_100 = interpolate_curve(curve, 100.0)
        val_at_1000 = interpolate_curve(curve, 1000.0)
        self.assertAlmostEqual(val_at_100, 0.0)
        self.assertAlmostEqual(val_at_1000, 6.0)

    def test_client_server_ipc(self):
        test_sock = "/tmp/test_dynaq_ipc.sock"
        test_port = 9879

        server = DynaQBackendServer(socket_path=test_sock, tcp_port=test_port)
        server.start()

        # Let server bind
        time.sleep(0.1)

        try:
            client = DynaQClient(socket_path=test_sock, tcp_port=test_port)
            client.connect()

            # 1. Ping
            self.assertTrue(client.ping())

            # 2. Get status
            status = client.get_status()
            self.assertEqual(status.get("status"), "online")
            self.assertEqual(status.get("sample_rate"), 48000.0)

            # 3. Set band
            ok = client.set_band(index=2, frequency=440.0, gain=3.5, q=2.0)
            self.assertTrue(ok)
            updated_status = client.get_status()
            band2 = updated_status["bands"][2]
            self.assertEqual(band2["frequency"], 440.0)
            self.assertEqual(band2["gain"], 3.5)

            # 4. Set master gain
            ok_gain = client.set_master_gain(-2.5)
            self.assertTrue(ok_gain)
            self.assertEqual(client.get_status()["master_gain_db"], -2.5)

            # 5. Set limiter
            ok_lim = client.set_limiter(ceiling_db=-1.0, is_enabled=True)
            self.assertTrue(ok_lim)
            self.assertEqual(client.get_status()["limiter"]["ceiling_db"], -1.0)

            # 6. Telemetry
            telemetry = client.get_telemetry()
            self.assertIn("peak_left_db", telemetry)
            self.assertIn("spectrum_64", telemetry)

            client.close()
        finally:
            server.stop()

    def test_error_classes(self):
        e1 = DynaQConnectionError("offline")
        e2 = DynaQDSPError("unstable poles")
        e3 = DynaQOptimizationError("did not converge")

        self.assertIn("DYNAQ_ERR_101", str(e1))
        self.assertIn("DYNAQ_ERR_201", str(e2))
        self.assertIn("DYNAQ_ERR_301", str(e3))


if __name__ == "__main__":
    unittest.main()

