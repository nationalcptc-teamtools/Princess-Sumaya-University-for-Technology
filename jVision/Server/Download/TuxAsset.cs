using System;
using System.IO;

namespace jVision.Server.Download
{
    // Loads Server/Assets/tux.png once at first use, base64-encodes it, and
    // caches the resulting data-URL so every SVG render can inline the same
    // string without re-reading the file. Both TopologyRenderer.LinuxMonitor
    // and AttackPathRenderer.TuxIcon use this so the two views share the same
    // Linux logo.
    internal static class TuxAsset
    {
        private static readonly Lazy<string> _dataUrl = new Lazy<string>(Load);
        public static string DataUrl => _dataUrl.Value;

        private static string Load()
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "tux.png");
            if (!File.Exists(path)) return "";
            var bytes = File.ReadAllBytes(path);
            return "data:image/png;base64," + Convert.ToBase64String(bytes);
        }
    }
}
