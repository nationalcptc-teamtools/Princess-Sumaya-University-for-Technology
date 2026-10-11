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
        // the same column. Vertical spacing is wide so branches never overlap
        // and their arrows never cross.
        // Dimensions are tuned so a fan-out of 8-10 sibling branches (typical
        // for a CPTC engagement narrative) still fits a landscape report page
        // rather than stretching into a one-column-wide strip. Increase them
        // again if you need bigger badges/icons for a poster print.
        private const int NodeW = 128;
        // 100 (not 84) to leave room for a second label line under the IP for
        // the Box.Domain FQDN — same two-line layout the topology renderer uses.
        private const int NodeH = 100;
        private const int HStep = 150;   // horizontal spacing between hop levels
        private const int VStep = 24;    // vertical spacing between sibling branches
        private const int PadX = 40;
        private const int PadY = 28;     // top/bottom breathing room around the tree
        private const int MinCanvasW = 720;
        private const int MinCanvasH = 220;

        private const int IconInsetX = (NodeW - 48) / 2;
        private const int IconInsetY = 8;
        private const int IconSize = 48;
        private const int CornerRadius = 10;

        // Symbols legend box (top-right of the canvas, sitting in the empty
        // space beside the centered kill-chain tree).
        private const int SymbolLegendW = 260;
        private const int SymbolLegendH = 220;
        private const int SymbolLegendMarginX = 60;
        private const int SymbolLegendMarginY = 30;
        private const int SymbolBadgeVGap = 26;   // px above each arrow badge where the shape marker sits
        private const int LegendGutter = 40;      // horizontal gap between the tree and the legend column

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

            // Walk the tree once to assign the display label ("★", "1", "A",
            // "3", ...) and path id to every edge. This drives the badges on
            // the arrows. The per-edge narrative legend was removed, so path
            // ids no longer feed a legend section — labels still exist purely
            // for the badges.
            AssignLabels(tree);

            // Canvas has to be tall enough for either the tree or the symbol
            // legend riding along its top-right corner. Narrative panel was
            // dropped — the diagram is the whole export.
            int canvasH = Math.Max(MinCanvasH, tree.SubtreeH + 2 * PadY);
            canvasH = Math.Max(canvasH, SymbolLegendH + 2 * PadY);

            // Tree span (leftmost X to rightmost X + NodeW) as laid out; we'll
            // shift every node so this span sits centered inside a left column
            // that excludes the legend, keeping tree + legend from colliding
            // however tall the fan-out gets.
            int rawTreeSpan = ComputeCanvasWidth(tree) - PadX;   // from attacker.left..deepest.right
            int canvasW = Math.Max(MinCanvasW, PadX + rawTreeSpan + LegendGutter + SymbolLegendW + PadX);
            canvasW = Math.Max(canvasW, 1400);   // report-friendly minimum width

            // Left column ends where the legend column begins.
            int treeAreaW = canvasW - SymbolLegendW - LegendGutter - 2 * PadX;
            int centerShift = (treeAreaW - rawTreeSpan) / 2;
            ShiftTree(tree, centerShift, 0);

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

            // Symbol legend rides in the top-right column, vertically centered
            // against the tree so the eye lands on it naturally.
            int legendX = canvasW - SymbolLegendW - PadX;
            int legendY = Math.Max(PadY, (canvasH - SymbolLegendH) / 2);
            DrawSymbolLegend(sb, legendX, legendY);

            sb.Append("</svg>\n");
            return Encoding.UTF8.GetBytes(sb.ToString());
        }

        // Recursive X/Y shift used to center the laid-out tree inside the
        // canvas after LayoutTree has assigned relative positions.
        private static void ShiftTree(TreeNode node, int dx, int dy)
        {
            node.X += dx;
            node.Y += dy;
            foreach (var e in node.Children) ShiftTree(e.Target, dx, dy);
        }

        // Boxed "shape → technique" key, positioned in the bottom-right of the
        // canvas. Matches the shapes drawn above each arrow badge.
        private static void DrawSymbolLegend(StringBuilder sb, int x, int y)
        {
            sb.Append(FormattableString.Invariant(
                $"<rect x=\"{x}\" y=\"{y}\" width=\"{SymbolLegendW}\" height=\"{SymbolLegendH}\" rx=\"10\" ry=\"10\" fill=\"#ffffff\" stroke=\"#94a3b8\" stroke-width=\"1.2\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{x + 18}\" y=\"{y + 30}\" font-size=\"17\" font-weight=\"700\" fill=\"#111\">Techniques (symbol)</text>\n"));

            string[] techs = { "creds", "exploit", "session", "relay", "rce", "phish" };
            int rowY = y + 60;
            foreach (var t in techs)
            {
                string col = TechniqueColour(t);
                sb.Append(TechniqueSymbol(t, x + 34, rowY, col));
                sb.Append(FormattableString.Invariant(
                    $"<text x=\"{x + 58}\" y=\"{rowY + 6}\" font-size=\"16\" font-weight=\"600\" fill=\"{col}\">{t}</text>\n"));
                rowY += 26;
            }
        }

        // --- tree construction -------------------------------------------------

        private class TreeNode
        {
            public string Ip;
            public string Label;         // display text (IP or "Attacker")
            public string Domain;        // FQDN shown as a second line under the IP
            public bool IsAttacker;
            public bool IsWindows;
            public bool IsCloud;         // hosted-cloud endpoint (S3 / AWS / etc.)
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
            // Display label shown inside the arrow badge: "★" for initial
            // access, "1"/"2"/... for the shared prefix, "A"/"B"/... for the
            // first edge into each branch, then per-branch numbering resumes.
            public string DisplayLabel;
            // "shared" until the first branch, then the branch letter ("A",
            // "B", ...) inherited by every edge downstream of that branch.
            public string PathId;
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
                Box b = null;
                boxByIp.TryGetValue(ip, out b);
                n = new TreeNode
                {
                    Ip = ip,
                    Label = ip,
                    Domain = b?.Domain,
                    IsWindows = b != null && IsWindowsBox(b),
                    IsCloud = b != null && IsCloudBox(b),
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

        // --- step labelling ----------------------------------------------------
        //
        // Attacker→foothold edges get "★". The first branch node (source with
        // >1 children) turns its children's edges into letter labels A, B, C…
        // After the branch, each subtree continues numbering from
        // (sharedLen + 2) — so the very first "path A" step and the very first
        // "path B" step both read the same number, giving each branch its own
        // clean sequence. Nested branches (rare) fall back to a compound path
        // id like "A.a", "A.b" so their edges still read distinctly.
        private static void AssignLabels(TreeNode attacker)
        {
            foreach (var e in attacker.Children)
            {
                e.DisplayLabel = "★";
                e.PathId = "shared";
            }
            int sharedCount = 0;
            foreach (var e in attacker.Children)
                WalkShared(e.Target, ref sharedCount);
        }

        private static void WalkShared(TreeNode node, ref int sharedCount)
        {
            if (node.Children.Count == 0) return;
            if (node.Children.Count == 1)
            {
                var edge = node.Children[0];
                sharedCount++;
                edge.DisplayLabel = sharedCount.ToString(CultureInfo.InvariantCulture);
                edge.PathId = "shared";
                WalkShared(edge.Target, ref sharedCount);
                return;
            }
            // Branch! Sibling edges become "A", "B", ... and each subtree
            // numbers from sharedCount+2 onward.
            int subStart = sharedCount + 2;
            for (int i = 0; i < node.Children.Count; i++)
            {
                var edge = node.Children[i];
                string letter = ((char)('A' + i)).ToString();
                edge.DisplayLabel = letter;
                edge.PathId = letter;
                WalkBranch(edge.Target, subStart, letter);
            }
        }

        private static void WalkBranch(TreeNode node, int nextStep, string pathId)
        {
            if (node.Children.Count == 0) return;
            if (node.Children.Count == 1)
            {
                var edge = node.Children[0];
                edge.DisplayLabel = nextStep.ToString(CultureInfo.InvariantCulture);
                edge.PathId = pathId;
                WalkBranch(edge.Target, nextStep + 1, pathId);
                return;
            }
            // Nested branch — use lower-case letter suffix so nobody confuses
            // "A.a" with the top-level "A" branch.
            for (int i = 0; i < node.Children.Count; i++)
            {
                var edge = node.Children[i];
                string subId = pathId + "." + (char)('a' + i);
                edge.DisplayLabel = subId;
                edge.PathId = subId;
                WalkBranch(edge.Target, nextStep + 1, subId);
            }
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
                $"<rect x=\"{n.X}\" y=\"{n.Y}\" width=\"{NodeW}\" height=\"{NodeH}\" rx=\"{CornerRadius}\" ry=\"{CornerRadius}\" fill=\"#ffffff\" stroke=\"#94a3b8\" stroke-width=\"1.4\"/>\n"));

            int iconX = n.X + IconInsetX;
            int iconY = n.Y + IconInsetY;
            if (n.IsAttacker)
                sb.Append(AttackerIcon(iconX, iconY));
            else if (n.IsCloud)
                sb.Append(CloudIcon(iconX, iconY));
            else if (n.IsWindows)
                sb.Append(WindowsIcon(iconX, iconY));
            else
                sb.Append(TuxIcon(iconX, iconY));

            // IP (or "ATTACKER") on the first line, Box.Domain FQDN on the
            // second — mirrors the two-line label the topology renderer draws.
            int labelY = n.Y + NodeH - 24;
            string label = n.IsAttacker ? "ATTACKER" : (n.Label ?? "");
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{n.X + NodeW / 2}\" y=\"{labelY}\" text-anchor=\"middle\" font-size=\"12\" font-weight=\"700\" fill=\"#111\">{XmlEscape(label)}</text>\n"));

            var domain = (n.Domain ?? "").Trim();
            if (!n.IsAttacker && domain.Length > 0)
            {
                sb.Append(FormattableString.Invariant(
                    $"<text x=\"{n.X + NodeW / 2}\" y=\"{labelY + 14}\" text-anchor=\"middle\" font-size=\"10\" fill=\"#111\">{XmlEscape(domain)}</text>\n"));
            }
        }

        private static void DrawEdges(StringBuilder sb, TreeNode node)
        {
            if (node.Children.Count == 1)
            {
                DrawSingleEdge(sb, node, node.Children[0]);
            }
            else if (node.Children.Count > 1)
            {
                DrawFanOut(sb, node);
            }
            foreach (var c in node.Children)
                DrawEdges(sb, c.Target);
        }

        // Neutral colour for the shared parent→trunk stub of a fanout. The
        // colored branches to each child overlay it starting at the trunk.
        private const string TrunkColour = "#94a3b8";

        // Single-child edge — clean S-path from parent's right-middle to
        // child's left-middle. No siblings means no channel contention.
        private static void DrawSingleEdge(StringBuilder sb, TreeNode parent, TreeEdge edge)
        {
            var child = edge.Target;
            int sx = parent.X + NodeW;
            int sy = parent.Y + NodeH / 2;
            int tx = child.X;
            int ty = child.Y + NodeH / 2;

            string colour = edge.Pivot == null ? "#334155" : TechniqueColour(edge.Pivot.Technique);
            string marker = ArrowMarker(colour);
            int r = CornerRadius;
            int midX = (sx + tx) / 2;

            string path;
            if (sy == ty)
            {
                path = FormattableString.Invariant($"M {sx} {sy} H {tx - 2}");
            }
            else
            {
                int dir = ty > sy ? 1 : -1;
                int seg1EndX = Math.Max(sx + r, midX - r);
                int seg2StartY = sy + dir * r;
                int seg2EndY = ty - dir * r;
                int seg2StartX = Math.Min(tx - r, midX + r);
                int sw1 = dir > 0 ? 1 : 0;
                int sw2 = dir > 0 ? 0 : 1;

                path = FormattableString.Invariant(
                    $"M {sx} {sy} H {seg1EndX} A {r} {r} 0 0 {sw1} {midX} {seg2StartY} V {seg2EndY} A {r} {r} 0 0 {sw2} {seg2StartX} {ty} H {tx - 2}");
            }
            sb.Append($"<path d=\"{path}\" fill=\"none\" stroke=\"{colour}\" stroke-width=\"3.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" marker-end=\"url(#{marker})\"/>\n");

            int badgeX = midX;
            int badgeY = ty;
            sb.Append(BuildStepBadge(badgeX, badgeY, edge.DisplayLabel ?? edge.StepNumber.ToString(CultureInfo.InvariantCulture), colour));
            sb.Append(TechniqueSymbol(edge.Pivot?.Technique, badgeX, badgeY - SymbolBadgeVGap, colour));
        }

        // Multi-child fanout: single vertical trunk shared by all siblings
        // (drawn once in a neutral colour), then each sibling gets its own
        // horizontal branch off the trunk at the child's y-level, colored by
        // technique. This eliminates the "middle sibling's straight line runs
        // through the outer siblings' vertical channels" crossing that the
        // per-sibling S-path routing produced.
        private static void DrawFanOut(StringBuilder sb, TreeNode parent)
        {
            int sx = parent.X + NodeW;
            int sy = parent.Y + NodeH / 2;
            // All siblings share the same X (LayoutTree places them all one
            // column further right), so any child's X works as the trunk-to-
            // child gap reference.
            int childX = parent.Children[0].Target.X;
            // Trunk sits ~40% of the way from parent to the child column, so
            // the horizontal branches into each child have room for a badge.
            int trunkX = sx + (childX - sx) * 4 / 10;

            // Trunk vertical spans from top-most to bottom-most child y, and
            // is extended to include parent's y so the parent stub connects
            // cleanly at the T-junction.
            int topY = int.MaxValue, botY = int.MinValue;
            foreach (var c in parent.Children)
            {
                int cy = c.Target.Y + NodeH / 2;
                if (cy < topY) topY = cy;
                if (cy > botY) botY = cy;
            }
            int trunkTop = Math.Min(sy, topY);
            int trunkBot = Math.Max(sy, botY);

            // Neutral trunk: parent stub + vertical spine. Rendered as a
            // single path so the T-junction stays crisp.
            sb.Append(FormattableString.Invariant(
                $"<path d=\"M {sx} {sy} H {trunkX} M {trunkX} {trunkTop} V {trunkBot}\" fill=\"none\" stroke=\"{TrunkColour}\" stroke-width=\"2.8\" stroke-linecap=\"round\"/>\n"));

            // One coloured branch per child, off the trunk at the child's y.
            foreach (var edge in parent.Children)
            {
                var child = edge.Target;
                int tx = child.X;
                int ty = child.Y + NodeH / 2;
                string colour = edge.Pivot == null ? "#334155" : TechniqueColour(edge.Pivot.Technique);
                string marker = ArrowMarker(colour);

                sb.Append(FormattableString.Invariant(
                    $"<path d=\"M {trunkX} {ty} H {tx - 2}\" fill=\"none\" stroke=\"{colour}\" stroke-width=\"3.2\" stroke-linecap=\"round\" marker-end=\"url(#{marker})\"/>\n"));

                // Small coloured tap where the branch leaves the trunk so
                // each branch's technique colour reads at the junction too.
                sb.Append(FormattableString.Invariant(
                    $"<circle cx=\"{trunkX}\" cy=\"{ty}\" r=\"5\" fill=\"{colour}\"/>\n"));

                int badgeX = (trunkX + tx) / 2;
                int badgeY = ty;
                sb.Append(BuildStepBadge(badgeX, badgeY, edge.DisplayLabel ?? edge.StepNumber.ToString(CultureInfo.InvariantCulture), colour));
                sb.Append(TechniqueSymbol(edge.Pivot?.Technique, badgeX, badgeY - SymbolBadgeVGap, colour));
            }
        }

        private static string BuildStepBadge(int cx, int cy, string label, string colour)
        {
            // Compact labels ("A", "3") use the standard font; wider labels
            // ("A.a") shrink one step so they don't clip the badge outline.
            int r = 16;
            int fontSize = (label?.Length ?? 1) >= 3 ? 12 : 16;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant(
                $"<circle cx=\"{cx}\" cy=\"{cy}\" r=\"{r}\" fill=\"{colour}\" stroke=\"#ffffff\" stroke-width=\"3\"/>\n"));
            sb.Append(FormattableString.Invariant(
                $"<text x=\"{cx}\" y=\"{cy + fontSize / 3}\" text-anchor=\"middle\" font-size=\"{fontSize}\" font-weight=\"800\" fill=\"#ffffff\">{XmlEscape(label ?? "")}</text>\n"));
            return sb.ToString();
        }

        // Distinct silhouette per technique so colour-blind readers can tell
        // arrows apart even in monochrome. Called both above each arrow badge
        // and inside the "Techniques (symbol)" legend box.
        private static string TechniqueSymbol(string technique, int x, int y, string colour)
        {
            switch ((technique ?? "").ToLowerInvariant())
            {
                case "creds":
                    return FormattableString.Invariant($"<path transform=\"translate({x},{y})\" d=\"M 0 -11 L 11 0 L 0 11 L -11 0 Z\" fill=\"{colour}\"/>");
                case "exploit":
                    return FormattableString.Invariant($"<path transform=\"translate({x},{y})\" d=\"M 0 -11 L 11 9 L -11 9 Z\" fill=\"{colour}\"/>");
                case "session":
                    return FormattableString.Invariant($"<circle cx=\"{x}\" cy=\"{y}\" r=\"9\" fill=\"{colour}\"/>");
                case "relay":
                    return FormattableString.Invariant($"<rect x=\"{x - 9}\" y=\"{y - 9}\" width=\"18\" height=\"18\" fill=\"{colour}\"/>");
                case "rce":
                    return FormattableString.Invariant($"<line x1=\"{x - 9}\" y1=\"{y - 9}\" x2=\"{x + 9}\" y2=\"{y + 9}\" stroke=\"{colour}\" stroke-width=\"3.6\" stroke-linecap=\"round\"/>")
                         + FormattableString.Invariant($"<line x1=\"{x + 9}\" y1=\"{y - 9}\" x2=\"{x - 9}\" y2=\"{y + 9}\" stroke=\"{colour}\" stroke-width=\"3.6\" stroke-linecap=\"round\"/>");
                case "phish":
                    return FormattableString.Invariant($"<path transform=\"translate({x},{y})\" d=\"M -9 -5 L 0 -11 L 9 -5 L 9 5 L 0 11 L -9 5 Z\" fill=\"{colour}\"/>");
                default:
                    return "";
            }
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

        // Base64-embedded Tux PNG scaled to the IconSize footprint (68x60),
        // letterboxed so the aspect ratio isn't squashed.
        private static string TuxIcon(int x, int y)
        {
            return FormattableString.Invariant(
                $"<image x=\"{x}\" y=\"{y}\" width=\"{IconSize}\" height=\"{IconSize - 8}\" preserveAspectRatio=\"xMidYMid meet\" href=\"{TuxAsset.DataUrl}\"/>");
        }

        // Windows: the four-colour flag standalone (no monitor frame), scaled
        // via SVG transform so it matches Tux's footprint.
        private static string WindowsIcon(int x, int y)
        {
            // The tile artwork below is authored for a 52-unit box; scale to
            // IconSize so it grows with the rest of the diagram.
            double scale = IconSize / 52.0;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant($"<g transform=\"translate({x},{y}) scale({scale:0.###})\">"));
            sb.Append("<path d=\"M 6 8 L 25 5 L 25 22 L 6 24 Z\" fill=\"#f25022\"/>");
            sb.Append("<path d=\"M 27 5 L 47 3 L 47 22 L 27 22 Z\" fill=\"#7fba00\"/>");
            sb.Append("<path d=\"M 6 26 L 25 24 L 25 41 L 6 43 Z\" fill=\"#00a4ef\"/>");
            sb.Append("<path d=\"M 27 24 L 47 22 L 47 41 L 27 41 Z\" fill=\"#ffb900\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        // Soft cyan cloud silhouette used for boxes tagged as S3/AWS/hosted-
        // cloud endpoints. Scaled to the same 52-unit design box as the other
        // icons so it lines up with the Tux/Windows drawings.
        private static string CloudIcon(int x, int y)
        {
            double scale = IconSize / 52.0;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant($"<g transform=\"translate({x},{y}) scale({scale:0.###})\">"));
            sb.Append("<path d=\"M 8 40 Q -2 40 -2 30 Q -2 20 10 20 Q 10 6 24 6 Q 38 6 40 20 Q 52 20 52 30 Q 52 40 40 40 Z\" fill=\"#bae6fd\" stroke=\"#0369a1\" stroke-width=\"1.8\" stroke-linejoin=\"round\"/>");
            sb.Append("<ellipse cx=\"16\" cy=\"26\" rx=\"5\" ry=\"3\" fill=\"#e0f2fe\" stroke=\"none\"/>");
            sb.Append("</g>");
            return sb.ToString();
        }

        private static string AttackerIcon(int x, int y)
        {
            double scale = IconSize / 52.0;
            var sb = new StringBuilder();
            sb.Append(FormattableString.Invariant($"<g transform=\"translate({x},{y}) scale({scale:0.###})\">"));
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

        private static readonly string[] _cloudKeywords = { "cloud", "aws", "azure", "gcp", "s3" };

        // Any box whose hostname OR domain mentions a cloud provider / bucket
        // gets the cloud icon instead of Tux — the attack story often pivots
        // through S3 buckets and it's useful to see that visually.
        private static bool IsCloudBox(Box b)
        {
            var hn = (b.Hostname ?? "").ToLowerInvariant();
            var dm = (b.Domain ?? "").ToLowerInvariant();
            return _cloudKeywords.Any(k => hn.Contains(k) || dm.Contains(k));
        }

        private static string XmlEscape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("&", "&amp;").Replace("<", "&lt;")
                    .Replace(">", "&gt;").Replace("\"", "&quot;")
                    .Replace("'", "&apos;");
        }

    }
}
