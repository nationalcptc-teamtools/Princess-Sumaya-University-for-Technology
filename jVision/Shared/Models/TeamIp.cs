using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    public class TeamIp
    {
        public int TeamIpId { get; set; }

        // jVision username, taken from the authenticated principal -- never
        // from the request body, same rule as LogEntry.Operator.
        [Required]
        public string Operator { get; set; }

        // Source address jVision observed the operator connecting from.
        [Required]
        public string Ip { get; set; }

        public DateTime FirstSeen { get; set; }

        public DateTime LastSeen { get; set; }
    }
}
