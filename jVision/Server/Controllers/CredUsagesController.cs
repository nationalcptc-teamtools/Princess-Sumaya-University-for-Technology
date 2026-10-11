using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using jVision.Server.Data;
using jVision.Server.Hubs;
using jVision.Shared.Models;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    public class CredUsagesController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        public CredUsagesController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        // GET /credusages           -> all
        // GET /credusages?credId=42 -> just this cred's usages
        [HttpGet]
        public async Task<ActionResult<IEnumerable<CredUsage>>> Get([FromQuery] int? credId)
        {
            var q = _context.CredUsage.AsQueryable();
            if (credId.HasValue) q = q.Where(u => u.CredId == credId.Value);
            return await q.OrderByDescending(u => u.TestedAt).ToListAsync();
        }

        [HttpPost]
        public async Task<ActionResult<CredUsage>> Post(CredUsage usage)
        {
            if (usage == null || usage.CredId == 0)
                return BadRequest("credId required");
            if (!await _context.Cred.AnyAsync(c => c.CredId == usage.CredId))
                return NotFound("cred not found");

            usage.Status = NormalizeStatus(usage.Status);
            usage.TestedBy = User?.Identity?.Name ?? usage.TestedBy ?? "anon";
            usage.TestedAt = DateTime.UtcNow;

            _context.CredUsage.Add(usage);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CredUsagesChanged();
            return usage;
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Put(int id, CredUsage incoming)
        {
            var u = await _context.CredUsage.FindAsync(id);
            if (u == null) return NotFound();

            u.Ip = incoming.Ip;
            u.BoxId = incoming.BoxId;
            u.Port = incoming.Port;
            u.ServiceName = incoming.ServiceName;
            u.Status = NormalizeStatus(incoming.Status);
            u.Notes = incoming.Notes;
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CredUsagesChanged();
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var u = await _context.CredUsage.FindAsync(id);
            if (u == null) return NotFound();
            _context.CredUsage.Remove(u);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CredUsagesChanged();
            return NoContent();
        }

        // Suggest hosts to try a given cred against, based on ServiceName
        // matches on tracked boxes. If the cred has already been logged (valid
        // or invalid) against a host+service, that box is filtered out so the
        // list stays fresh.
        [HttpGet("suggestions/{credId}")]
        public async Task<ActionResult<IEnumerable<object>>> Suggest(int credId, [FromQuery] string service)
        {
            var svc = (service ?? "").Trim();
            if (svc.Length == 0) return new List<object>();

            var already = await _context.CredUsage
                .Where(u => u.CredId == credId && u.ServiceName == svc)
                .Select(u => u.BoxId)
                .ToListAsync();

            var boxes = await _context.Boxes
                .Include(b => b.Services)
                .Where(b => b.Services.Any(s => s.Name == svc && s.State == "open"))
                .Where(b => !already.Contains(b.BoxId))
                .Select(b => new { boxId = b.BoxId, ip = b.Ip, hostname = b.Hostname, service = svc })
                .ToListAsync();

            return boxes.Cast<object>().ToList();
        }

        private static readonly HashSet<string> _statuses = new(StringComparer.OrdinalIgnoreCase)
        {
            "valid", "invalid", "untested"
        };

        private static string NormalizeStatus(string s)
        {
            var t = (s ?? "").Trim();
            return _statuses.Contains(t) ? t.ToLowerInvariant() : "untested";
        }
    }
}
