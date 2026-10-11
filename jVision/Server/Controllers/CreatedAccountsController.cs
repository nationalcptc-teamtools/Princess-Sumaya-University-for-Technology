using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.SignalR;
using jVision.Server.Data;
using jVision.Server.Hubs;
using jVision.Shared.Models;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    public class CreatedAccountsController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;

        public CreatedAccountsController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<CreatedAccount>>> Get()
        {
            return await _context.CreatedAccount
                .OrderByDescending(a => a.CreatedAt)
                .ToListAsync();
        }

        [HttpPost]
        public async Task<ActionResult<CreatedAccount>> Post(CreatedAccount acc)
        {
            if (string.IsNullOrWhiteSpace(acc?.Username))
                return BadRequest("username required");

            acc.CreatedBy = User?.Identity?.Name ?? acc.CreatedBy ?? "anon";
            acc.CreatedAt = DateTime.UtcNow;

            // Mirror to Cred with Origin="Created" so the Credentials tab has
            // one place to see every credential we know about. LinkedCredId
            // stays as the FK so edits/deletes stay in sync.
            var mirrored = new Cred
            {
                Text = FormatCredText(acc),
                Type = "user/pass",
                Source = FormatCredSource(acc),
                Origin = "Created",
                Verified = true,
            };
            _context.Cred.Add(mirrored);
            await _context.SaveChangesAsync();
            acc.LinkedCredId = mirrored.CredId;

            _context.CreatedAccount.Add(acc);
            await _context.SaveChangesAsync();

            await _hubContext.Clients.All.CredAdded(mirrored);
            await _hubContext.Clients.All.CreatedAccountsChanged();
            return acc;
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Put(int id, CreatedAccount incoming)
        {
            var acc = await _context.CreatedAccount.FindAsync(id);
            if (acc == null) return NotFound();

            acc.BoxId = incoming.BoxId;
            acc.Ip = incoming.Ip;
            acc.Service = incoming.Service;
            acc.Username = incoming.Username;
            acc.Password = incoming.Password;
            acc.Privilege = incoming.Privilege;
            acc.Notes = incoming.Notes;

            // Keep the mirrored cred in sync.
            if (acc.LinkedCredId is int credId)
            {
                var mirrored = await _context.Cred.FindAsync(credId);
                if (mirrored != null)
                {
                    mirrored.Text = FormatCredText(acc);
                    mirrored.Source = FormatCredSource(acc);
                    await _context.SaveChangesAsync();
                    await _hubContext.Clients.All.CredUpdated(mirrored);
                }
            }

            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CreatedAccountsChanged();
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var acc = await _context.CreatedAccount.FindAsync(id);
            if (acc == null) return NotFound();

            // Remove the mirrored Cred alongside so the two lists don't drift.
            if (acc.LinkedCredId is int credId)
            {
                var mirrored = await _context.Cred.FindAsync(credId);
                if (mirrored != null)
                {
                    _context.Cred.Remove(mirrored);
                    await _hubContext.Clients.All.CredDeleted(credId);
                }
            }

            _context.CreatedAccount.Remove(acc);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CreatedAccountsChanged();
            return NoContent();
        }

        // "user:pass" is the shape the Credies page's Pairs column expects.
        private static string FormatCredText(CreatedAccount a)
        {
            var u = (a.Username ?? "").Trim();
            var p = (a.Password ?? "").Trim();
            return string.IsNullOrEmpty(p) ? u : $"{u}:{p}";
        }

        private static string FormatCredSource(CreatedAccount a)
        {
            var parts = new List<string> { "Created" };
            if (!string.IsNullOrWhiteSpace(a.Service)) parts.Add(a.Service);
            if (!string.IsNullOrWhiteSpace(a.Ip)) parts.Add($"on {a.Ip}");
            if (!string.IsNullOrWhiteSpace(a.Privilege)) parts.Add($"({a.Privilege})");
            return string.Join(" ", parts);
        }
    }
}
