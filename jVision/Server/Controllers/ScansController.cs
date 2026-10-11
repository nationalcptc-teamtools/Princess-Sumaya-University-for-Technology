using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Xml.Linq;
using jVision.Server.Data;
using jVision.Server.Hubs;
using jVision.Server.Models;
using jVision.Shared.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    [Authorize]
    public class ScansController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        // 100 MB. Full-p- scans across a big estate can produce ~10-30 MB
        // XMLs; leave headroom rather than DoS the team by rejecting one at
        // hour 6 when everyone's uploading their manual scans.
        private const long MaxUploadBytes = 100L * 1024 * 1024;

        public ScansController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<ScanUpload>>> List()
        {
            return await _context.ScanUpload
                .OrderByDescending(s => s.UploadedAt)
                .Select(s => new ScanUpload
                {
                    ScanUploadId = s.ScanUploadId,
                    FileName = s.FileName,
                    Uploader = s.Uploader,
                    Note = s.Note,
                    UploadedAt = s.UploadedAt,
                    SizeBytes = s.SizeBytes,
                    // StoredPath intentionally omitted from list responses.
                }).ToListAsync();
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Download(int id)
        {
            var s = await _context.ScanUpload.FindAsync(id);
            if (s == null) return NotFound();
            if (!System.IO.File.Exists(s.StoredPath)) return NotFound("stored file missing");
            var stream = System.IO.File.OpenRead(s.StoredPath);
            return File(stream, "application/xml", s.FileName);
        }

        // GET /scans/for-ip/{ip} -- rehydrates the per-host slices for the
        // Home-row "Uploaded" popup. Newest upload first so the freshest scan
        // shows up on top.
        [HttpGet("for-ip/{ip}")]
        public async Task<ActionResult<IEnumerable<UploadedScanView>>> ForIp(string ip)
        {
            var rows = await (from h in _context.UploadedScanHost
                              join u in _context.ScanUpload on h.ScanUploadId equals u.ScanUploadId
                              where h.Ip == ip
                              orderby u.UploadedAt descending
                              select new { h, u }).ToListAsync();

            var views = new List<UploadedScanView>();
            foreach (var r in rows)
            {
                List<ServiceDTO> services = null;
                if (!string.IsNullOrEmpty(r.h.ServicesJson))
                {
                    try { services = JsonSerializer.Deserialize<List<ServiceDTO>>(r.h.ServicesJson); }
                    catch { services = new List<ServiceDTO>(); }
                }
                views.Add(new UploadedScanView
                {
                    ScanUploadId = r.h.ScanUploadId,
                    FileName = r.u.FileName,
                    Uploader = r.u.Uploader,
                    UploadedAt = r.u.UploadedAt,
                    Note = r.u.Note,
                    Ip = r.h.Ip,
                    Hostname = r.h.Hostname,
                    Services = services ?? new List<ServiceDTO>(),
                });
            }
            return views;
        }

        [HttpPost]
        [DisableRequestSizeLimit]
        public async Task<ActionResult<ScanUpload>> Upload(
            [FromForm] IFormFile file,
            [FromForm] string note,
            [FromForm] bool importToHome = false)
        {
            if (file == null || file.Length == 0) return BadRequest("no file");
            if (file.Length > MaxUploadBytes) return BadRequest("file too large");

            var dir = Path.Combine(Directory.GetCurrentDirectory(), "Scans");
            Directory.CreateDirectory(dir);

            var safeOriginal = Path.GetFileName(file.FileName);
            var storedName = Guid.NewGuid().ToString("N") + ".xml";
            var storedPath = Path.Combine(dir, storedName);

            using (var fs = new FileStream(storedPath, FileMode.CreateNew))
            {
                await file.CopyToAsync(fs);
            }

            var record = new ScanUpload
            {
                FileName = safeOriginal,
                Uploader = User.Identity?.Name ?? "unknown",
                Note = note,
                UploadedAt = DateTime.UtcNow,
                SizeBytes = file.Length,
                StoredPath = storedPath,
            };
            _context.ScanUpload.Add(record);
            await _context.SaveChangesAsync();

            bool anyNewBoxes = false;
            if (importToHome)
            {
                try
                {
                    anyNewBoxes = await ImportXmlToHome(storedPath, record.ScanUploadId);
                }
                catch (Exception e)
                {
                    // Storing the raw file already succeeded, so don't fail the
                    // whole upload -- just log and return a partial-success.
                    Console.WriteLine("[ScansController] import failed: " + e);
                }
            }

            var broadcast = new ScanUpload
            {
                ScanUploadId = record.ScanUploadId,
                FileName = record.FileName,
                Uploader = record.Uploader,
                Note = record.Note,
                UploadedAt = record.UploadedAt,
                SizeBytes = record.SizeBytes,
            };
            await _hubContext.Clients.All.ScanUploaded(broadcast);
            if (anyNewBoxes) await _hubContext.Clients.All.BoxAdded();
            return Ok(broadcast);
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var s = await _context.ScanUpload.FindAsync(id);
            if (s == null) return NotFound();
            if (!string.Equals(s.Uploader, User.Identity?.Name, StringComparison.Ordinal))
                return Forbid();
            try { System.IO.File.Delete(s.StoredPath); } catch { }

            // No FK cascade set up on UploadedScanHost -> clean it manually so
            // stale rows don't hang around after the parent scan is gone.
            var slices = _context.UploadedScanHost.Where(h => h.ScanUploadId == id);
            _context.UploadedScanHost.RemoveRange(slices);
            _context.ScanUpload.Remove(s);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.ScanDeleted(id);
            return NoContent();
        }

        // -- XML import ------------------------------------------------------

        // Returns true if any brand-new Box rows were created.
        private async Task<bool> ImportXmlToHome(string xmlPath, int scanUploadId)
        {
            var doc = XDocument.Load(xmlPath);
            var hosts = doc.Descendants("host");
            bool createdBox = false;

            foreach (var host in hosts)
            {
                // Prefer ipv4 address; nmap XML can list multiple <address>
                // (e.g. mac + ipv4). Skip the host entirely if no IP.
                var ip = host.Elements("address")
                             .FirstOrDefault(a => (string)a.Attribute("addrtype") == "ipv4")
                             ?.Attribute("addr")?.Value
                       ?? host.Elements("address").FirstOrDefault()?.Attribute("addr")?.Value;
                if (string.IsNullOrWhiteSpace(ip)) continue;

                var hostname = host.Element("hostnames")?.Elements("hostname").FirstOrDefault()
                                   ?.Attribute("name")?.Value;

                var services = new List<ServiceDTO>();
                foreach (var p in host.Descendants("port"))
                {
                    var svc = p.Element("service");
                    var scripts = p.Elements("script").ToList();
                    string scriptCombined = null;
                    if (scripts.Count > 0)
                    {
                        scriptCombined = string.Join("\n", scripts.Select(s =>
                            "[" + (string)s.Attribute("id") + "]\n" + (string)s.Attribute("output")));
                    }
                    int.TryParse((string)p.Attribute("portid"), out int portNum);
                    services.Add(new ServiceDTO
                    {
                        Port = portNum,
                        Protocol = (string)p.Attribute("protocol"),
                        State = (string)p.Element("state")?.Attribute("state"),
                        Name = (string)svc?.Attribute("name"),
                        Version = (string)svc?.Attribute("version"),
                        Script = scriptCombined,
                    });
                }

                // Create a Box row if this IP is new to the team, so the
                // Home page has a row for the "Uploaded" button to attach to.
                var existingBox = await _context.Boxes.FirstOrDefaultAsync(b => b.Ip == ip);
                if (existingBox == null)
                {
                    _context.Boxes.Add(new Box
                    {
                        Ip = ip,
                        Hostname = hostname,
                        State = "up",
                    });
                    createdBox = true;
                }
                else if (string.IsNullOrEmpty(existingBox.Hostname) && !string.IsNullOrEmpty(hostname))
                {
                    // Fill in hostname if we didn't know it yet -- harmless
                    // enrichment, doesn't touch Services.
                    existingBox.Hostname = hostname;
                }

                _context.UploadedScanHost.Add(new UploadedScanHost
                {
                    ScanUploadId = scanUploadId,
                    Ip = ip,
                    Hostname = hostname,
                    ServicesJson = JsonSerializer.Serialize(services),
                });
            }

            await _context.SaveChangesAsync();
            return createdBox;
        }
    }
}
