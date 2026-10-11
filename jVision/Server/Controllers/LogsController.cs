using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using ClosedXML.Excel;
using jVision.Server.Data;
using jVision.Server.Hubs;
using jVision.Shared.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    [Authorize]
    public class LogsController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        public LogsController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        // GET /logs?operator=mustafa&source=zsh&since=2026-08-03T14:00:00Z&search=nmap&limit=500
        [HttpGet]
        public async Task<ActionResult<IEnumerable<LogEntry>>> Get(
            [FromQuery(Name = "operator")] string op = null,
            [FromQuery] string source = null,
            [FromQuery] DateTime? since = null,
            [FromQuery] string search = null,
            [FromQuery] int limit = 500)
        {
            if (limit <= 0 || limit > 5000) limit = 500;

            IQueryable<LogEntry> q = _context.LogEntry;
            if (!string.IsNullOrEmpty(op))     q = q.Where(l => l.Operator == op);
            if (!string.IsNullOrEmpty(source)) q = q.Where(l => l.Source == source);
            if (since.HasValue)                q = q.Where(l => l.Timestamp >= since.Value);
            if (!string.IsNullOrEmpty(search)) q = q.Where(l => EF.Functions.Like(l.Line, "%" + search + "%"));

            return await q.OrderByDescending(l => l.Timestamp).Take(limit).ToListAsync();
        }

        // GET /logs/operators -- for the filter dropdown in the UI.
        [HttpGet("operators")]
        public async Task<ActionResult<IEnumerable<string>>> Operators()
        {
            return await _context.LogEntry
                .Select(l => l.Operator)
                .Distinct()
                .OrderBy(o => o)
                .ToListAsync();
        }

        // POST /logs -- batch upload from the sync client. Server stamps the
        // operator name from the authenticated user, ignoring any value in the
        // payload (prevents impersonation via a mislabelled batch).
        [HttpPost]
        public async Task<IActionResult> Post([FromBody] List<LogEntry> entries)
        {
            if (entries == null || entries.Count == 0) return Ok(0);

            string op = User.Identity?.Name ?? "unknown";
            foreach (var e in entries)
            {
                e.Operator = op;
                if (e.Timestamp == default) e.Timestamp = DateTime.UtcNow;
                if (string.IsNullOrEmpty(e.Source)) e.Source = "unknown";
                if (e.Line == null) e.Line = "";
            }

            await _context.LogEntry.AddRangeAsync(entries);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.LogsAdded(entries.Count);
            return Ok(entries.Count);
        }

        // GET /logs/export -- one XLSX, one worksheet per operator, two columns:
        // A=bash (zsh), B=burp. Chronological, independent lists (bash and burp
        // rows don't line up by timestamp -- they're independent streams).
        //
        // Operator names are replaced with the source IP jVision last saw them
        // connect from (looked up in TeamIp). Falls back to "unknown-N" if we
        // never recorded an IP for that operator, so the export still shares
        // cleanly without leaking usernames.
        [HttpGet("export")]
        public async Task<IActionResult> Export()
        {
            var all = await _context.LogEntry
                .OrderBy(l => l.Operator).ThenBy(l => l.Timestamp)
                .ToListAsync();

            using var wb = new XLWorkbook();

            if (all.Count == 0)
            {
                var empty = wb.Worksheets.Add("logs");
                empty.Cell(1, 1).Value = "no logs";
            }
            else
            {
                var distinctOps = all
                    .Select(l => l.Operator ?? "unknown")
                    .Distinct()
                    .OrderBy(o => o, StringComparer.OrdinalIgnoreCase)
                    .ToList();

                // Most-recent IP per operator (case-insensitive on username to
                // match how LogEntry.Operator is stored across clients).
                // GroupBy + inner OrderByDescending.First() isn't translatable
                // by EF Core 5 against SQLite, so materialise the TeamIp rows
                // first (tiny table: one row per operator) and reduce in memory.
                var latestIpByOp = (await _context.TeamIp.ToListAsync())
                    .GroupBy(t => t.Operator)
                    .Select(g => new
                    {
                        Op = g.Key,
                        Ip = g.OrderByDescending(t => t.LastSeen).First().Ip,
                    })
                    .ToList();
                var ipMap = latestIpByOp.ToDictionary(
                    x => x.Op ?? "",
                    x => x.Ip,
                    StringComparer.OrdinalIgnoreCase);

                var opToAlias = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                int unknownIdx = 0;
                foreach (var op in distinctOps)
                {
                    if (ipMap.TryGetValue(op, out var ip) && !string.IsNullOrWhiteSpace(ip))
                        opToAlias[op] = ip;
                    else
                        opToAlias[op] = $"unknown-{++unknownIdx}";
                }

                foreach (var opGroup in all.GroupBy(l => l.Operator ?? "unknown"))
                {
                    var alias = opToAlias[opGroup.Key];
                    var ws = wb.Worksheets.Add(SafeSheetName(alias, wb));
                    ws.Cell(1, 1).Value = "bash";
                    ws.Cell(1, 2).Value = "burp";
                    ws.Row(1).Style.Font.Bold = true;

                    var bash = opGroup.Where(l => l.Source == "zsh").ToList();
                    var burp = opGroup.Where(l => l.Source == "burp").ToList();

                    for (int i = 0; i < bash.Count; i++)
                        ws.Cell(i + 2, 1).Value = ScrubLine(FormatLine(bash[i]), opToAlias);
                    for (int i = 0; i < burp.Count; i++)
                        ws.Cell(i + 2, 2).Value = ScrubLine(FormatLine(burp[i]), opToAlias);

                    // AdjustToContents() calls into System.Drawing to measure
                    // text width, which needs libgdiplus at runtime -- the
                    // aspnet:5.0 base image doesn't have it. Fixed widths avoid
                    // the extra apt dependency; user can double-click the
                    // column edge in Excel to auto-fit.
                    ws.Column(1).Width = 90;
                    ws.Column(2).Width = 90;
                    ws.SheetView.FreezeRows(1);
                }
            }

            using var ms = new MemoryStream();
            wb.SaveAs(ms);
            var name = $"jvision-logs-{DateTime.UtcNow:yyyy-MM-dd-HHmm}.xlsx";
            return File(ms.ToArray(),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                name);
        }

        // GET /logs/export.csv -- flat CSV: operator, timestamp, source, line.
        // Same alias + scrub pipeline as the XLSX export so the two files are
        // interchangeable for sharing.
        [HttpGet("export.csv")]
        public async Task<IActionResult> ExportCsv()
        {
            var all = await _context.LogEntry
                .OrderBy(l => l.Operator).ThenBy(l => l.Timestamp)
                .ToListAsync();

            var opToAlias = await BuildAliasMap(all);

            var sb = new StringBuilder();
            sb.Append("operator,timestamp,source,line\n");
            foreach (var l in all)
            {
                var opKey = l.Operator ?? "unknown";
                var alias = opToAlias.TryGetValue(opKey, out var a) ? a : opKey;
                var ts = l.Timestamp.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
                var line = ScrubLine(l.Line ?? "", opToAlias);
                sb.Append(CsvField(alias)).Append(',')
                  .Append(CsvField(ts)).Append(',')
                  .Append(CsvField(l.Source ?? "")).Append(',')
                  .Append(CsvField(line)).Append('\n');
            }

            var bytes = Encoding.UTF8.GetPreamble()
                .Concat(Encoding.UTF8.GetBytes(sb.ToString()))
                .ToArray();
            var name = $"jvision-logs-{DateTime.UtcNow:yyyy-MM-dd-HHmm}.csv";
            return File(bytes, "text/csv", name);
        }

        private async Task<Dictionary<string, string>> BuildAliasMap(List<LogEntry> all)
        {
            var distinctOps = all
                .Select(l => l.Operator ?? "unknown")
                .Distinct()
                .OrderBy(o => o, StringComparer.OrdinalIgnoreCase)
                .ToList();

            var latestIpByOp = (await _context.TeamIp.ToListAsync())
                .GroupBy(t => t.Operator)
                .Select(g => new
                {
                    Op = g.Key,
                    Ip = g.OrderByDescending(t => t.LastSeen).First().Ip,
                })
                .ToList();
            var ipMap = latestIpByOp.ToDictionary(
                x => x.Op ?? "",
                x => x.Ip,
                StringComparer.OrdinalIgnoreCase);

            var opToAlias = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            int unknownIdx = 0;
            foreach (var op in distinctOps)
            {
                if (ipMap.TryGetValue(op, out var ip) && !string.IsNullOrWhiteSpace(ip))
                    opToAlias[op] = ip;
                else
                    opToAlias[op] = $"unknown-{++unknownIdx}";
            }
            return opToAlias;
        }

        private static string CsvField(string s)
        {
            if (s == null) return "";
            if (s.IndexOfAny(new[] { ',', '"', '\n', '\r' }) < 0) return s;
            return "\"" + s.Replace("\"", "\"\"") + "\"";
        }

        private static string FormatLine(LogEntry l) =>
            $"[{l.Timestamp.ToLocalTime():yyyy-MM-dd HH:mm:ss}] {l.Line}";

        // Rewrite any occurrence of an operator's real name inside a log line
        // to its member-alias. Word-boundary match so "root" doesn't rewrite
        // "root@host" partially -- we want a whole-token replacement. Case-
        // insensitive because Windows tools uppercase user names inconsistently.
        private static string ScrubLine(string s, Dictionary<string, string> opToAlias)
        {
            if (string.IsNullOrEmpty(s)) return s;
            foreach (var kv in opToAlias)
            {
                if (string.IsNullOrEmpty(kv.Key)) continue;
                s = Regex.Replace(s, @"\b" + Regex.Escape(kv.Key) + @"\b",
                                  kv.Value, RegexOptions.IgnoreCase);
            }
            return s;
        }

        // Excel: sheet names <=31 chars, cannot contain \ / ? * [ ] :, and must
        // be unique per workbook (case-insensitive).
        private static readonly Regex _sheetBad = new Regex(@"[\\/\?\*\[\]:]");
        private static string SafeSheetName(string raw, XLWorkbook wb)
        {
            var cleaned = _sheetBad.Replace(raw ?? "", "_").Trim();
            if (string.IsNullOrEmpty(cleaned)) cleaned = "unknown";
            if (cleaned.Length > 31) cleaned = cleaned.Substring(0, 31);

            var candidate = cleaned;
            int n = 2;
            while (wb.Worksheets.Any(w => string.Equals(w.Name, candidate, StringComparison.OrdinalIgnoreCase)))
            {
                var suffix = $"~{n++}";
                var trimTo = Math.Max(1, 31 - suffix.Length);
                candidate = cleaned.Substring(0, Math.Min(cleaned.Length, trimTo)) + suffix;
            }
            return candidate;
        }
    }
}
