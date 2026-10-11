using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Threading.Tasks;
using jVision.Shared.Annotations;

namespace jVision.Server.Models
{
    public class Box
    {
        public int BoxId { get; set; }
        public string UserId { get; set; }
        public ApplicationUser User { get; set; }
        [Required]
        [IpAddress]
        public string Ip { get; set; }
        public string Hostname { get; set; }
        public string State { get; set; }
        public string Comments { get; set; }
        public string Standing { get; set; }
        public string Os { get; set; }

        public string Subnet { get; set; }

        // AD/DNS domain the host belongs to (e.g. "corp.local"). Free-text,
        // nullable — operator edits it from the Box dialog.
        public string Domain { get; set; }

        // CPTC environment bucket the host belongs to (web / AD / OT / AI /
        // mobile / cloud). Drives the network topology's category grouping.
        // Nullable — hosts without a category fall into an "Other" group in
        // the diagram.
        public string Category { get; set; }

        // Progress stage in the engagement (todo/enum/foothold/privesc/owned).
        // Null = not yet triaged. Nullable string so existing rows migrate cleanly.
        public string Stage { get; set; }

        public IList<Service> Services { get; set; }

    }
}
