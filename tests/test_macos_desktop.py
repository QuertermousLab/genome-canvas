import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAC_APP = ROOT / "macos" / "GenomeCanvasDesktop"


class MacOSDesktopClientTests(unittest.TestCase):
    def test_info_plist_allows_http_only_for_web_content(self):
        with (MAC_APP / "Resources" / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleIdentifier"], "org.genomecanvas.desktop")
        self.assertEqual(info["CFBundleShortVersionString"], "1.3.1")
        self.assertEqual(info["LSMinimumSystemVersion"], "13.0")
        self.assertTrue(info["NSAppTransportSecurity"]["NSAllowsArbitraryLoadsInWebContent"])
        self.assertNotIn("NSAllowsArbitraryLoads", info["NSAppTransportSecurity"])

    def test_client_uses_persistent_webkit_and_native_file_panels(self):
        source = (MAC_APP / "Sources" / "main.m").read_text(encoding="utf-8")
        self.assertIn("http://127.0.0.1:8000/", source)
        self.assertIn("[WKWebsiteDataStore defaultDataStore]", source)
        self.assertIn("WKDownloadDelegate", source)
        self.assertIn("[NSSavePanel savePanel]", source)
        self.assertIn("[NSOpenPanel openPanel]", source)

    def test_client_uses_native_workbench_controls_and_desktop_bridge(self):
        source = (MAC_APP / "Sources" / "main.m").read_text(encoding="utf-8")
        web_app = (ROOT / "app.js").read_text(encoding="utf-8")
        styles = (ROOT / "styles.css").read_text(encoding="utf-8")
        self.assertIn("WKScriptMessageHandler", source)
        self.assertIn("NSTableViewDataSource", source)
        self.assertIn('name:@"genomeCanvas"', source)
        self.assertIn('callDesktopMethod:@"moveTrack"', source)
        self.assertIn("window.GenomeCanvasDesktop", web_app)
        self.assertIn("desktopStateSnapshot", web_app)
        self.assertIn("desktop-embedded .track-rail", styles)
        self.assertIn("desktop-embedded .browser-toolbar", styles)
        self.assertNotIn("swatch.tag =", source)
        self.assertIn('swatch.identifier = @"TrackSwatch"', source)
        self.assertNotIn("NSWindowStyleMaskFullSizeContentView", source)
        self.assertIn('action:@selector(createWorkspace:)', source)
        self.assertIn('action:@selector(deleteWorkspace:)', source)

    def test_build_script_targets_supported_mac_architectures(self):
        script = (MAC_APP / "build.sh").read_text(encoding="utf-8")
        self.assertIn("arm64|x86_64", script)
        self.assertIn("-mmacosx-version-min=13.0", script)
        self.assertIn("xcrun --sdk macosx clang", script)
        self.assertIn("codesign --force --deep --sign -", script)
        self.assertIn("Resources/GenomeCanvas-1024.png", script)
        self.assertNotIn("favicon.svg", script)
        self.assertTrue((MAC_APP / "Resources" / "GenomeCanvas-1024.png").is_file())


if __name__ == "__main__":
    unittest.main()
