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
        // POST: api/Creds
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPost]
        public async Task<ActionResult<Cred>> PostCred(Cred cred)
        {
            _context.Cred.Add(cred);
            await _context.SaveChangesAsync();

            //return CreatedAtAction("GetCred", new { id = cred.CredId }, cred);
            await _hubContext.Clients.All.CredAdded(cred);
            return StatusCode(200);
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
