using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using jVision.Server.Models;

namespace jVision.Server.Download
{
    // Network topology renderer — CPTC-style category grouping:
    //
    //   +--------------------------+
    //   |     Attacker Network     |   dashed box, hooded-figure monitor
    //   +--------------------------+
    //              |  ↓
    //          [ ROUTER ]             clean cyan cylinder
    //              |  ↓
    //   +-------- CPTC Network -----------------+
    //   | [Active Directory]  [Web Environment] |
    //   | [OT Systems]        [AI Systems]      |
    //   | [Mobile]            [Cloud]           |
    //   +---------------------------------------+
    //
    //  Each host shows an OS-specific icon (Linux Tux / Windows flag / cloud
    //  silhouette) and the IP + short domain label. Hosts are grouped by
    //  Box.Category (web / AD / OT / AI / mobile / cloud). Uncategorized
    //  hosts land in an "Other" bucket.
    //
    // Mapping from jVision data:
    //   Box.Category -> sub-environment label (grouped)
    //   Box.Ip       -> bold label under each device
    //   Box.Domain   -> short chip under the IP
    //   Box.Os/Box.Hostname -> icon selector
    public static class TopologyRenderer
    {
        // ---- Layout constants ----
        private const int CanvasMinW = 1280;
        private const int OuterPadX = 45;

        private const int AttackerW = 200, AttackerH = 180;
        private const int AttackerTopY = 30;

        private const int RouterW = 100, RouterH = 58;
        private const int RouterTopY = 280;

        // Outer "engagement network" frame — reintroduced to match the CPTC
        // reference diagram where every category box lives inside a labelled
        // dashed container ("All Ports Tours Network").
        private const int OuterFrameTopY = 400;
        private const int OuterFramePad = 22;
        private const string OuterFrameLabel = "BFF Network";

        // Category / sub-environment box — width sized so a 3-column grid
        // of cells still leaves each cell wide enough to fit a full FQDN
        // like "navigation.allports.tours" without clipping even at the
        // slightly larger label font size used below.
        private const int SubBoxMinW = 660;
        private const int SubBoxHeaderH = 32;
        private const int SubBoxPadX = 22, SubBoxPadY = 16;

        // Device cell (icon + IP label + optional domain chip)
        private const int IconW = 52, IconH = 45;
        private const int CellW = 180, CellH = 112;
        private const int DevPerRow = 3;

        private const int SubGapX = 30, SubGapY = 24;
        private const int SubCols = 2;                     // 2 category columns (matches reference)

        // Vertical spacing between pivot-arrow lanes in the channel below the
        // subnet row. Must clear the pill-label height (~24px) with headroom.
        private const int PivotLaneSpacing = 32;
        private const int PivotCornerRadius = 8;
        private const int PivotChannelGap = 30;            // gap from bottom of subnet row to first lane

        // ==================== data grouping ====================

        private static Version TryParseIp(string ip) =>
            Version.TryParse(ip ?? "", out var v) ? v : new Version(0, 0, 0, 0);

        // Fixed display order + long-form labels for the CPTC category buckets.
        // Anything that doesn't match a known category (case-insensitive) is
        // treated as "Other" and rendered last, so operator-set free-text
        // values still surface instead of being dropped.
        private static readonly (string Key, string Label)[] _categoryOrder =
        {
            ("AD",     "Active Directory Environment"),
            ("Web",    "Web Environment"),
            ("OT",     "OT Systems"),
            ("AI",     "AI Systems"),
            ("Mobile", "Mobile Environment"),
            ("Cloud",  "Cloud Environment"),
        };

        private static string NormalizeCategoryKey(string raw)
        {
            var t = (raw ?? "").Trim();
            if (t.Length == 0) return "Other";
            // Fold common aliases into canonical keys so a "web", "WEB",
            // "web-app", "active directory" all end up in the same bucket.
            var low = t.ToLowerInvariant();
            if (low.Contains("active directory") || low == "ad") return "AD";
            if (low.Contains("web"))                             return "Web";
            if (low.Contains("ot"))                              return "OT";
            if (low.Contains("ai"))                              return "AI";
            if (low.Contains("mobile"))                          return "Mobile";
            if (low.Contains("cloud"))                           return "Cloud";
            return t;   // unknown — display as-is
        }

        private static string CategoryLabel(string key)
        {
            foreach (var (k, label) in _categoryOrder)
                if (string.Equals(k, key, StringComparison.OrdinalIgnoreCase)) return label;
            return key;
        }

        private static int CategoryOrderIndex(string key)
        {
            for (int i = 0; i < _categoryOrder.Length; i++)
                if (string.Equals(_categoryOrder[i].Key, key, StringComparison.OrdinalIgnoreCase)) return i;
            return int.MaxValue;   // unknown categories sort after all known ones
        }

        private static List<(string Category, List<Box> Hosts)> GroupByCategory(List<Box> boxes)
        {
            return boxes
                .GroupBy(b => NormalizeCategoryKey(b.Category))
                .OrderBy(g => CategoryOrderIndex(g.Key))
                .ThenBy(g => g.Key, StringComparer.OrdinalIgnoreCase)
                .Select(g => (CategoryLabel(g.Key), g.OrderBy(b => TryParseIp(b.Ip)).ToList()))
                .ToList();
        }

        // OS detection: check the Os field, then fall back to hostname keywords
        // so machines the scanner couldn't fingerprint but that carry a
        // descriptive name (dc01, ubuntu-jump, kali-attacker) still get the
        // right icon.
        private static readonly string[] _winKeywords = { "windows", "microsoft" };
        private static readonly string[] _linuxKeywords = {
            "linux", "ubuntu", "debian", "centos", "rhel", "redhat",
            "kali", "arch", "fedora", "suse", "alpine", "unix"
        };

        private static bool IsWindows(Box b)
        {
            var os = (b.Os ?? "").ToLowerInvariant();
            var hn = (b.Hostname ?? "").ToLowerInvariant();
            if (_winKeywords.Any(k => os.Contains(k))) return true;
            if (_winKeywords.Any(k => hn.Contains(k))) return true;
            // Linux keywords in the hostname take precedence over the
            // ambiguous short prefix "win" (avoids classifying "win-ubuntu-jump"
            // as Windows).
            if (_linuxKeywords.Any(k => hn.Contains(k))) return false;
            // Common short forms only if not clearly Linux.
            if (hn.StartsWith("win") || hn.Contains("-win") || hn.Contains(" win")) return true;
            if (hn.StartsWith("dc") || hn.Contains("exchange") || hn.Contains("srv-win")) return true;
            return false;
        }

        // Hosted-cloud endpoints (S3 buckets, AWS/Azure/GCP surface, anything
        // tagged as "cloud.*" in the domain) get the cloud icon so the eye
        // picks them out from the on-prem Linux/Windows hosts.
        private static readonly string[] _cloudKeywords = { "cloud", "aws", "azure", "gcp", "s3" };

        private static bool IsCloud(Box b)
        {
            var hn = (b.Hostname ?? "").ToLowerInvariant();
            var dm = (b.Domain ?? "").ToLowerInvariant();
            return _cloudKeywords.Any(k => hn.Contains(k) || dm.Contains(k));
        }

        // Mobile hosts get a phone silhouette regardless of underlying OS so
        // the diagram reads at a glance ("this row is the mobile fleet").
        // Category is authoritative here — no keyword fallback, since a
        // "mobile-api" hostname might live in the Web bucket for a shop app.
        private static bool IsMobile(Box b) =>
            string.Equals(NormalizeCategoryKey(b.Category), "Mobile", StringComparison.OrdinalIgnoreCase);

        // ==================== layout math ====================

        private static int RowsInSub(int hostCount) =>
            Math.Max(1, (hostCount + DevPerRow - 1) / DevPerRow);

        private static int SubBoxH(int hostCount) =>
            SubBoxHeaderH + SubBoxPadY + RowsInSub(hostCount) * CellH + 10;

        private class Layout
        {
            public int CanvasW;
            public int CanvasH;
            public int AttackerX;                // top-left of attacker block
            public int RouterX;                  // top-left of router block
            public int OuterFrameX;
            public int OuterFrameY;
            public int OuterFrameW;
            public int OuterFrameH;
            public List<(int X, int Y, int W, int H)> SubBoxes = new();  // absolute rects
        }

        private static Layout Compute(List<(string Category, List<Box> Hosts)> grouped)
        {
            var l = new Layout();

            // Outer frame width: uniform sub-box width * effective column
            // count + gaps + padding. Effective columns adapt to the actual
            // group count so a lone category ends up centered under the
            // router instead of parked in the leftmost slot of a 2-wide grid.
            int subBoxW = SubBoxMinW;
            int effectiveCols = Math.Max(1, Math.Min(SubCols, Math.Max(1, grouped.Count)));
            int innerW = subBoxW * effectiveCols + SubGapX * (effectiveCols - 1);
            l.OuterFrameW = innerW + 2 * OuterFramePad;
            l.CanvasW = Math.Max(CanvasMinW, l.OuterFrameW + 2 * OuterPadX);

            // Fixed elements
            l.OuterFrameX = (l.CanvasW - l.OuterFrameW) / 2;
            l.OuterFrameY = OuterFrameTopY;
            l.AttackerX = (l.CanvasW - AttackerW) / 2;
            l.RouterX   = (l.CanvasW - RouterW) / 2;

            // Grid-place the sub-boxes inside the outer frame. Each row is
            // centered independently so a trailing partial row still sits
            // under the router.
            int contentY = l.OuterFrameY + OuterFramePad;
            int yCursor = contentY;

            for (int rowStart = 0; rowStart < grouped.Count; rowStart += SubCols)
            {
                int rowCount = Math.Min(SubCols, grouped.Count - rowStart);
                int rowW = subBoxW * rowCount + SubGapX * (rowCount - 1);
                int rowStartX = (l.CanvasW - rowW) / 2;
                int rowH = 0;
                for (int c = 0; c < rowCount; c++)
                {
                    int idx = rowStart + c;
                    int h = SubBoxH(grouped[idx].Hosts.Count);
                    int x = rowStartX + c * (subBoxW + SubGapX);
                    l.SubBoxes.Add((x, yCursor, subBoxW, h));
                    rowH = Math.Max(rowH, h);
                }
                yCursor += rowH + SubGapY;
            }
            if (grouped.Count > 0) yCursor -= SubGapY;
            int totalContentH = Math.Max(0, yCursor - contentY);

            l.OuterFrameH = Math.Max(200, totalContentH + 2 * OuterFramePad);
            l.CanvasH = l.OuterFrameY + l.OuterFrameH + 20;
            return l;
        }

        // ==================== SVG entry point ====================

        public static byte[] RenderSvg(List<Box> boxes) => RenderSvg(boxes, null);

        public static byte[] RenderSvg(List<Box> boxes, List<jVision.Shared.Models.PivotEdge> pivotEdges)
        {
            var grouped = GroupByCategory(boxes);
            var layout = Compute(grouped);

            // Pivot arrows route through a horizontal channel below the subnet
            // row. Reserve one lane per edge so parallel arrows never overlap,
            // and grow the canvas to fit them + their pill labels.
            int pivotCount = pivotEdges?.Count(e => e != null && !string.IsNullOrEmpty(e.SourceIp)
                                                    && !string.IsNullOrEmpty(e.TargetIp)
                                                    && !string.Equals(e.SourceIp, e.TargetIp, StringComparison.OrdinalIgnoreCase)) ?? 0;
            if (pivotCount > 0)
            {
                layout.CanvasH += 30 + pivotCount * PivotLaneSpacing + 20;
            }

            var sb = new StringBuilder();
            sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n");
            sb.Append($"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{layout.CanvasW}\" height=\"{layout.CanvasH}\" viewBox=\"0 0 {layout.CanvasW} {layout.CanvasH}\" font-family=\"Arial, Helvetica, sans-serif\">\n");
            sb.Append(Defs());
            sb.Append($"<rect width=\"{layout.CanvasW}\" height=\"{layout.CanvasH}\" fill=\"#ffffff\"/>\n");

            // Attacker Network
            sb.Append(AttackerBlock(layout.AttackerX, AttackerTopY));

            // Arrow attacker -> router (arrowhead at router end, centred)
            sb.Append(DownArrow(layout.CanvasW / 2, AttackerTopY + AttackerH + 10, RouterTopY - 8));

            // Router — clean cylinder, no coloured diagonal shapes, no subnet label
            sb.Append(CiscoRouter(layout.RouterX, RouterTopY));

            // Arrow router -> engagement frame
            sb.Append(DownArrow(layout.CanvasW / 2, RouterTopY + RouterH + 20, layout.OuterFrameY - 8));

            // Outer "BFF Network" frame that wraps every category box.
            sb.Append(EngagementFrame(layout.OuterFrameX, layout.OuterFrameY,
                                      layout.OuterFrameW, layout.OuterFrameH,
                                      OuterFrameLabel));

            // Category sub-environments. Record each host's on-canvas centre
            // plus the sub-box its icon lives in so the pivot-edge overlay
            // can route arrows around category frames instead of straight
            // through them.
            var hostCentres = new Dictionary<string, (int Cx, int Cy)>(StringComparer.OrdinalIgnoreCase);
            var hostSubBox  = new Dictionary<string, (int X, int Y, int W, int H)>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < grouped.Count; i++)
            {
                var (category, hosts) = grouped[i];
                var (x, y, w, h) = layout.SubBoxes[i];
                sb.Append(SubEnvBox(x, y, w, h, category, hosts, hostCentres));
                foreach (var host in hosts)
                {
                    if (!string.IsNullOrEmpty(host.Ip))
                        hostSubBox[host.Ip] = (x, y, w, h);
                }
            }

            // Attack-path arrows: only render pivots whose endpoints we actually
            // know the coordinates for (both endpoints must be tracked hosts).
            if (pivotEdges != null && pivotEdges.Count > 0)
            {
                sb.Append(PivotEdgesOverlay(pivotEdges, hostCentres, hostSubBox,
                                            layout.OuterFrameY + layout.OuterFrameH));
            }

            // Empty state
            if (grouped.Count == 0)
            {
                sb.Append($"<text x=\"{layout.CanvasW / 2}\" y=\"{layout.OuterFrameY + 80}\" text-anchor=\"middle\" font-size=\"14\" fill=\"#94a3b8\">No hosts categorized yet.</text>\n");
            }

            sb.Append("</svg>\n");
            return Encoding.UTF8.GetBytes(sb.ToString());
        }

        // ==================== SVG pieces ====================

        private static string Defs()
        {
            var sb = new StringBuilder();
            sb.Append("<defs>\n");
            sb.Append(@"  <marker id=""arrDown"" viewBox=""0 0 10 10"" refX=""10"" refY=""5""
          markerWidth=""10"" markerHeight=""10"" orient=""auto"">
    <polygon points=""0 0, 10 5, 0 10"" fill=""#333""/>
  </marker>
");
            // One arrowhead marker per pivot technique colour. Static id list
            // so a rasteriser without context-stroke support (older ImageMagick)
            // still renders correctly.
            foreach (var colour in new[] { "#c026d3", "#dc2626", "#ea580c", "#0d9488", "#7c3aed", "#ca8a04", "#334155" })
            {
                var id = "arrPivot_" + colour.TrimStart('#');
                sb.Append($@"  <marker id=""{id}"" viewBox=""0 0 10 10"" refX=""9"" refY=""5"" markerWidth=""8"" markerHeight=""8"" orient=""auto""><polygon points=""0 0, 10 5, 0 10"" fill=""{colour}""/></marker>
");
            }
            sb.Append("</defs>\n");
            return sb.ToString();
        }

        private static string PivotMarkerId(string colour) => "arrPivot_" + colour.TrimStart('#');

        private static string DownArrow(int cx, int y1, int y2)
        {
            return $"<line x1=\"{cx}\" y1=\"{y1}\" x2=\"{cx}\" y2=\"{y2}\" stroke=\"#111\" stroke-width=\"1.6\" marker-end=\"url(#arrDown)\"/>\n";
        }

        // Attacker Network block: dashed container, hooded-figure monitor, sub-label.
        private static string AttackerBlock(int x, int y)
        {
            int w = AttackerW, h = AttackerH;
            var sb = new StringBuilder();
            sb.Append($"<g>");
            sb.Append($"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" fill=\"none\" stroke=\"#333\" stroke-width=\"1.4\" stroke-dasharray=\"4,3\"/>");
            sb.Append($"<text x=\"{x + w / 2}\" y=\"{y + 22}\" text-anchor=\"middle\" font-size=\"16\" font-weight=\"700\" fill=\"#111\">Middleast-2</text>");

            // Hooded-figure monitor icon centered horizontally, near top of the box.
            int ix = x + (w - 100) / 2;
            int iy = y + 38;
            sb.Append($"<g transform=\"translate({ix},{iy})\">");
            // Monitor bezel + screen
            sb.Append("<rect x=\"0\" y=\"20\" width=\"100\" height=\"70\" rx=\"4\" fill=\"#e6f2fb\" stroke=\"#111\" stroke-width=\"1.2\"/>");
            sb.Append("<rect x=\"5\" y=\"25\" width=\"90\" height=\"55\" fill=\"#ffffff\" stroke=\"#111\" stroke-width=\"0.6\"/>");
            // Hood
            sb.Append("<path d=\"M 34 12 Q 34 -2 50 -2 Q 66 -2 66 12 L 66 30 L 34 30 Z\" fill=\"#111\" stroke=\"#111\"/>");
            // Eyes strip
            sb.Append("<rect x=\"42\" y=\"16\" width=\"16\" height=\"6\" fill=\"#e6f2fb\"/>");
            // Shoulders under screen
            sb.Append("<path d=\"M 30 30 Q 30 44 40 48 L 60 48 Q 70 44 70 30 Z\" fill=\"#111\"/>");
            // Stand + base
            sb.Append("<rect x=\"45\" y=\"90\" width=\"10\" height=\"6\" fill=\"#111\"/>");
            sb.Append("<rect x=\"30\" y=\"96\" width=\"40\" height=\"4\" rx=\"1\" fill=\"#111\"/>");
            sb.Append("</g>");

            // Sub-label
            sb.Append($"<text x=\"{x + w / 2}\" y=\"{y + h - 26}\" text-anchor=\"middle\" font-size=\"13\" fill=\"#111\">VDI</text>");
            sb.Append($"<text x=\"{x + w / 2}\" y=\"{y + h - 10}\" text-anchor=\"middle\" font-size=\"13\" fill=\"#111\">Infrastructure</text>");
            sb.Append($"</g>\n");
            return sb.ToString();
        }

        // Outer dashed engagement frame that wraps every category box, with a
        // small solid-outline label chip sitting on the top-left of the frame
        // (matches the "All Ports Tours Network" chip in the reference).
        private static string EngagementFrame(int x, int y, int w, int h, string label)
        {
            var sb = new StringBuilder();
            sb.Append($"<g>");
            sb.Append($"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" fill=\"none\" stroke=\"#333\" stroke-width=\"1.4\" stroke-dasharray=\"6,4\"/>");
            // Label chip nested into the top-left corner, breaking the dashed
            // outline so the frame reads as a named container rather than an
            // anonymous box.
            const int chipPadX = 10, chipPadY = 5;
            const int fs = 13;
            int textW = (int)Math.Ceiling((label ?? "").Length * fs * 0.6);
            int chipW = textW + 2 * chipPadX;
            int chipH = fs + 2 * chipPadY;
            int chipX = x + 14;
            int chipY = y - chipH / 2;
            sb.Append($"<rect x=\"{chipX}\" y=\"{chipY}\" width=\"{chipW}\" height=\"{chipH}\" fill=\"#ffffff\" stroke=\"#333\" stroke-width=\"1\"/>");
            sb.Append($"<text x=\"{chipX + chipW / 2}\" y=\"{chipY + chipH / 2 + fs / 3}\" text-anchor=\"middle\" font-size=\"{fs}\" font-weight=\"700\" fill=\"#111\">{XmlEscape(label ?? "")}</text>");
            sb.Append("</g>\n");
            return sb.ToString();
        }

        // Cisco cylinder router — clean body only, no coloured diagonal arrow shapes.
        private static string CiscoRouter(int x, int y)
        {
            var sb = new StringBuilder();
            sb.Append($"<g transform=\"translate({x},{y})\">");
            sb.Append("<rect x=\"0\" y=\"16\" width=\"100\" height=\"28\" fill=\"#2ea3c9\"/>");
            sb.Append("<ellipse cx=\"50\" cy=\"44\" rx=\"50\" ry=\"12\" fill=\"#1f80a3\"/>");
            sb.Append("<ellipse cx=\"50\" cy=\"16\" rx=\"50\" ry=\"12\" fill=\"#2ea3c9\"/>");
            sb.Append("<ellipse cx=\"50\" cy=\"16\" rx=\"50\" ry=\"12\" fill=\"none\" stroke=\"#9be3f5\" stroke-width=\"1\" opacity=\"0.8\"/>");
            sb.Append("</g>\n");
            return sb.ToString();
        }

        // One dashed sub-environment box with a header bar and a grid of devices.
        // hostCentres accumulates per-IP (cx, cy) coordinates so callers can
        // draw overlay arrows (e.g. pivot edges) between hosts across subnets.
        private static string SubEnvBox(int x, int y, int w, int h, string label, List<Box> hosts,
                                        Dictionary<string, (int Cx, int Cy)> hostCentres = null)
        {
            var sb = new StringBuilder();
            // Container (dashed)
            sb.Append($"<g>");
            sb.Append($"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" fill=\"none\" stroke=\"#333\" stroke-width=\"1.2\" stroke-dasharray=\"4,3\"/>");
            // Header bar (solid rectangle around the title, no fill)
            sb.Append($"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{SubBoxHeaderH}\" fill=\"none\" stroke=\"#333\" stroke-width=\"1\"/>");
            sb.Append($"<text x=\"{x + w / 2}\" y=\"{y + 22}\" text-anchor=\"middle\" font-size=\"15\" font-weight=\"700\" fill=\"#111\">{XmlEscape(label)}</text>");
            sb.Append($"</g>\n");

            // Device grid inside sub-box
            int gridX = x + SubBoxPadX;
            int gridY = y + SubBoxHeaderH + SubBoxPadY;
            int gridInnerW = w - 2 * SubBoxPadX;
            int cellSpanW = gridInnerW / DevPerRow;         // cell horizontal slot (label may span slightly)

            for (int i = 0; i < hosts.Count; i++)
            {
                int row = i / DevPerRow;
                int col = i % DevPerRow;
                int cellCx = gridX + col * cellSpanW + cellSpanW / 2;
                int cellTopY = gridY + row * CellH;
                sb.Append(DeviceCell(cellCx, cellTopY, hosts[i]));
                if (hostCentres != null && !string.IsNullOrEmpty(hosts[i].Ip))
                {
                    // Centre of the icon (icon top = cellTopY, height = IconH).
                    hostCentres[hosts[i].Ip] = (cellCx, cellTopY + IconH / 2);
                }
            }
            return sb.ToString();
        }

        // Render every pivot edge as an orthogonal (Manhattan) arrow that exits
        // its source host from the side, routes horizontally out of the source
        // subnet, drops into a per-edge lane in the channel below the subnet
        // row, crosses to the destination side, and rises back into the target
        // host from its side. Each edge gets its own lane so parallel arrows
        // never overlap, and by routing outside the subnet frames we never
        // draw through unrelated host icons ("obsidian-canvas" style).
        //
        // Labels sit on the horizontal lane segment as rounded pill boxes
        // (white fill, coloured border + text) so they read cleanly at any
        // scale and don't get lost against the grid like the old 11pt halo
        // labels did.
        private static string PivotEdgesOverlay(List<jVision.Shared.Models.PivotEdge> edges,
                                                Dictionary<string, (int Cx, int Cy)> hostCentres,
                                                Dictionary<string, (int X, int Y, int W, int H)> hostSubBox,
                                                int subnetRowBottom)
        {
            var sb = new StringBuilder();
            // Filter to only edges we can actually place, preserving order so
            // lane assignment matches the order rows appear in the Pivots page.
            var valid = new List<jVision.Shared.Models.PivotEdge>();
            foreach (var e in edges)
            {
                if (e == null || string.IsNullOrEmpty(e.SourceIp) || string.IsNullOrEmpty(e.TargetIp)) continue;
                if (string.Equals(e.SourceIp, e.TargetIp, StringComparison.OrdinalIgnoreCase)) continue;
                if (!hostCentres.ContainsKey(e.SourceIp) || !hostCentres.ContainsKey(e.TargetIp)) continue;
                valid.Add(e);
            }
            if (valid.Count == 0) return "";

            int channelTop = subnetRowBottom + PivotChannelGap;

            for (int i = 0; i < valid.Count; i++)
            {
                var e = valid[i];
                var src = hostCentres[e.SourceIp];
                var dst = hostCentres[e.TargetIp];
                var srcSub = hostSubBox[e.SourceIp];
                var dstSub = hostSubBox[e.TargetIp];
                int laneY = channelTop + i * PivotLaneSpacing;
                string colour = TechniqueColour(e.Technique);
                string marker = PivotMarkerId(colour);
                string label = FormatPivotLabel(e);

                // Unified routing: exit both hosts from the side that faces
                // the other endpoint, drop into the shared below-subnet lane
                // through a "column" that sits in the empty cell gutter next
                // to the icon (not on top of another host). For cross-subnet
                // edges we push the column all the way outside the source /
                // destination subnet frame so the vertical run stays clear of
                // every host in that subnet. Per-edge offset staggers columns
                // so parallel arrows don't stack on top of each other.
                bool sameSubnet = srcSub.Equals(dstSub);
                int dir = dst.Cx > src.Cx ? 1 : (dst.Cx < src.Cx ? -1 : 1);
                int stagger = i * 6;
                int srcExitX = src.Cx + dir * (IconW / 2);
                int dstEnterX = dst.Cx - dir * (IconW / 2);
                int srcCol, dstCol;
                if (sameSubnet)
                {
                    // Same subnet: use the cell gutter right next to each icon
                    // so we don't wrap around the entire subnet frame.
                    srcCol = src.Cx + dir * (IconW / 2 + 10 + stagger);
                    dstCol = dst.Cx - dir * (IconW / 2 + 10 + stagger);
                }
                else
                {
                    // Cross-subnet: keep the drop column outside the subnet
                    // frame so the vertical segment doesn't clip any host in
                    // the source / destination subnet.
                    srcCol = dir > 0 ? srcSub.X + srcSub.W + 20 + stagger : srcSub.X - 20 - stagger;
                    dstCol = dir > 0 ? dstSub.X - 20 - stagger : dstSub.X + dstSub.W + 20 + stagger;
                }
                var waypoints = new List<(int X, int Y)>
                {
                    (srcExitX, src.Cy),
                    (srcCol,   src.Cy),
                    (srcCol,   laneY),
                    (dstCol,   laneY),
                    (dstCol,   dst.Cy),
                    (dstEnterX, dst.Cy),
                };

                sb.Append(BuildOrthoPath(waypoints, colour, marker));

                if (!string.IsNullOrEmpty(label))
                {
                    // Pill sits on the horizontal lane segment, centred on the
                    // two mid-waypoints so long paths still put the label in
                    // the middle of the run, not next to a bend.
                    int lx = (waypoints[waypoints.Count / 2 - 1].X + waypoints[waypoints.Count / 2].X) / 2;
                    sb.Append(BuildPillLabel(lx, laneY, label, colour));
                }
            }
            return sb.ToString();
        }

        // Emit an orthogonal path through the given waypoints. Consecutive
        // segments must alternate between purely-horizontal and purely-vertical
        // (i.e. adjacent waypoints share one coordinate). Each interior corner
        // is replaced with a quarter-circle arc of radius PivotCornerRadius so
        // the bends look Obsidian-canvas smooth. Sweep flag per corner is
        // derived from the 2-D cross product of the incoming vs. outgoing
        // segment direction — positive cross = clockwise turn (sweep=1) in
        // SVG's y-down coordinate system.
        private static string BuildOrthoPath(List<(int X, int Y)> pts, string colour, string marker)
        {
            if (pts == null || pts.Count < 2) return "";
            int r = PivotCornerRadius;
            var p = new StringBuilder();
            p.Append(FormattableString.Invariant($"M {pts[0].X} {pts[0].Y}"));

            for (int i = 1; i < pts.Count; i++)
            {
                var prev = pts[i - 1];
                var cur = pts[i];
                bool last = i == pts.Count - 1;

                if (last)
                {
                    // Straight segment to the endpoint (no corner to round).
                    if (cur.X == prev.X) p.Append(FormattableString.Invariant($" V {cur.Y}"));
                    else if (cur.Y == prev.Y) p.Append(FormattableString.Invariant($" H {cur.X}"));
                    else p.Append(FormattableString.Invariant($" L {cur.X} {cur.Y}"));
                    continue;
                }

                var next = pts[i + 1];
                int dx1 = cur.X - prev.X, dy1 = cur.Y - prev.Y;
                int dx2 = next.X - cur.X, dy2 = next.Y - cur.Y;
                int len1 = Math.Abs(dx1) + Math.Abs(dy1);        // orthogonal: one is zero
                int len2 = Math.Abs(dx2) + Math.Abs(dy2);
                int rr = Math.Min(r, Math.Min(len1, len2) / 2);
                if (rr <= 0)
                {
                    // No room for an arc — draw a straight through this point.
                    if (cur.X == prev.X) p.Append(FormattableString.Invariant($" V {cur.Y}"));
                    else                 p.Append(FormattableString.Invariant($" H {cur.X}"));
                    continue;
                }

                int sx1 = Math.Sign(dx1), sy1 = Math.Sign(dy1);
                int sx2 = Math.Sign(dx2), sy2 = Math.Sign(dy2);
                int preX = cur.X - sx1 * rr, preY = cur.Y - sy1 * rr;
                int postX = cur.X + sx2 * rr, postY = cur.Y + sy2 * rr;
                int sweep = (sx1 * sy2 - sy1 * sx2) > 0 ? 1 : 0;

                if (preX == prev.X) p.Append(FormattableString.Invariant($" V {preY}"));
                else                p.Append(FormattableString.Invariant($" H {preX}"));
                p.Append(FormattableString.Invariant($" A {rr} {rr} 0 0 {sweep} {postX} {postY}"));
            }

            return $"<path d=\"{p}\" fill=\"none\" stroke=\"{colour}\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" marker-end=\"url(#{marker})\" opacity=\"0.95\"/>\n";
        }

        // Rounded pill: white background, coloured border, coloured bold text.
        // Sits centred on (cx, cy) which is the midpoint of the arrow's
        // horizontal lane segment.
        private static string BuildPillLabel(int cx, int cy, string label, string colour)
        {
            const int fontSize = 13;
            const int padX = 10;
            const int padY = 5;
            // Approximate text width from character count. Slightly generous so
            // long labels aren't clipped by the pill outline.
            int textW = (int)Math.Ceiling(label.Length * fontSize * 0.58);
            int pillW = textW + 2 * padX;
            int pillH = fontSize + 2 * padY + 2;
            int rx = pillH / 2;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<rect x=\"{cx - pillW / 2}\" y=\"{cy - pillH / 2}\" width=\"{pillW}\" height=\"{pillH}\" rx=\"{rx}\" ry=\"{rx}\" fill=\"#ffffff\" stroke=\"{colour}\" stroke-width=\"1.4\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{cx}\" y=\"{cy + fontSize / 3}\" text-anchor=\"middle\" font-size=\"{fontSize}\" font-weight=\"700\" fill=\"{colour}\">{XmlEscape(label)}</text>\n"));
            return sb.ToString();
        }

        private static string TechniqueColour(string t) => (t ?? "").ToLowerInvariant() switch
        {
            "creds"   => "#c026d3",   // magenta
            "exploit" => "#dc2626",   // red
            "rce"     => "#ea580c",   // orange
            "session" => "#0d9488",   // teal
            "relay"   => "#7c3aed",   // violet
            "phish"   => "#ca8a04",   // amber
            _         => "#334155",   // slate
        };

        private static string FormatPivotLabel(jVision.Shared.Models.PivotEdge e)
        {
            var pieces = new List<string>();
            if (!string.IsNullOrWhiteSpace(e.Technique) && e.Technique != "other") pieces.Add(e.Technique);
            if (!string.IsNullOrWhiteSpace(e.Label)) pieces.Add(e.Label);
            return Ellipsize(string.Join(": ", pieces), 40);
        }

        // A single device cell. cx = horizontal centre; top = top y.
        // Shows OS-specific monitor icon + IP address only (no hostname notes).
        private static string DeviceCell(int cx, int top, Box b)
        {
            int ix = cx - IconW / 2;
            var sb = new StringBuilder();
            sb.Append($"<g>");
            if (IsCloud(b))
                sb.Append(CloudMonitor(ix, top));
            else if (IsMobile(b))
                sb.Append(MobilePhone(ix, top));
            else if (IsWindows(b))
                sb.Append(WinTileMonitor(ix, top));
            else
                sb.Append(LinuxMonitor(ix, top));
            int labelY = top + IconH + 20;
            sb.Append($"<text x=\"{cx}\" y=\"{labelY}\" text-anchor=\"middle\" font-size=\"14\" font-weight=\"700\" fill=\"#111\">{XmlEscape(b.Ip ?? "")}</text>");

            // Full FQDN directly under the IP — plain black text, no
            // outline. Cell width is sized so labels like
            // "navigation.allports.tours" fit without clipping even at the
            // bumped-up domain font size.
            var domain = (b.Domain ?? "").Trim();
            if (domain.Length > 0)
            {
                sb.Append(FormattableString.Invariant(
                    $"<text x=\"{cx}\" y=\"{labelY + 18}\" text-anchor=\"middle\" font-size=\"12\" fill=\"#111\">{XmlEscape(domain)}</text>"));
            }

            sb.Append($"</g>\n");
            return sb.ToString();
        }

        // ==================== device icons ====================

        // Windows: just the four-colour flag, no monitor frame — matches the
        // Tux mascot style so Windows and Linux hosts share a visual language.
        private static string WinTileMonitor(int x, int y)
        {
            var sb = new StringBuilder();
            sb.Append($"<g transform=\"translate({x},{y})\">");
            sb.Append("<path d=\"M 6 8 L 25 5 L 25 22 L 6 24 Z\" fill=\"#f25022\"/>");
            sb.Append("<path d=\"M 27 5 L 47 3 L 47 22 L 27 22 Z\" fill=\"#7fba00\"/>");
            sb.Append("<path d=\"M 6 26 L 25 24 L 25 41 L 6 43 Z\" fill=\"#00a4ef\"/>");
            sb.Append("<path d=\"M 27 24 L 47 22 L 47 41 L 27 41 Z\" fill=\"#ffb900\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        // Base64-embedded Tux PNG in the 52x45 icon footprint, letterboxed so
        // the aspect ratio isn't squashed.
        private static string LinuxMonitor(int x, int y)
        {
            return FormattableString.Invariant(
                $"<image x=\"{x}\" y=\"{y}\" width=\"52\" height=\"45\" preserveAspectRatio=\"xMidYMid meet\" href=\"{TuxAsset.DataUrl}\"/>");
        }

        // Soft cloud silhouette used for cloud-tagged endpoints (S3 buckets,
        // AWS/Azure/GCP surface). Fits the same 52x45 icon footprint so the
        // grid stays aligned when a row mixes cloud and on-prem hosts.
        private static string CloudMonitor(int x, int y)
        {
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<g transform=\"translate({x},{y})\">"));
            sb.Append("<path d=\"M 8 34 Q -2 34 -2 26 Q -2 18 8 18 Q 8 6 22 6 Q 36 6 38 18 Q 50 18 50 26 Q 50 34 40 34 Z\" fill=\"#bae6fd\" stroke=\"#0369a1\" stroke-width=\"1.8\" stroke-linejoin=\"round\"/>");
            sb.Append("<ellipse cx=\"14\" cy=\"22\" rx=\"5\" ry=\"3\" fill=\"#e0f2fe\" stroke=\"none\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        // Portrait smartphone silhouette for mobile hosts. Rounded body,
        // small speaker slot at the top, home indicator at the bottom, and a
        // subtle screen fill so the outline reads from a distance. Centred
        // inside the same 52x45 icon footprint as every other icon.
        private static string MobilePhone(int x, int y)
        {
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<g transform=\"translate({x},{y})\">"));
            // Body (portrait rounded rectangle, centred: x=17,w=18,h=43)
            sb.Append("<rect x=\"17\" y=\"1\" width=\"18\" height=\"43\" rx=\"3\" ry=\"3\" fill=\"#1f2937\" stroke=\"#111827\" stroke-width=\"1\"/>");
            // Screen
            sb.Append("<rect x=\"19\" y=\"6\" width=\"14\" height=\"32\" rx=\"1\" ry=\"1\" fill=\"#60a5fa\"/>");
            // Speaker slot
            sb.Append("<rect x=\"24\" y=\"3.5\" width=\"4\" height=\"1.2\" rx=\"0.6\" ry=\"0.6\" fill=\"#9ca3af\"/>");
            // Home indicator
            sb.Append("<rect x=\"23\" y=\"40.5\" width=\"6\" height=\"1.6\" rx=\"0.8\" ry=\"0.8\" fill=\"#9ca3af\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        // ==================== helpers ====================

        private static string XmlEscape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("&", "&amp;").Replace("<", "&lt;")
                    .Replace(">", "&gt;").Replace("\"", "&quot;")
                    .Replace("'", "&apos;");
        }

        private static string Ellipsize(string s, int max) =>
            (s?.Length ?? 0) <= max ? (s ?? "") : s.Substring(0, max - 1) + "…";

        // ==================== draw.io export ====================
        //
        // Same visual language as the PNG/SVG: every icon is embedded as a
        // URL-encoded SVG data-URL on a `shape=image` mxCell. drawio treats
        // these as fully editable vertex cells (move, resize, relabel, swap
        // image) so the exported .drawio looks like the PNG but is editable.
        //
        // URL-encoding (not base64) is used so no `;` ever appears inside the
        // style value — drawio splits styles on `;`, which would truncate a
        // raw `data:image/png;base64,...` URL.

        private static string SvgDataUrl(string rawSvg) =>
            "data:image/svg+xml," + Uri.EscapeDataString(rawSvg);

        // Standalone hooded-attacker-at-a-monitor icon. Hood path goes above
        // y=0 so the viewBox has a negative y origin.
        private static string DrawioAttackerIconDataUrl() => SvgDataUrl(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 -4 100 104'>" +
            "<rect x='0' y='20' width='100' height='70' rx='4' fill='#e6f2fb' stroke='#111' stroke-width='1.2'/>" +
            "<rect x='5' y='25' width='90' height='55' fill='#ffffff' stroke='#111' stroke-width='0.6'/>" +
            "<path d='M 34 12 Q 34 -2 50 -2 Q 66 -2 66 12 L 66 30 L 34 30 Z' fill='#111' stroke='#111'/>" +
            "<rect x='42' y='16' width='16' height='6' fill='#e6f2fb'/>" +
            "<path d='M 30 30 Q 30 44 40 48 L 60 48 Q 70 44 70 30 Z' fill='#111'/>" +
            "<rect x='45' y='90' width='10' height='6' fill='#111'/>" +
            "<rect x='30' y='96' width='40' height='4' rx='1' fill='#111'/>" +
            "</svg>");

        private static string DrawioRouterIconDataUrl() => SvgDataUrl(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 58'>" +
            "<rect x='0' y='16' width='100' height='28' fill='#2ea3c9'/>" +
            "<ellipse cx='50' cy='44' rx='50' ry='12' fill='#1f80a3'/>" +
            "<ellipse cx='50' cy='16' rx='50' ry='12' fill='#2ea3c9'/>" +
            "<ellipse cx='50' cy='16' rx='50' ry='12' fill='none' stroke='#9be3f5' stroke-width='1' opacity='0.8'/>" +
            "</svg>");

        private static string DrawioWindowsIconDataUrl() => SvgDataUrl(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 52 45'>" +
            "<path d='M 6 8 L 25 5 L 25 22 L 6 24 Z' fill='#f25022'/>" +
            "<path d='M 27 5 L 47 3 L 47 22 L 27 22 Z' fill='#7fba00'/>" +
            "<path d='M 6 26 L 25 24 L 25 41 L 6 43 Z' fill='#00a4ef'/>" +
            "<path d='M 27 24 L 47 22 L 47 41 L 27 41 Z' fill='#ffb900'/>" +
            "</svg>");

        private static string DrawioCloudIconDataUrl() => SvgDataUrl(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='-4 0 56 45'>" +
            "<path d='M 8 34 Q -2 34 -2 26 Q -2 18 8 18 Q 8 6 22 6 Q 36 6 38 18 Q 50 18 50 26 Q 50 34 40 34 Z' fill='#bae6fd' stroke='#0369a1' stroke-width='1.8' stroke-linejoin='round'/>" +
            "<ellipse cx='14' cy='22' rx='5' ry='3' fill='#e0f2fe'/>" +
            "</svg>");

        private static string DrawioMobileIconDataUrl() => SvgDataUrl(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 52 45'>" +
            "<rect x='17' y='1' width='18' height='43' rx='3' ry='3' fill='#1f2937' stroke='#111827' stroke-width='1'/>" +
            "<rect x='19' y='6' width='14' height='32' rx='1' ry='1' fill='#60a5fa'/>" +
            "<rect x='24' y='3.5' width='4' height='1.2' rx='0.6' ry='0.6' fill='#9ca3af'/>" +
            "<rect x='23' y='40.5' width='6' height='1.6' rx='0.8' ry='0.8' fill='#9ca3af'/>" +
            "</svg>");

        // Tux is a PNG (TuxAsset.DataUrl). Wrap it in an SVG `<image>` so the
        // outer URL has no `;` after URL-encoding, matching the other icons.
        private static string DrawioLinuxIconDataUrl() => SvgDataUrl(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 52 45'>" +
            $"<image x='0' y='0' width='52' height='45' preserveAspectRatio='xMidYMid meet' href='{TuxAsset.DataUrl}'/>" +
            "</svg>");

        private static string DrawioHostIconUrl(Box b)
        {
            if (IsCloud(b)) return DrawioCloudIconDataUrl();
            if (IsMobile(b)) return DrawioMobileIconDataUrl();
            if (IsWindows(b)) return DrawioWindowsIconDataUrl();
            return DrawioLinuxIconDataUrl();
        }

        public static byte[] RenderDrawio(List<Box> boxes)
        {
            var grouped = GroupByCategory(boxes);
            var layout = Compute(grouped);

            var ms = new MemoryStream();
            var settings = new XmlWriterSettings
            {
                OmitXmlDeclaration = true,
                Indent = true,
                Encoding = new UTF8Encoding(false),
            };
            using (var w = XmlWriter.Create(ms, settings))
            {
                w.WriteStartElement("mxfile");
                w.WriteAttributeString("host", "app.diagrams.net");
                w.WriteStartElement("diagram");
                w.WriteAttributeString("id", "jvision-topology");
                w.WriteAttributeString("name", "Topology");
                w.WriteStartElement("mxGraphModel");
                w.WriteAttributeString("dx", "1200");
                w.WriteAttributeString("dy", "800");
                w.WriteAttributeString("grid", "1");
                w.WriteAttributeString("gridSize", "10");
                w.WriteAttributeString("pageWidth", layout.CanvasW.ToString(CultureInfo.InvariantCulture));
                w.WriteAttributeString("pageHeight", layout.CanvasH.ToString(CultureInfo.InvariantCulture));
                w.WriteStartElement("root");

                DrawioCell(w, "0", null, null, null);
                DrawioCell(w, "1", "0", null, null);

                // Attacker box (dashed swimlane) + hooded-figure monitor icon
                // child so the drawio file carries the same artwork as the PNG.
                DrawioVertex(w, "attacker", "1", "Middleast-2",
                    "swimlane;html=1;fontStyle=1;startSize=28;fillColor=none;strokeColor=#333333;strokeWidth=1.4;dashed=1;dashPattern=4 3;fontColor=#111111;fontSize=16;",
                    layout.AttackerX, AttackerTopY, AttackerW, AttackerH);
                // Icon is drawn with coordinates relative to its parent cell
                // (the swimlane); the 26 px startSize is included so the icon
                // sits below the title bar.
                DrawioVertex(w, "attacker_icon", "attacker", "",
                    "shape=image;html=1;image=" + DrawioAttackerIconDataUrl() + ";imageAspect=0;",
                    (AttackerW - 100) / 2, 38 + 26 - 26, 100, 100);

                // Router — Cisco cylinder, redrawn as our hand-styled icon so
                // it matches the PNG rather than the generic drawio stencil.
                DrawioVertex(w, "router", "1", "ROUTER",
                    "shape=image;html=1;image=" + DrawioRouterIconDataUrl() + ";imageAspect=0;fontColor=#111111;fontStyle=1;labelPosition=right;verticalLabelPosition=middle;align=left;verticalAlign=middle;",
                    layout.RouterX, RouterTopY, RouterW, RouterH);

                // Edges attacker -> router -> engagement frame
                DrawioEdge(w, "e1", "1", "attacker", "router", downArrow: true);

                // Outer engagement container so operators can drag the whole
                // network as one unit in draw.io.
                DrawioVertex(w, "engagement", "1", OuterFrameLabel,
                    "swimlane;html=1;fontStyle=1;startSize=30;fillColor=none;strokeColor=#333333;strokeWidth=1.4;dashed=1;dashPattern=6 4;fontColor=#111111;fontSize=15;",
                    layout.OuterFrameX, layout.OuterFrameY, layout.OuterFrameW, layout.OuterFrameH);

                // Category sub-environments and their hosts
                for (int i = 0; i < grouped.Count; i++)
                {
                    var (category, hosts) = grouped[i];
                    var (x, y, sw, sh) = layout.SubBoxes[i];
                    string subId = $"sub_{i}";
                    // draw.io swimlane coords are absolute for top-level children of "1".
                    DrawioVertex(w, subId, "1", category,
                        "swimlane;html=1;fontStyle=1;startSize=30;fillColor=none;strokeColor=#333333;strokeWidth=1.2;dashed=1;dashPattern=4 3;fontColor=#111111;fontSize=15;",
                        x, y, sw, sh);

                    int gridX = SubBoxPadX;
                    int gridY = SubBoxHeaderH + SubBoxPadY;
                    int gridInnerW = sw - 2 * SubBoxPadX;
                    int cellSpanW = gridInnerW / DevPerRow;
                    for (int hIdx = 0; hIdx < hosts.Count; hIdx++)
                    {
                        var host = hosts[hIdx];
                        int row = hIdx / DevPerRow;
                        int col = hIdx % DevPerRow;
                        int hx = gridX + col * cellSpanW + (cellSpanW - IconW) / 2;
                        int hy = gridY + row * CellH;
                        // Match the SVG's two-line label: IP on top, Hostname
                        // (or Domain if hostname is blank) underneath.
                        string hostname = string.IsNullOrEmpty(host.Hostname) ? "" : host.Hostname;
                        string second = !string.IsNullOrEmpty(hostname) ? hostname
                                       : (!string.IsNullOrEmpty(host.Domain) ? host.Domain : "");
                        string label = (host.Ip ?? "") + (string.IsNullOrEmpty(second) ? "" : "<br>" + second);
                        string style = "shape=image;html=1;image=" + DrawioHostIconUrl(host) +
                                       ";imageAspect=0;labelPosition=center;verticalLabelPosition=bottom;align=center;verticalAlign=top;fontSize=13;fontStyle=1;fontColor=#111111;";
                        DrawioVertex(w, $"h_{i}_{hIdx}", subId, label, style, hx, hy, IconW, IconH);
                    }
                }

                w.WriteEndElement();  // root
                w.WriteEndElement();  // mxGraphModel
                w.WriteEndElement();  // diagram
                w.WriteEndElement();  // mxfile
            }
            return ms.ToArray();
        }

        private static void DrawioCell(XmlWriter w, string id, string parent, string value, string style)
        {
            w.WriteStartElement("mxCell");
            w.WriteAttributeString("id", id);
            if (value != null) w.WriteAttributeString("value", value);
            if (style != null) w.WriteAttributeString("style", style);
            if (parent != null) w.WriteAttributeString("parent", parent);
            w.WriteEndElement();
        }

        private static void DrawioVertex(XmlWriter w, string id, string parent, string value, string style, int x, int y, int width, int height)
        {
            w.WriteStartElement("mxCell");
            w.WriteAttributeString("id", id);
            w.WriteAttributeString("value", value ?? "");
            w.WriteAttributeString("style", style);
            w.WriteAttributeString("vertex", "1");
            w.WriteAttributeString("parent", parent);
            w.WriteStartElement("mxGeometry");
            w.WriteAttributeString("x", x.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("y", y.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("width", width.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("height", height.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("as", "geometry");
            w.WriteEndElement();
            w.WriteEndElement();
        }

        private static void DrawioEdge(XmlWriter w, string id, string parent, string source, string target, bool downArrow)
        {
            w.WriteStartElement("mxCell");
            w.WriteAttributeString("id", id);
            w.WriteAttributeString("style",
                downArrow
                    ? "endArrow=classic;startArrow=none;html=1;strokeColor=#111111;strokeWidth=1.6;"
                    : "endArrow=classic;startArrow=classic;html=1;strokeColor=#111111;strokeWidth=1.6;");
            w.WriteAttributeString("edge", "1");
            w.WriteAttributeString("parent", parent);
            w.WriteAttributeString("source", source);
            w.WriteAttributeString("target", target);
            w.WriteStartElement("mxGeometry");
            w.WriteAttributeString("relative", "1");
            w.WriteAttributeString("as", "geometry");
            w.WriteEndElement();
            w.WriteEndElement();
        }
    }
}
