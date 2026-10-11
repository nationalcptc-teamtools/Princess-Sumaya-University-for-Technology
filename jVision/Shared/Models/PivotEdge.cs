using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    // A directed edge in the attack graph: we moved from SourceIp to TargetIp
    // using Technique (creds, exploit, session-passing, phishing, ...). Rendered
    // as a labeled arrow on the topology.
    public class PivotEdge
    {
        public int PivotEdgeId { get; set; }

        [Required]
        public string SourceIp { get; set; }

        [Required]
        public string TargetIp { get; set; }

        // Short technique tag: "creds", "exploit", "rce", "session", "relay",
        // "phish", "other". Kept as a string so ops can add new tags without
        // a migration.
        public string Technique { get; set; }

        // Freeform label shown on the arrow ("admin:Password1", "CVE-2023-1234").
        public string Label { get; set; }

        // Optional link to a Cred row when Technique="creds".
        public int? CredId { get; set; }

        public string CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}
