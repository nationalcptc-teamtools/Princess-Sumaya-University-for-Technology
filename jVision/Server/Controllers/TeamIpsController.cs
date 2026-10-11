using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using jVision.Server.Data;
using jVision.Shared.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace jVision.Server.Controllers
{
    [Route("teamips")]
    [ApiController]
    [Authorize]
    public class TeamIpsController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;

        public TeamIpsController(JvisionServerDBContext context)
        {
            _context = context;
        }

        // GET /teamips -- rows are written by OperatorIpMiddleware, never posted.
        [HttpGet]
        public async Task<ActionResult<IEnumerable<TeamIp>>> Get()
        {
            return await _context.TeamIp
                .OrderBy(t => t.Operator)
                .ThenByDescending(t => t.LastSeen)
                .ToListAsync();
        }

        // DELETE /teamips/5 -- prune an address an operator no longer uses.
        // It comes back on their next request if they connect from it again.
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var row = await _context.TeamIp.FindAsync(id);
            if (row == null) return NotFound();

            _context.TeamIp.Remove(row);
            await _context.SaveChangesAsync();
            return NoContent();
        }
    }
}
