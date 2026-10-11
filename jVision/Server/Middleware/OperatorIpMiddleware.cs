using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using jVision.Server.Data;
using jVision.Shared.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace jVision.Server.Middleware
{
    // Stamps operator -> source-address pairs for the Team IPs page. Runs on
    // every authenticated request, so an operator shows up whether they push
    // logs with the sync daemon or just open the web UI.
    public class OperatorIpMiddleware
    {
        private readonly RequestDelegate _next;

        // Without this, every request would round-trip the DB just to bump
        // LastSeen. Key is "operator|ip".
        private static readonly ConcurrentDictionary<string, DateTime> _seen =
            new ConcurrentDictionary<string, DateTime>();
        private static readonly TimeSpan RefreshAfter = TimeSpan.FromMinutes(5);

        public OperatorIpMiddleware(RequestDelegate next) => _next = next;

        public async Task InvokeAsync(HttpContext ctx)
        {
            await Record(ctx);
            await _next(ctx);
        }

        private static async Task Record(HttpContext ctx)
        {
            if (ctx.User?.Identity?.IsAuthenticated != true) return;

            var op = ctx.User.Identity.Name;
            var addr = ctx.Connection.RemoteIpAddress;
            if (IsThisHost(addr)) return;

            var ip = Normalize(addr);
            if (string.IsNullOrEmpty(op) || string.IsNullOrEmpty(ip)) return;

            var now = DateTime.UtcNow;
            var key = op + "|" + ip;
            if (_seen.TryGetValue(key, out var last) && now - last < RefreshAfter) return;
            _seen[key] = now;

            var db = ctx.RequestServices.GetService<JvisionServerDBContext>();
            if (db == null) return;

            try
            {
                var row = await db.TeamIp.FirstOrDefaultAsync(t => t.Operator == op && t.Ip == ip);
                if (row == null)
                    db.TeamIp.Add(new TeamIp { Operator = op, Ip = ip, FirstSeen = now, LastSeen = now });
                else
                    row.LastSeen = now;

                await db.SaveChangesAsync();
            }
            catch (DbUpdateException)
            {
                // Two concurrent first-requests from the same operator can both
                // miss the row and race the unique index. Losing one is fine --
                // the winner already recorded the pair.
                _seen.TryRemove(key, out _);
            }
        }

        private static string Normalize(IPAddress addr)
        {
            if (addr == null) return null;
            if (addr.IsIPv4MappedToIPv6) addr = addr.MapToIPv4();
            return addr.ToString();
        }

        // Browsing jVision from the same machine that hosts the container makes
        // the request arrive from the Docker bridge gateway, which is the host
        // itself rather than any operator. Matching the actual gateway rather
        // than blanket-excluding 172.16/12 matters: an engagement network can
        // legitimately live in that range, and we must not drop real operators.
        private static bool IsThisHost(IPAddress addr)
        {
            if (addr == null) return true;
            if (IPAddress.IsLoopback(addr)) return true;

            var gw = _gateway.Value;
            return gw != null && gw.Equals(addr.IsIPv4MappedToIPv6 ? addr.MapToIPv4() : addr);
        }

        private static readonly Lazy<IPAddress> _gateway = new Lazy<IPAddress>(ReadDefaultGateway);

        // /proc/net/route, tab-separated: the default route is the row whose
        // Destination is all zeroes. Gateway is a little-endian hex u32.
        private static IPAddress ReadDefaultGateway()
        {
            try
            {
                foreach (var line in File.ReadAllLines("/proc/net/route").Skip(1))
                {
                    var f = line.Split(new[] { '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    if (f.Length < 3 || f[1] != "00000000" || f[2] == "00000000") continue;
                    return new IPAddress(BitConverter.GetBytes(Convert.ToUInt32(f[2], 16)));
                }
            }
            catch (IOException)
            {
                // Not on Linux, or /proc unavailable. Loopback filtering still applies.
            }
            return null;
        }
    }
}
