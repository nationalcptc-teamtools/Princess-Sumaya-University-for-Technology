using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using jVision.Server.Data;
using jVision.Shared.Models;
using Microsoft.AspNetCore.SignalR;
using jVision.Server.Hubs;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    public class CredsController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;
        public CredsController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        // Every cred must say where it came from. Enforced here as well as in
        // the UI so a direct POST can't slip an unclassified cred into the list.
        // "Created" is the origin used when the Created Accounts tab auto-mirrors
        // an account into Creds.
        public static readonly string[] Origins = { "Web", "AD", "Others", "Created" };

        private static string NormalizeOrigin(string o) =>
            Origins.FirstOrDefault(v => string.Equals(v, (o ?? "").Trim(), StringComparison.OrdinalIgnoreCase));

        // GET: api/Creds
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Cred>>> GetCred()
        {
            return await _context.Cred.ToListAsync();
        }

        /**
        // GET: api/Creds/5
        [HttpGet("{id}")]
        public async Task<ActionResult<Cred>> GetCred(int id)
        {
            var cred = await _context.Cred.FindAsync(id);

            if (cred == null)
            {
                return NotFound();
            }

            return cred;
        }
        **/
        // PUT: api/Creds/5
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        /**
        [HttpPut("{id}")]
        public async Task<IActionResult> PutCred(int id, Cred cred)
        {
            if (id != cred.CredId)
            {
                return BadRequest();
            }

            _context.Entry(cred).State = EntityState.Modified;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!CredExists(id))
                {
                    return NotFound();
                }
                else
                {
                    throw;
                }
            }

            return NoContent();
        }
        **/
        // POST: api/Creds  (or a list, for bulk paste)
        [HttpPost]
        public async Task<IActionResult> PostCred(Cred cred)
        {
            var origin = NormalizeOrigin(cred?.Origin);
            if (origin == null)
                return BadRequest("origin required: Web, AD or Others");
            cred.Origin = origin;

            // Dedup on (Type, Text, Origin) -- catches paste-the-same-list-twice,
            // while still letting the same cred be recorded for both Web and AD.
            if (await _context.Cred.AnyAsync(c => c.Type == cred.Type && c.Text == cred.Text && c.Origin == origin))
            {
                return StatusCode(200);
            }
            _context.Cred.Add(cred);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CredAdded(cred);
            return StatusCode(200);
        }

        // POST /Creds/bulk  -- accept a list of already-typed creds (usually
        // the user pasted many lines at once). Dedups per row.
        [HttpPost("bulk")]
        public async Task<ActionResult<int>> PostBulk(List<Cred> creds)
        {
            if (creds == null || creds.Count == 0) return 0;

            int added = 0;
            foreach (var c in creds)
            {
                if (string.IsNullOrWhiteSpace(c.Text)) continue;

                var origin = NormalizeOrigin(c.Origin);
                if (origin == null)
                    return BadRequest("origin required: Web, AD or Others");
                c.Origin = origin;

                if (await _context.Cred.AnyAsync(x => x.Type == c.Type && x.Text == c.Text && x.Origin == origin))
                    continue;
                _context.Cred.Add(c);
                await _context.SaveChangesAsync();
                await _hubContext.Clients.All.CredAdded(c);
                added++;
            }
            return added;
        }

        // PUT /Creds/{id}  -- currently only used to toggle Verified and edit
        // Source in place.
        [HttpPut("{id}")]
        public async Task<IActionResult> PutCred(int id, Cred cred)
        {
            var existing = await _context.Cred.FindAsync(id);
            if (existing == null) return NotFound();

            existing.Verified = cred.Verified;
            if (cred.Source != null) existing.Source = cred.Source;
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CredUpdated(existing);
            return NoContent();
        }

        // DELETE: api/Creds/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteCred(int id)
        {
            var cred = await _context.Cred.FindAsync(id);
            if (cred == null)
            {
                return NotFound();
            }

            _context.Cred.Remove(cred);
            await _context.SaveChangesAsync();
            await _hubContext.Clients.All.CredDeleted(cred.CredId);

            return NoContent();
        }

        private bool CredExists(int id)
        {
            return _context.Cred.Any(e => e.CredId == id);
        }
    }
}
