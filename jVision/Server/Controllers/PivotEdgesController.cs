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
    public class PivotEdgesController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        public PivotEdgesController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PivotEdge>>> Get()
        {
            return await _context.PivotEdge
                .OrderBy(p => p.CreatedAt)
                .ToListAsync();
        }

        [HttpPost]
        public async Task<ActionResult<PivotEdge>> Post(PivotEdge edge)
        {
            if (string.IsNullOrWhiteSpace(edge?.SourceIp) || string.IsNullOrWhiteSpace(edge?.TargetIp))
                return BadRequest("source and target IPs required");

            edge.CreatedBy = User?.Identity?.Name ?? edge.CreatedBy ?? "anon";
            edge.CreatedAt = DateTime.UtcNow;
            edge.SourceIp = edge.SourceIp.Trim();
            edge.TargetIp = edge.TargetIp.Trim();
            edge.Technique = string.IsNullOrWhiteSpace(edge.Technique) ? "other" : edge.Technique.Trim();

            _context.PivotEdge.Add(edge);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.PivotEdgesChanged();
            return edge;
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var e = await _context.PivotEdge.FindAsync(id);
            if (e == null) return NotFound();
            _context.PivotEdge.Remove(e);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.PivotEdgesChanged();
            return NoContent();
        }
    }
}
