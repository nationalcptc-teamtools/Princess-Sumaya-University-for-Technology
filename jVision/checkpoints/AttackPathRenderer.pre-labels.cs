using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using jVision.Server.Models;
using jVision.Shared.Models;

namespace jVision.Server.Download
{
    // Dedicated "attack-narrative map" renderer, meant for the report page —
    // NOT overlaid on the network topology. Every recorded PivotEdge becomes
    // a numbered step in a top-down tree, so the reader can follow the kill
    // chain by step number without decoding IP layouts.
    //
    // Structure:
    //     ATTACKER (hooded monitor icon)
    //        │  initial access
    //        ▼
    //     [ first foothold(s) ]
    //        │  (1) exploit: CVE-…
    //        ▼
    //     [ next hop ]
    //        │  (2) creds: user:pass
    //        ▼
    //        …
    //
    // Steps are numbered by PivotEdge.CreatedAt so the numbers match the order
    // the operator captured them. If the pivot graph branches (one source
    // reached two targets) the tree layout centers each subtree independently
    // — the classic Reingold–Tilford-lite algorithm.
    public static class AttackPathRenderer
    {
        // --- layout constants --------------------------------------------------
        // Horizontal (left→right) kill-chain layout. Attacker sits on the far
        // left, each successive hop is one card-column further right, and any
        // branches (one source pivoting to N targets) stack vertically inside
        // the same column.
        private const int NodeW = 110;
        private const int NodeH = 100;
        private const int HStep = 130;   // horizontal spacing between hop levels
        private const int VStep = 44;    // vertical spacing between sibling branches
        private const int PadX = 50;
        private const int PadY = 24;     // top/bottom breathing room around the tree
        private const int MinCanvasW = 640;
        private const int MinCanvasH = 200;

        private const int IconInsetX = (NodeW - 52) / 2;
        private const int IconInsetY = 10;
        private const int CornerRadius = 10;

        // Legend block sizing.
        private const int LegendTitleH = 40;
        private const int LegendRowH = 26;
        private const int LegendPadY = 24;
        private const int LegendLeftX = 60;

        // --- render entry ------------------------------------------------------

        public static byte[] RenderSvg(List<Box> boxes, List<PivotEdge> edges)
        {
            var boxByIp = new Dictionary<string, Box>(StringComparer.OrdinalIgnoreCase);
            foreach (var b in boxes)
                if (!string.IsNullOrEmpty(b.Ip)) boxByIp[b.Ip] = b;

            var valid = (edges ?? new List<PivotEdge>())
                .Where(e => e != null
                            && !string.IsNullOrEmpty(e.SourceIp)
                            && !string.IsNullOrEmpty(e.TargetIp)
                            && !string.Equals(e.SourceIp, e.TargetIp, StringComparison.OrdinalIgnoreCase))
                .OrderBy(e => e.CreatedAt)
                .ToList();

            var attacker = new TreeNode { Label = "Attacker", IsAttacker = true };
            var tree = BuildTree(valid, boxByIp, attacker);
            LayoutTree(tree, PadX, PadY);

            // Numbered pivots only (skip the star ★ "initial access" edge)
            // become entries in the legend below the tree.
            var legendSteps = valid.Select((e, idx) => (Edge: e, Step: idx + 1)).ToList();
            int legendRows = legendSteps.Count;
            int legendBlockH = legendRows > 0 ? LegendTitleH + LegendRowH * legendRows + LegendPadY : 0;

            int canvasW = Math.Max(MinCanvasW, ComputeCanvasWidth(tree) + PadX);
            int canvasH = Math.Max(MinCanvasH, tree.SubtreeH + 2 * PadY) + legendBlockH;

            var sb = new StringBuilder();
            sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n");
            sb.Append($"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{canvasW}\" height=\"{canvasH}\" viewBox=\"0 0 {canvasW} {canvasH}\" font-family=\"Arial, Helvetica, sans-serif\">\n");
            sb.Append(Defs());
            sb.Append($"<rect width=\"{canvasW}\" height=\"{canvasH}\" fill=\"#ffffff\"/>\n");

            if (valid.Count == 0)
            {
                sb.Append($"<text x=\"{canvasW / 2}\" y=\"{canvasH / 2}\" text-anchor=\"middle\" font-size=\"14\" fill=\"#94a3b8\">No pivots recorded yet.</text>\n");
                sb.Append("</svg>\n");
                return Encoding.UTF8.GetBytes(sb.ToString());
            }

            // Draw edges first so nodes sit on top of arrowheads.
            DrawEdges(sb, tree);
            DrawNodes(sb, tree);

            if (legendSteps.Count > 0)
            {
                int legendTopY = Math.Max(MinCanvasH, tree.SubtreeH + 2 * PadY);
                DrawLegend(sb, legendSteps, canvasW, legendTopY);
            }

            sb.Append("</svg>\n");
            return Encoding.UTF8.GetBytes(sb.ToString());
        }

        private static void DrawLegend(StringBuilder sb, List<(PivotEdge Edge, int Step)> steps, int canvasW, int topY)
        {
            // Separator + title
            sb.Append(FormattableString.Invariant(
                $"<line x1=\"{LegendLeftX}\" y1=\"{topY}\" x2=\"{canvasW - LegendLeftX}\" y2=\"{topY}\" stroke=\"#cbd5e1\" stroke-width=\"1\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{LegendLeftX}\" y=\"{topY + 26}\" font-size=\"15\" font-weight=\"700\" fill=\"#111\">Steps</text>\n"));

            int rowY = topY + LegendTitleH + 4;
            foreach (var (edge, step) in steps)
            {
                string colour = TechniqueColour(edge.Technique);
                int badgeCx = LegendLeftX + 13;
                int badgeCy = rowY + 8;
                // Colored numbered circle matching the badge on the graph.
                sb.Append(FormattableString.Invariant(
                    $"<circle cx=\"{badgeCx}\" cy=\"{badgeCy}\" r=\"11\" fill=\"{colour}\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>\n"));
                sb.Append(FormattableString.Invariant(
                    $"<text x=\"{badgeCx}\" y=\"{badgeCy + 4}\" text-anchor=\"middle\" font-size=\"12\" font-weight=\"800\" fill=\"#ffffff\">{step}</text>\n"));

                // Row text: src → dst · technique · label. Coloured by
                // technique so the reader can match a row to its arrow at a
                // glance.
                string src = XmlEscape(edge.SourceIp ?? "");
                string dst = XmlEscape(edge.TargetIp ?? "");
                string tech = XmlEscape((edge.Technique ?? "other").Trim());
                string label = XmlEscape((edge.Label ?? "").Trim());
                string body = $"{src} → {dst}  ·  <tspan font-weight=\"700\">{tech}</tspan>";
                if (label.Length > 0) body += $"  ·  {label}";

                sb.Append(FormattableString.Invariant(
                    $"<text x=\"{badgeCx + 22}\" y=\"{badgeCy + 5}\" font-size=\"14\" fill=\"{colour}\">{body}</text>\n"));

                rowY += LegendRowH;
            }
        }

        // --- tree construction -------------------------------------------------

        private class TreeNode
        {
            public string Ip;
            public string Label;         // display text (IP or "Attacker")
            public bool IsAttacker;
            public bool IsWindows;
            public int X;
            public int Y;
            public int SubtreeH;         // total vertical span of this subtree
            public List<TreeEdge> Children = new();
        }

        private class TreeEdge
        {
            public PivotEdge Pivot;      // null for the implicit attacker→foothold edge
            public int StepNumber;       // 1-based step # from CreatedAt order; 0 for initial access
            public TreeNode Target;
        }

        // Build a strict tree: each host is placed under the FIRST pivot that
        // targets it (creation order). Any host that appears as a source but
        // never as a target of an earlier pivot becomes a foothold — child of
        // the attacker node with an "initial access" edge.
        private static TreeNode BuildTree(List<PivotEdge> valid,
                                          Dictionary<string, Box> boxByIp,
                                          TreeNode attacker)
        {
            var nodesByIp = new Dictionary<string, TreeNode>(StringComparer.OrdinalIgnoreCase);
            TreeNode GetOrCreate(string ip)
            {
                if (nodesByIp.TryGetValue(ip, out var n)) return n;
                n = new TreeNode
                {
                    Ip = ip,
                    Label = ip,
                    IsWindows = boxByIp.TryGetValue(ip, out var b) && IsWindowsBox(b),
                };
                nodesByIp[ip] = n;
                return n;
            }

            // Track which hosts are already attached to a parent to avoid
            // creating duplicate subtrees when the graph isn't a strict tree.
            var attached = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < valid.Count; i++)
            {
                var e = valid[i];
                var srcNode = GetOrCreate(e.SourceIp);
                var dstNode = GetOrCreate(e.TargetIp);

                if (!attached.Contains(e.SourceIp))
                {
                    // First time we see this source — treat it as a foothold
                    // if nobody has pivoted to it yet.
                    attacker.Children.Add(new TreeEdge
                    {
                        Target = srcNode,
                        Pivot = null,
                        StepNumber = 0,   // pre-step (initial access)
                    });
                    attached.Add(e.SourceIp);
                }

                if (!attached.Contains(e.TargetIp))
                {
                    srcNode.Children.Add(new TreeEdge
                    {
                        Target = dstNode,
                        Pivot = e,
                        StepNumber = i + 1,
                    });
                    attached.Add(e.TargetIp);
                }
                // If the target IS already attached elsewhere in the tree we
                // silently drop this duplicate edge; MVP tree layout can't
                // represent cross-links cleanly. The step numbering still
                // reflects creation order for the edges we do render.
            }

            return attacker;
        }

        // --- tree layout (left→right, subtree-centering) -----------------------

        // Place `node` at column X = `x`, then recursively place each child
        // one column further right (x + NodeW + HStep). Sibling children stack
        // vertically starting at `startY`, separated by VStep, and the parent
        // ends up vertically centered over the vertical span of its children.
        private static void LayoutTree(TreeNode node, int x, int startY)
        {
            if (node.Children.Count == 0)
            {
                node.SubtreeH = NodeH;
                node.X = x;
                node.Y = startY;
                return;
            }

            int childY = startY;
            foreach (var child in node.Children)
            {
                LayoutTree(child.Target, x + NodeW + HStep, childY);
                childY += child.Target.SubtreeH + VStep;
            }
            int totalH = (childY - VStep) - startY;
            node.SubtreeH = Math.Max(NodeH, totalH);
            node.X = x;
            node.Y = startY + (node.SubtreeH - NodeH) / 2;
        }

        private static int ComputeCanvasWidth(TreeNode node)
        {
            int max = node.X + NodeW;
            foreach (var c in node.Children)
                max = Math.Max(max, ComputeCanvasWidth(c.Target));
            return max;
        }

        // --- SVG parts ---------------------------------------------------------

        private static string Defs()
        {
            var sb = new StringBuilder();
            sb.Append("<defs>\n");
            // Per-technique arrowhead markers so each edge can carry its own
            // colour without breaking rasterisers that don't support
            // context-stroke.
            foreach (var colour in new[] { "#c026d3", "#dc2626", "#ea580c", "#0d9488", "#7c3aed", "#ca8a04", "#334155", "#111111" })
            {
                var id = "ap_arr_" + colour.TrimStart('#');
                sb.Append($"  <marker id=\"{id}\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"9\" markerHeight=\"9\" orient=\"auto\"><polygon points=\"0 0, 10 5, 0 10\" fill=\"{colour}\"/></marker>\n");
            }
            sb.Append("</defs>\n");
            return sb.ToString();
        }

        private static string ArrowMarker(string colour) => "ap_arr_" + colour.TrimStart('#');

        private static void DrawNodes(StringBuilder sb, TreeNode node)
        {
            DrawNode(sb, node);
            foreach (var c in node.Children)
                DrawNodes(sb, c.Target);
        }

        private static void DrawNode(StringBuilder sb, TreeNode n)
        {
            // Card background (rounded rect with subtle border)
            sb.Append(FormattableString.Invariant(
                $"<rect x=\"{n.X}\" y=\"{n.Y}\" width=\"{NodeW}\" height=\"{NodeH}\" rx=\"10\" ry=\"10\" fill=\"#ffffff\" stroke=\"#94a3b8\" stroke-width=\"1.2\"/>\n"));

            int iconX = n.X + IconInsetX;
            int iconY = n.Y + IconInsetY;
            if (n.IsAttacker)
                sb.Append(AttackerIcon(iconX, iconY));
            else if (n.IsWindows)
                sb.Append(WindowsIcon(iconX, iconY));
            else
                sb.Append(TuxIcon(iconX, iconY));

            // Label under the icon
            int labelY = n.Y + NodeH - 12;
            string label = n.IsAttacker ? "ATTACKER" : (n.Label ?? "");
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{n.X + NodeW / 2}\" y=\"{labelY}\" text-anchor=\"middle\" font-size=\"12\" font-weight=\"700\" fill=\"#111\">{XmlEscape(label)}</text>\n"));
        }

        private static void DrawEdges(StringBuilder sb, TreeNode node)
        {
            foreach (var c in node.Children)
            {
                DrawEdge(sb, node, c);
                DrawEdges(sb, c.Target);
            }
        }

        private static void DrawEdge(StringBuilder sb, TreeNode parent, TreeEdge edge)
        {
            var child = edge.Target;
            // Exit parent from right-middle, enter child at left-middle.
            int sx = parent.X + NodeW;
            int sy = parent.Y + NodeH / 2;
            int tx = child.X;
            int ty = child.Y + NodeH / 2;

            string colour = edge.Pivot == null ? "#334155" : TechniqueColour(edge.Pivot.Technique);
            string marker = ArrowMarker(colour);

            // Orthogonal S-path: right → up/down → right. For siblings placed
            // vertically off-axis we insert a small vertical jog through the
            // midpoint column so every arrow shares the same "channel" x.
            string path;
            int midX = (sx + tx) / 2;
            int r = CornerRadius;
            if (sy == ty)
            {
                // Straight horizontal — same row, no branch needed.
                path = FormattableString.Invariant($"M {sx} {sy} H {tx - 2}");
            }
            else
            {
                int dir = ty > sy ? 1 : -1;             // +1 = child sits below parent
                int seg1EndX = midX - r;
                int seg2StartY = sy + dir * r;
                int seg2EndY = ty - dir * r;
                int seg2StartX = midX + r;
                if (seg1EndX < sx + r) seg1EndX = sx + r;
                if (seg2StartX > tx - r) seg2StartX = tx - r;

                // Sweep flags for right-then-down vs right-then-up. In SVG's
                // y-down coord system, right→down is a clockwise (sweep=1)
                // turn, right→up is counterclockwise (sweep=0). Down→right and
                // up→right mirror.
                int sw1 = dir > 0 ? 1 : 0;   // right→down or right→up
                int sw2 = dir > 0 ? 0 : 1;   // down→right or up→right

                var pb = new StringBuilder();
                pb.Append(FormattableString.Invariant($"M {sx} {sy}"));
                pb.Append(FormattableString.Invariant($" H {seg1EndX}"));
                pb.Append(FormattableString.Invariant($" A {r} {r} 0 0 {sw1} {midX} {seg2StartY}"));
                pb.Append(FormattableString.Invariant($" V {seg2EndY}"));
                pb.Append(FormattableString.Invariant($" A {r} {r} 0 0 {sw2} {seg2StartX} {ty}"));
                pb.Append(FormattableString.Invariant($" H {tx - 2}"));
                path = pb.ToString();
            }
            sb.Append($"<path d=\"{path}\" fill=\"none\" stroke=\"{colour}\" stroke-width=\"2.4\" stroke-linecap=\"round\" stroke-linejoin=\"round\" marker-end=\"url(#{marker})\"/>\n");

            // Only the numbered badge lives on the arrow now — the technique
            // text and pivot label moved to the legend below the tree so the
            // graph stays visually calm. The badge sits at the child's y so
            // each branch's badge lands on its own row.
            int badgeX = midX;
            int badgeY = ty;
            sb.Append(BuildStepBadge(badgeX, badgeY, edge.StepNumber, colour));
        }

        // Pill sizing helper — figures out the actual pill width for a label
        // (respecting a maximum width) and returns the final text after any
        // ellipsis truncation. Kept separate from BuildLabelPillFixed so the
        // caller can lay out sibling groups symmetrically.
        private static (int pillW, int pillH, string label) MeasurePill(string label, int maxPillW)
        {
            const int fontSize = 13;
            const int padX = 10;
            const int padY = 5;
            const double charW = fontSize * 0.58;
            int pillH = fontSize + 2 * padY + 2;
            if (string.IsNullOrEmpty(label)) return (0, pillH, "");
            int maxChars = Math.Max(3, (int)Math.Floor((maxPillW - 2 * padX) / charW));
            if (label.Length > maxChars) label = label.Substring(0, maxChars - 1) + "…";
            int textW = (int)Math.Ceiling(label.Length * charW);
            int pillW = textW + 2 * padX;
            return (pillW, pillH, label);
        }

        private static string BuildLabelPillFixed(int leftX, int cy, string label, string colour, int pillW, int pillH)
        {
            const int fontSize = 13;
            const int padX = 10;
            int rx = pillH / 2;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<rect x=\"{leftX}\" y=\"{cy - pillH / 2}\" width=\"{pillW}\" height=\"{pillH}\" rx=\"{rx}\" ry=\"{rx}\" fill=\"#ffffff\" stroke=\"{colour}\" stroke-width=\"1.4\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{leftX + padX}\" y=\"{cy + fontSize / 3}\" text-anchor=\"start\" font-size=\"{fontSize}\" font-weight=\"700\" fill=\"{colour}\">{XmlEscape(label)}</text>\n"));
            return sb.ToString();
        }

        private static string BuildStepBadge(int cx, int cy, int step, string colour)
        {
            string text = step == 0 ? "★" : step.ToString(CultureInfo.InvariantCulture);
            int r = 13;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<circle cx=\"{cx}\" cy=\"{cy}\" r=\"{r}\" fill=\"{colour}\" stroke=\"#ffffff\" stroke-width=\"2\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{cx}\" y=\"{cy + 4}\" text-anchor=\"middle\" font-size=\"13\" font-weight=\"800\" fill=\"#ffffff\">{text}</text>\n"));
            return sb.ToString();
        }

        private static string BuildLabelPill(int leftX, int cy, string label, string colour, int maxPillW = int.MaxValue)
        {
            const int fontSize = 13;
            const int padX = 10;
            const int padY = 5;
            const double charW = fontSize * 0.58;
            // Fit-to-width: if the naive pill would spill past maxPillW,
            // truncate the label with an ellipsis so we stay inside the
            // arrow's horizontal segment and never draw over the child icon.
            int maxChars = Math.Max(4, (int)Math.Floor((maxPillW - 2 * padX) / charW));
            if (label.Length > maxChars) label = label.Substring(0, maxChars - 1) + "…";
            int textW = (int)Math.Ceiling(label.Length * charW);
            int pillW = textW + 2 * padX;
            int pillH = fontSize + 2 * padY + 2;
            int rx = pillH / 2;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<rect x=\"{leftX}\" y=\"{cy - pillH / 2}\" width=\"{pillW}\" height=\"{pillH}\" rx=\"{rx}\" ry=\"{rx}\" fill=\"#ffffff\" stroke=\"{colour}\" stroke-width=\"1.4\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{leftX + padX}\" y=\"{cy + fontSize / 3}\" text-anchor=\"start\" font-size=\"{fontSize}\" font-weight=\"700\" fill=\"{colour}\">{XmlEscape(label)}</text>\n"));
            return sb.ToString();
        }

        private static string FormatEdgeLabel(TreeEdge edge)
        {
            if (edge.Pivot == null) return "initial access";
            var pieces = new List<string>();
            if (!string.IsNullOrWhiteSpace(edge.Pivot.Technique) && edge.Pivot.Technique != "other")
                pieces.Add(edge.Pivot.Technique);
            if (!string.IsNullOrWhiteSpace(edge.Pivot.Label))
                pieces.Add(edge.Pivot.Label);
            return Ellipsize(string.Join(": ", pieces), 44);
        }

        private static string TechniqueColour(string t) => (t ?? "").ToLowerInvariant() switch
        {
            "creds"   => "#c026d3",
            "exploit" => "#dc2626",
            "rce"     => "#ea580c",
            "session" => "#0d9488",
            "relay"   => "#7c3aed",
            "phish"   => "#ca8a04",
            _         => "#334155",
        };

        // --- icons (reused visual language from TopologyRenderer) --------------

        // Base64-embedded Tux PNG in the 52x45 icon footprint, letterboxed so
        // the aspect ratio isn't squashed.
        private static string TuxIcon(int x, int y)
        {
            return FormattableString.Invariant(
                $"<image x=\"{x}\" y=\"{y}\" width=\"52\" height=\"45\" preserveAspectRatio=\"xMidYMid meet\" href=\"{TuxAsset.DataUrl}\"/>");
        }

        // Windows: the four-colour flag standalone (no monitor frame), sized
        // and positioned to visually balance Tux at the same 52x45 footprint.
        private static string WindowsIcon(int x, int y)
        {
            var sb = new StringBuilder();
            sb.Append($"<g transform=\"translate({x},{y})\">");
            // Slight vertical centring gap so the flag sits mid-cell
            sb.Append("<path d=\"M 6 8 L 25 5 L 25 22 L 6 24 Z\" fill=\"#f25022\"/>");
            sb.Append("<path d=\"M 27 5 L 47 3 L 47 22 L 27 22 Z\" fill=\"#7fba00\"/>");
            sb.Append("<path d=\"M 6 26 L 25 24 L 25 41 L 6 43 Z\" fill=\"#00a4ef\"/>");
            sb.Append("<path d=\"M 27 24 L 47 22 L 47 41 L 27 41 Z\" fill=\"#ffb900\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        private static string AttackerIcon(int x, int y)
        {
            var sb = new StringBuilder();
            sb.Append($"<g transform=\"translate({x},{y})\">");
            sb.Append("<rect x=\"0\" y=\"20\" width=\"52\" height=\"35\" rx=\"3\" fill=\"#111\" stroke=\"#000\" stroke-width=\"1.2\"/>");
            sb.Append("<rect x=\"3\" y=\"23\" width=\"46\" height=\"27\" fill=\"#1e293b\"/>");
            // Hood
            sb.Append("<path d=\"M 10 14 Q 10 -2 26 -2 Q 42 -2 42 14 L 42 30 L 10 30 Z\" fill=\"#111\" stroke=\"#111\"/>");
            // Eyes strip
            sb.Append("<rect x=\"18\" y=\"18\" width=\"16\" height=\"5\" fill=\"#e11d48\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        // --- helpers -----------------------------------------------------------

        private static readonly string[] _winKeywords = { "windows", "microsoft" };
        private static readonly string[] _linuxKeywords = {
            "linux", "ubuntu", "debian", "centos", "rhel", "redhat",
            "kali", "arch", "fedora", "suse", "alpine", "unix"
        };

        private static bool IsWindowsBox(Box b)
        {
            var os = (b.Os ?? "").ToLowerInvariant();
            var hn = (b.Hostname ?? "").ToLowerInvariant();
            if (_winKeywords.Any(k => os.Contains(k))) return true;
            if (_winKeywords.Any(k => hn.Contains(k))) return true;
            if (_linuxKeywords.Any(k => hn.Contains(k))) return false;
            if (hn.StartsWith("win") || hn.Contains("-win") || hn.Contains(" win")) return true;
            if (hn.StartsWith("dc") || hn.Contains("exchange") || hn.Contains("srv-win")) return true;
            return false;
        }

        private static string XmlEscape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("&", "&amp;").Replace("<", "&lt;")
                    .Replace(">", "&gt;").Replace("\"", "&quot;")
                    .Replace("'", "&apos;");
        }

        private static string Ellipsize(string s, int max) =>
            (s?.Length ?? 0) <= max ? (s ?? "") : s.Substring(0, max - 1) + "…";
    }
}
