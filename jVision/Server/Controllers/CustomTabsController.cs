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
    // Team-shared, run-time defined nav tabs. Any authenticated operator can
    // create, edit, or delete a tab -- it's a collaborative surface, same trust
    // model as ScratchPage.
    [Route("customtabs")]
    [ApiController]
    [Authorize]
    public class CustomTabsController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        public CustomTabsController(JvisionServerDBContext context,
                                    IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<CustomTab>>> Get()
        {
            return await _context.CustomTab.OrderBy(t => t.CreatedAt).ToListAsync();
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<CustomTab>> GetOne(int id)
        {
            var row = await _context.CustomTab.FindAsync(id);
            if (row == null) return NotFound();
            return row;
        }

        [HttpPost]
        public async Task<ActionResult<CustomTab>> Create([FromBody] CustomTab tab)
        {
            var title = (tab?.Title ?? "").Trim();
            if (title.Length == 0) return BadRequest("title required");

            var now = DateTime.UtcNow;
            var who = User.Identity?.Name ?? "unknown";
            var created = new CustomTab
            {
                Title = title,
                Icon = (tab.Icon ?? "").Trim(),
                Content = tab.Content ?? "",
                CreatedBy = who,
                CreatedAt = now,
                UpdatedBy = who,
                UpdatedAt = now,
            };
            _context.CustomTab.Add(created);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CustomTabsChanged();
            return created;
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] CustomTab tab)
        {
            var row = await _context.CustomTab.FindAsync(id);
            if (row == null) return NotFound();

            var title = (tab?.Title ?? "").Trim();
            if (title.Length == 0) return BadRequest("title required");

            row.Title = title;
            row.Icon = (tab.Icon ?? "").Trim();
            row.Content = tab.Content ?? "";
            row.UpdatedBy = User.Identity?.Name ?? "unknown";
            row.UpdatedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CustomTabsChanged();
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var row = await _context.CustomTab.FindAsync(id);
            if (row == null) return NotFound();
            _context.CustomTab.Remove(row);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CustomTabsChanged();
            return NoContent();
        }
    }
}
