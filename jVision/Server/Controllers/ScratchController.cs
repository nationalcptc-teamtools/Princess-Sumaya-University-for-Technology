using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using jVision.Server.Data;
using jVision.Server.Hubs;
using jVision.Shared.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace jVision.Server.Controllers
{
    [Route("scratch")]
    [ApiController]
    [Authorize]
    public class ScratchController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        public ScratchController(JvisionServerDBContext context,
                                 IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<ScratchPage>>> Get()
        {
            return await _context.ScratchPage.OrderBy(p => p.Title).ToListAsync();
        }

        [HttpPost]
        public async Task<ActionResult<ScratchPage>> Create([FromBody] ScratchPage page)
        {
            var title = (page?.Title ?? "").Trim();
            if (title.Length == 0) return BadRequest("title required");

            var created = new ScratchPage
            {
                Title = title,
                Content = page.Content ?? "",
                UpdatedBy = User.Identity?.Name ?? "unknown",
                UpdatedAt = DateTime.UtcNow,
            };

            _context.ScratchPage.Add(created);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.ScratchChanged();
            return created;
        }

        // Any authenticated operator may edit any page -- shared team scratchpad.
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ScratchPage page)
        {
            var row = await _context.ScratchPage.FindAsync(id);
            if (row == null) return NotFound();

            var title = (page?.Title ?? "").Trim();
            if (title.Length == 0) return BadRequest("title required");

            row.Title = title;
            row.Content = page.Content ?? "";
            row.UpdatedBy = User.Identity?.Name ?? "unknown";
            row.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.ScratchChanged();
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var row = await _context.ScratchPage.FindAsync(id);
            if (row == null) return NotFound();

            _context.ScratchPage.Remove(row);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.ScratchChanged();
            return NoContent();
        }
    }
}
